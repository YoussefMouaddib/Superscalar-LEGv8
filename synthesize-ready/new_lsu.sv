`timescale 1ns/1ps
import core_pkg::*;

module lsu #(
    parameter int LQ_ENTRIES = 8,
    parameter int SQ_ENTRIES = 8,
    parameter int XLEN = 32,
    parameter int COMMIT_W = 2,
    parameter int ROB_ENTRIES = 16
)(
    input  logic        clk,
    input  logic        reset,
    
    input  logic        flush_pipeline,
    
    // Allocation interface (from dispatch)
    input  logic        alloc_en,
    input  logic        is_load,
    input  logic [7:0]  opcode,
    
    input  logic [5:0]  base_addr_tag,
    input  logic        base_addr_ready,
    input  logic [XLEN-1:0] base_addr_value,
    
    input  logic [XLEN-1:0] offset,
    input  logic [XLEN-1:0] store_data_value,
    input  logic [5:0]  store_data_tag,
    input  logic        store_data_ready,
    input  logic [4:0]  arch_rs1,
    input  logic [4:0]  arch_rs2,
    input  logic [4:0]  arch_rd,
    input  logic [5:0]  phys_rd,
    input  logic [5:0]  rob_idx,
    
    // CDB interface (for wakeup)
    input  logic [1:0]       cdb_valid,
    input  logic [1:0][5:0]  cdb_tag,
    input  logic [1:0][31:0] cdb_value,
    
    // CDB output (for load results)
    output logic        cdb_req,
    output logic [5:0]  cdb_req_tag,
    output logic [XLEN-1:0] cdb_req_value,
    output logic        cdb_req_exception,
    
    // ROB interface
    input  logic [COMMIT_W-1:0]  commit_en,
    input  logic [COMMIT_W-1:0]  commit_is_store,
    input  logic [COMMIT_W-1:0][$clog2(ROB_ENTRIES)-1:0] commit_rob_idx,
    
    output logic        lsu_exception,
    output logic [4:0]  lsu_exception_cause,
    
    // Memory interface
    output logic        mem_req,
    output logic        mem_we,
    output logic [XLEN-1:0] mem_addr,
    output logic [XLEN-1:0] mem_wdata,
    input  logic        mem_ready,
    input  logic [XLEN-1:0] mem_rdata,
    input  logic        mem_error
);

    // ============================================================
    // Queue Entry Definitions
    // ============================================================
    typedef struct packed {
        logic valid;
        logic [XLEN-1:0] addr;
        logic [5:0] dest_tag;
        logic [5:0] rob_idx;
        logic completed;
        logic [XLEN-1:0] data;
        logic exception;
    } lq_entry_t;

    typedef struct packed {
        logic valid;
        logic [5:0] base_tag;
        logic base_ready;
        logic [XLEN-1:0] base_val;
        logic [5:0] data_tag;
        logic data_ready;
        logic [XLEN-1:0] data_val;
        logic [XLEN-1:0] offset;
        logic [XLEN-1:0] addr;
        logic addr_computed;
        logic [5:0] rob_idx;
        logic committed;
        logic exception;
    } sq_entry_t;

    lq_entry_t lq [0:LQ_ENTRIES-1];
    sq_entry_t sq [0:SQ_ENTRIES-1];

    logic [2:0] lq_head, lq_tail;
    logic [2:0] sq_head, sq_tail;

    // ============================================================
    // Allocation Logic
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [XLEN-1:0] calc_addr;
        
        if (reset) begin
            for (int i = 0; i < LQ_ENTRIES; i++) begin
                lq[i].valid <= 1'b0;
                lq[i].completed <= 1'b0;
            end
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                sq[i].valid <= 1'b0;
                sq[i].committed <= 1'b0;
                sq[i].addr_computed <= 1'b0;
            end
            lq_head <= '0;
            lq_tail <= '0;
            sq_head <= '0;
            sq_tail <= '0;
            
        end else if (flush_pipeline) begin
            // Flush all loads (speculative)
            for (int i = 0; i < LQ_ENTRIES; i++) begin
                lq[i].valid <= 1'b0;
                lq[i].completed <= 1'b0;
            end
            
            // Flush uncommitted stores
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (!sq[i].committed) begin
                    sq[i].valid <= 1'b0;
                end
            end
            
            lq_head <= '0;
            lq_tail <= '0;
            sq_tail <= sq_head;
            
        end else begin
            // Allocate to queues
            if (alloc_en && !flush_pipeline) begin
                if (is_load) begin
                    // LOADS: Compute address immediately if ready, else wait
                    if (base_addr_ready) begin
                        calc_addr = base_addr_value + offset;
                        lq[lq_tail].valid <= 1'b1;
                        lq[lq_tail].addr <= calc_addr;
                        lq[lq_tail].dest_tag <= phys_rd;
                        lq[lq_tail].rob_idx <= rob_idx;
                        lq[lq_tail].completed <= 1'b0;
                        lq[lq_tail].exception <= (calc_addr[1:0] != 2'b00);
                        lq_tail <= lq_tail + 1;
                    end
                    // NOTE: If base not ready, could add wakeup logic for loads too
                    // For now, loads assume base is always ready (common case)
                    
                end else begin
                    // STORES: Always allocate, track operand tags
                    sq[sq_tail].valid <= 1'b1;
                    sq[sq_tail].base_tag <= base_addr_tag;
                    sq[sq_tail].base_ready <= base_addr_ready;
                    sq[sq_tail].base_val <= base_addr_value;
                    sq[sq_tail].data_tag <= store_data_tag;
                    sq[sq_tail].data_ready <= store_data_ready;
                    sq[sq_tail].data_val <= store_data_value;
                    sq[sq_tail].offset <= offset;
                    sq[sq_tail].addr <= '0;
                    sq[sq_tail].addr_computed <= 1'b0;
                    sq[sq_tail].rob_idx <= rob_idx;
                    sq[sq_tail].committed <= 1'b0;
                    sq[sq_tail].exception <= 1'b0;
                    sq_tail <= sq_tail + 1;
                end
            end

            // Mark stores as committed from ROB
            for (int c = 0; c < COMMIT_W; c++) begin
                if (commit_en[c] && commit_is_store[c]) begin
                    for (int i = 0; i < SQ_ENTRIES; i++) begin
                        if (sq[i].valid && sq[i].rob_idx == commit_rob_idx[c]) begin
                            sq[i].committed <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    // ============================================================
    // CDB Wakeup Logic for Store Operands
    // ============================================================
    always_ff @(posedge clk) begin
        automatic logic [XLEN-1:0] calc_addr;
        
        if (!reset && !flush_pipeline) begin
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (sq[i].valid) begin
                    // Wakeup base address
                    for (int j = 0; j < 2; j++) begin
                        if (cdb_valid[j] && !sq[i].base_ready && sq[i].base_tag == cdb_tag[j]) begin
                            sq[i].base_val <= cdb_value[j];
                            sq[i].base_ready <= 1'b1;
                        end
                    end
                    
                    // Wakeup store data
                    for (int j = 0; j < 2; j++) begin
                        if (cdb_valid[j] && !sq[i].data_ready && sq[i].data_tag == cdb_tag[j]) begin
                            sq[i].data_val <= cdb_value[j];
                            sq[i].data_ready <= 1'b1;
                        end
                    end
                    
                    // Compute address when base is ready
                    if (sq[i].base_ready && !sq[i].addr_computed) begin
                        calc_addr = sq[i].base_val + sq[i].offset;
                        sq[i].addr <= calc_addr;
                        sq[i].addr_computed <= 1'b1;
                        sq[i].exception <= (calc_addr[1:0] != 2'b00);
                    end
                end
            end
        end
    end

    // ============================================================
    // Memory Access State Machine
    // ============================================================
    typedef enum logic [1:0] {
        MEM_IDLE,
        MEM_LOAD,
        MEM_STORE
    } mem_state_t;

    mem_state_t mem_state;
    logic [2:0] active_lq_idx;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_state <= MEM_IDLE;
            mem_req <= 1'b0;
            mem_we <= 1'b0;
            cdb_req <= 1'b0;
            cdb_req_tag <= '0;
            cdb_req_value <= '0;
            cdb_req_exception <= 1'b0;
            
        end else if (flush_pipeline) begin
            mem_state <= MEM_IDLE;
            mem_req <= 1'b0;
            mem_we <= 1'b0;
            cdb_req <= 1'b0;
            
        end else begin
            cdb_req <= 1'b0;
            
            case (mem_state)
                MEM_IDLE: begin
                    // PRIORITY 1: Execute loads
                    for (int i = 0; i < LQ_ENTRIES; i++) begin
                        automatic int idx = (lq_head + i) % LQ_ENTRIES;
                        if (lq[idx].valid && !lq[idx].completed && !lq[idx].exception) begin
                            active_lq_idx <= idx;
                            mem_state <= MEM_LOAD;
                            mem_req <= 1'b1;
                            mem_we <= 1'b0;
                            mem_addr <= lq[idx].addr;
                            break;
                        end
                    end
                    
                    // PRIORITY 2: Execute committed stores (only if no loads)
                    if (mem_state == MEM_IDLE) begin
                        for (int i = 0; i < SQ_ENTRIES; i++) begin
                            automatic int idx = (sq_head + i) % SQ_ENTRIES;
                            if (sq[idx].valid && sq[idx].committed && 
                                sq[idx].addr_computed && sq[idx].data_ready && 
                                !sq[idx].exception) begin
                                mem_state <= MEM_STORE;
                                mem_req <= 1'b1;
                                mem_we <= 1'b1;
                                mem_addr <= sq[idx].addr;
                                mem_wdata <= sq[idx].data_val;
                                break;
                            end
                        end
                    end
                end
                
                MEM_LOAD: begin
                    if (mem_ready) begin
                        mem_req <= 1'b0;
                        lq[active_lq_idx].completed <= 1'b1;
                        lq[active_lq_idx].data <= mem_rdata;
                        cdb_req <= 1'b1;
                        cdb_req_tag <= lq[active_lq_idx].dest_tag;
                        cdb_req_value <= mem_rdata;
                        cdb_req_exception <= mem_error;
                        lq[active_lq_idx].valid <= 1'b0;
                        lq_head <= lq_head + 1;
                        mem_state <= MEM_IDLE;
                    end
                end
                
                MEM_STORE: begin
                    if (mem_ready) begin
                        mem_req <= 1'b0;
                        // Remove completed store from queue
                        for (int i = 0; i < SQ_ENTRIES; i++) begin
                            if (sq[i].valid && sq[i].committed && sq[i].addr == mem_addr) begin
                                sq[i].valid <= 1'b0;
                                sq_head <= sq_head + 1;
                                break;
                            end
                        end
                        mem_state <= MEM_IDLE;
                    end
                end
                
                default: mem_state <= MEM_IDLE;
            endcase
        end
    end

    // ============================================================
    // Exception Handling
    // ============================================================
    always_comb begin
        lsu_exception = 1'b0;
        lsu_exception_cause = '0;
        
        for (int i = 0; i < LQ_ENTRIES; i++) begin
            if (lq[i].valid && lq[i].exception) begin
                lsu_exception = 1'b1;
                lsu_exception_cause = 5'h1;
            end
        end
        
        for (int i = 0; i < SQ_ENTRIES; i++) begin
            if (sq[i].valid && sq[i].exception) begin
                lsu_exception = 1'b1;
                lsu_exception_cause = 5'h2;
            end
        end
        
        if (mem_error) begin
            lsu_exception = 1'b1;
            lsu_exception_cause = 5'h3;
        end
    end

endmodule
