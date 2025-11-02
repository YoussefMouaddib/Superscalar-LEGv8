`timescale 1ns/1ps
import core_pkg::*;

module lsu #(
    parameter int LQ_ENTRIES = 8,
    parameter int SQ_ENTRIES = 8,
    parameter int XLEN = 32
)(
    input  logic        clk,
    input  logic        reset,
    
    // Allocation interface (from decode/rename)
    input  logic        alloc_en,
    input  logic        is_load,        // 1=load, 0=store
    input  logic [7:0]  opcode,         // LDR, STR, CAS
    input  logic [XLEN-1:0] base_addr,
    input  logic [XLEN-1:0] offset,
    input  logic [4:0]  arch_rs1,       // for address
    input  logic [4:0]  arch_rs2,       // for store data
    input  logic [4:0]  arch_rd,        // for load destination
    input  logic [5:0]  phys_rd,        // physical destination
    input  logic [5:0]  rob_idx,
    
    // PRF interface (for store data)
    input  logic [XLEN-1:0] store_data_val,
    input  logic        store_data_ready,
    
    // CDB interface (for load results and store completion)
    output logic        cdb_valid,
    output logic [5:0]  cdb_tag,
    output logic [XLEN-1:0] cdb_value,
    output logic        cdb_exception,
    
    // ROB interface (for commit and exceptions)
    input  logic        commit_en,
    input  logic        commit_is_store,
    input  logic [5:0]  commit_rob_idx,
    output logic        lsu_exception,
    output logic [4:0]  lsu_exception_cause,
    
    // Memory interface (scratchpad)
    output logic        mem_req,
    output logic        mem_we,
    output logic [XLEN-1:0] mem_addr,
    output logic [XLEN-1:0] mem_wdata,
    input  logic        mem_ready,
    input  logic [XLEN-1:0] mem_rdata,
    input  logic        mem_error
);

// Load Queue Entry
typedef struct packed {
    logic valid;
    logic [XLEN-1:0] addr;
    logic [5:0] dest_tag;
    logic [5:0] rob_idx;
    logic completed;
    logic [XLEN-1:0] data;
    logic exception;
    logic is_cas;
} lq_entry_t;

// Store Queue Entry  
typedef struct packed {
    logic valid;
    logic [XLEN-1:0] addr;
    logic [XLEN-1:0] data;
    logic [5:0] rob_idx;
    logic committed;
    logic exception;
    logic is_cas;
    logic [XLEN-1:0] cas_compare;  // For CAS compare value
} sq_entry_t;

lq_entry_t lq [0:LQ_ENTRIES-1];
sq_entry_t sq [0:SQ_ENTRIES-1];

logic [2:0] lq_head, lq_tail;
logic [2:0] sq_head, sq_tail;
logic [XLEN-1:0] agen_addr;
logic agen_misaligned;

// Address Generation
always_comb begin
    agen_addr = base_addr + offset;
    // Check 32-bit alignment (address[1:0] == 2'b00)
    agen_misaligned = (agen_addr[1:0] != 2'b00);
end

// ============================================================
// Load-Store Queue Allocation
// ============================================================
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        for (int i = 0; i < LQ_ENTRIES; i++) begin
            lq[i].valid <= 1'b0;
            lq[i].completed <= 1'b0;
        end
        for (int i = 0; i < SQ_ENTRIES; i++) begin
            sq[i].valid <= 1'b0;
            sq[i].committed <= 1'b0;
        end
        lq_head <= '0;
        lq_tail <= '0;
        sq_head <= '0;
        sq_tail <= '0;
    end else begin
        // Load/Store Allocation
        if (alloc_en) begin
            if (is_load) begin
                // Allocate to Load Queue
                lq[lq_tail].valid <= 1'b1;
                lq[lq_tail].addr <= agen_addr;
                lq[lq_tail].dest_tag <= phys_rd;
                lq[lq_tail].rob_idx <= rob_idx;
                lq[lq_tail].completed <= 1'b0;
                lq[lq_tail].exception <= agen_misaligned;
                lq[lq_tail].is_cas <= (opcode == 8'h30); // CAS opcode
                lq_tail <= lq_tail + 1;
            end else begin
                // Allocate to Store Queue
                sq[sq_tail].valid <= 1'b1;
                sq[sq_tail].addr <= agen_addr;
                sq[sq_tail].data <= store_data_val;
                sq[sq_tail].rob_idx <= rob_idx;
                sq[sq_tail].committed <= 1'b0;
                sq[sq_tail].exception <= agen_misaligned;
                sq[sq_tail].is_cas <= (opcode == 8'h30); // CAS opcode
                if (opcode == 8'h30) begin
                    sq[sq_tail].cas_compare <= store_data_val; // For CAS compare
                end
                sq_tail <= sq_tail + 1;
            end
        end

        // Process committed stores from ROB
        if (commit_en && commit_is_store) begin
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (sq[i].valid && sq[i].rob_idx == commit_rob_idx) begin
                    sq[i].committed <= 1'b1;
                end
            end
        end
    end
end

// ============================================================
// Store-to-Load Forwarding Logic
// ============================================================
function logic [XLEN-1:0] check_forwarding(input logic [XLEN-1:0] load_addr);
    logic [XLEN-1:0] forwarded_data;
    logic forward_found;
    
    forwarded_data = '0;
    forward_found = 1'b0;
    
    // Search Store Queue for matching addresses (youngest older store wins)
    for (int i = 0; i < SQ_ENTRIES; i++) begin
        if (sq[i].valid && !sq[i].exception && 
            sq[i].addr == load_addr && sq[i].committed) begin
            forwarded_data = sq[i].data;
            forward_found = 1'b1;
        end
    end
    
    return forward_found ? forwarded_data : 'x;
endfunction

// ============================================================
// Memory Access Pipeline
// ============================================================
typedef enum logic [2:0] {
    MEM_IDLE,
    MEM_READ,
    MEM_WRITE,
    MEM_CAS_READ,
    MEM_CAS_COMPARE,
    MEM_CAS_WRITE,
    MEM_MMIO
} mem_state_t;

mem_state_t mem_state;
logic [2:0] mem_lq_index;
logic [XLEN-1:0] cas_read_value;
logic [3:0] mmio_counter;

// CDB outputs
logic cdb_valid_next;
logic [5:0] cdb_tag_next;
logic [XLEN-1:0] cdb_value_next;
logic cdb_exception_next;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        mem_state <= MEM_IDLE;
        mem_req <= 1'b0;
        mem_we <= 1'b0;
        cdb_valid <= 1'b0;
        mmio_counter <= '0;
    end else begin
        cdb_valid <= cdb_valid_next;
        cdb_tag <= cdb_tag_next;
        cdb_value <= cdb_value_next;
        cdb_exception <= cdb_exception_next;
        
        // Default CDB values
        cdb_valid_next <= 1'b0;
        cdb_exception_next <= 1'b0;

        case (mem_state)
            MEM_IDLE: begin
                // Look for next load to process
                for (int i = 0; i < LQ_ENTRIES; i++) begin
                    int index = (lq_head + i) % LQ_ENTRIES;
                    if (lq[index].valid && !lq[index].completed && !lq[index].exception) begin
                        mem_lq_index <= index;
                        
                        // Check for store-to-load forwarding first
                        automatic logic [XLEN-1:0] forwarded_data = 
                            check_forwarding(lq[index].addr);
                        
                        if (forwarded_data !== 'x) begin
                            // Forward from store queue
                            lq[index].completed <= 1'b1;
                            lq[index].data <= forwarded_data;
                            cdb_valid_next <= 1'b1;
                            cdb_tag_next <= lq[index].dest_tag;
                            cdb_value_next <= forwarded_data;
                            lq_head <= lq_head + 1;
                        end else if (lq[index].is_cas) begin
                            // CAS operation - start 3-stage pipeline
                            mem_state <= MEM_CAS_READ;
                            mem_req <= 1'b1;
                            mem_we <= 1'b0;
                            mem_addr <= lq[index].addr;
                        end else begin
                            // Regular load - check if it's MMIO
                            if (lq[index].addr[31:28] == 4'hF) begin
                                // MMIO space - start MMIO access
                                mem_state <= MEM_MMIO;
                                mmio_counter <= 4'd4;
                            end else begin
                                // Scratchpad access
                                mem_state <= MEM_READ;
                                mem_req <= 1'b1;
                                mem_we <= 1'b0;
                                mem_addr <= lq[index].addr;
                            end
                        end
                        break;
                    end
                end
            end
            
            MEM_READ: begin
                if (mem_ready) begin
                    mem_req <= 1'b0;
                    lq[mem_lq_index].completed <= 1'b1;
                    lq[mem_lq_index].data <= mem_rdata;
                    cdb_valid_next <= 1'b1;
                    cdb_tag_next <= lq[mem_lq_index].dest_tag;
                    cdb_value_next <= mem_rdata;
                    cdb_exception_next <= mem_error;
                    lq_head <= lq_head + 1;
                    mem_state <= MEM_IDLE;
                end
            end
            
            MEM_CAS_READ: begin
                if (mem_ready) begin
                    mem_req <= 1'b0;
                    cas_read_value <= mem_rdata;
                    mem_state <= MEM_CAS_COMPARE;
                end
            end
            
            MEM_CAS_COMPARE: begin
                // Find corresponding store queue entry for CAS
                for (int i = 0; i < SQ_ENTRIES; i++) begin
                    if (sq[i].valid && sq[i].rob_idx == lq[mem_lq_index].rob_idx) begin
                        if (cas_read_value == sq[i].cas_compare) begin
                            // Compare successful - proceed with write
                            mem_state <= MEM_CAS_WRITE;
                            mem_req <= 1'b1;
                            mem_we <= 1'b1;
                            mem_addr <= lq[mem_lq_index].addr;
                            mem_wdata <= sq[i].data;
                        end else begin
                            // Compare failed - complete load with read value
                            lq[mem_lq_index].completed <= 1'b1;
                            lq[mem_lq_index].data <= cas_read_value;
                            cdb_valid_next <= 1'b1;
                            cdb_tag_next <= lq[mem_lq_index].dest_tag;
                            cdb_value_next <= cas_read_value;
                            lq_head <= lq_head + 1;
                            mem_state <= MEM_IDLE;
                        end
                        break;
                    end
                end
            end
            
            MEM_CAS_WRITE: begin
                if (mem_ready) begin
                    mem_req <= 1'b0;
                    // CAS succeeded - complete with the written value
                    lq[mem_lq_index].completed <= 1'b1;
                    for (int i = 0; i < SQ_ENTRIES; i++) begin
                        if (sq[i].valid && sq[i].rob_idx == lq[mem_lq_index].rob_idx) begin
                            lq[mem_lq_index].data <= sq[i].data;
                            break;
                        end
                    end
                    cdb_valid_next <= 1'b1;
                    cdb_tag_next <= lq[mem_lq_index].dest_tag;
                    for (int i = 0; i < SQ_ENTRIES; i++) begin
                        if (sq[i].valid && sq[i].rob_idx == lq[mem_lq_index].rob_idx) begin
                            cdb_value_next <= sq[i].data;
                            break;
                        end
                    end
                    lq_head <= lq_head + 1;
                    mem_state <= MEM_IDLE;
                end
            end
            
            MEM_MMIO: begin
                if (mmio_counter > 0) begin
                    mmio_counter <= mmio_counter - 1;
                end else begin
                    // MMIO access complete - return dummy value
                    lq[mem_lq_index].completed <= 1'b1;
                    lq[mem_lq_index].data <= 32'hDEADBEEF;
                    cdb_valid_next <= 1'b1;
                    cdb_tag_next <= lq[mem_lq_index].dest_tag;
                    cdb_value_next <= 32'hDEADBEEF;
                    lq_head <= lq_head + 1;
                    mem_state <= MEM_IDLE;
                end
            end
            
            default: mem_state <= MEM_IDLE;
        endcase
        
        // Process committed stores (write to memory)
        if (commit_en && commit_is_store) begin
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (sq[i].valid && sq[i].rob_idx == commit_rob_idx && 
                    !sq[i].is_cas && mem_state == MEM_IDLE) begin
                    // Write store to memory (non-CAS stores only)
                    mem_state <= MEM_WRITE;
                    mem_req <= 1'b1;
                    mem_we <= 1'b1;
                    mem_addr <= sq[i].addr;
                    mem_wdata <= sq[i].data;
                    // Remove from SQ after write
                    sq[i].valid <= 1'b0;
                    sq_head <= sq_head + 1;
                    break;
                end
            end
        end
        
        // Memory write completion
        if (mem_state == MEM_WRITE && mem_ready) begin
            mem_req <= 1'b0;
            mem_state <= MEM_IDLE;
        end
    end
end

// ============================================================
// Exception Handling
// ============================================================
always_comb begin
    lsu_exception = 1'b0;
    lsu_exception_cause = '0;
    
    // Check for misaligned accesses in LQ/SQ
    for (int i = 0; i < LQ_ENTRIES; i++) begin
        if (lq[i].valid && lq[i].exception) begin
            lsu_exception = 1'b1;
            lsu_exception_cause = 5'h1; // Misaligned load
        end
    end
    
    for (int i = 0; i < SQ_ENTRIES; i++) begin
        if (sq[i].valid && sq[i].exception) begin
            lsu_exception = 1'b1;
            lsu_exception_cause = 5'h2; // Misaligned store
        end
    end
    
    // Memory errors
    if (mem_error) begin
        lsu_exception = 1'b1;
        lsu_exception_cause = 5'h3; // Memory error
    end
end

// ============================================================
// Queue Management
// ============================================================
// Remove completed loads from LQ
always_ff @(posedge clk) begin
    for (int i = 0; i < LQ_ENTRIES; i++) begin
        if (lq[i].valid && lq[i].completed) begin
            lq[i].valid <= 1'b0;
        end
    end
end

// Remove committed CAS operations from SQ
always_ff @(posedge clk) begin
    for (int i = 0; i < SQ_ENTRIES; i++) begin
        if (sq[i].valid && sq[i].committed && sq[i].is_cas) begin
            sq[i].valid <= 1'b0;
        end
    end
end

endmodule
