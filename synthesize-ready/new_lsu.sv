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
    
    // Allocation interface
    input  logic        alloc_en,
    input  logic        is_load,
    input  logic [7:0]  opcode,
    input  logic [5:0]  base_addr_tag,
    input  logic        base_addr_ready,
    input  logic [XLEN-1:0] base_addr_value,
    input  logic [XLEN-1:0] store_data_value,
    input  logic [5:0]  store_data_tag,
    input  logic        store_data_ready,
    input  logic [XLEN-1:0] offset,
    input  logic [4:0]  arch_rs1,
    input  logic [4:0]  arch_rs2,
    input  logic [4:0]  arch_rd,
    input  logic [5:0]  phys_rd,
    input  logic [5:0]  rob_idx,
    
    // CDB wakeup
    input  logic [1:0]       cdb_valid,
    input  logic [1:0][5:0]  cdb_tag,
    input  logic [1:0][31:0] cdb_value,
    
    // CDB output
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
    // Queue Structures
    // ============================================================
    typedef struct packed {
        logic valid;
        logic [5:0] dest_tag;
        logic [5:0] rob_idx;
        logic [5:0] base_tag;
        logic       base_ready;
        logic [XLEN-1:0] base_val;
        logic [XLEN-1:0] offset;
        logic addr_valid;
        logic [XLEN-1:0] addr;
        logic executing;
        logic exception;
    } lq_entry_t;

    typedef struct packed {
        logic valid;
        logic [5:0] rob_idx;
        logic [5:0] base_tag;
        logic       base_ready;
        logic [XLEN-1:0] base_val;
        logic [5:0] data_tag;
        logic       data_ready;
        logic [XLEN-1:0] data_val;
        logic [XLEN-1:0] offset;
        logic addr_valid;
        logic [XLEN-1:0] addr;
        logic committed;
        logic executing;
        logic exception;
    } sq_entry_t;

    lq_entry_t [LQ_ENTRIES-1:0] lq;
    sq_entry_t [SQ_ENTRIES-1:0] sq;
    
    logic [2:0] lq_head, lq_tail;
    logic [2:0] sq_head, sq_tail;
    
    // Memory operation tracking
    logic load_in_flight;
    logic [2:0] load_in_flight_idx;
    logic store_in_flight;

    // ============================================================
    // SINGLE UNIFIED ALWAYS_FF BLOCK - NO DRIVER CONFLICTS
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [XLEN-1:0] calc_addr;
        automatic int lq_search_idx;
        automatic int sq_search_idx;
        automatic logic found_load;
        automatic logic found_store;
        
        if (reset) begin
            // Reset all state
            lq <= '{default: '0};
            sq <= '{default: '0};
            lq_head <= '0;
            lq_tail <= '0;
            sq_head <= '0;
            sq_tail <= '0;
            load_in_flight <= 1'b0;
            load_in_flight_idx <= '0;
            store_in_flight <= 1'b0;
            mem_req <= 1'b0;
            mem_we <= 1'b0;
            mem_addr <= '0;
            mem_wdata <= '0;
            cdb_req <= 1'b0;
            cdb_req_tag <= '0;
            cdb_req_value <= '0;
            cdb_req_exception <= 1'b0;
            
        end else if (flush_pipeline) begin
            // Clear speculative entries
            for (int i = 0; i < LQ_ENTRIES; i++) lq[i].valid <= 1'b0;
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (!sq[i].committed) sq[i].valid <= 1'b0;
            end
            lq_head <= '0;
            lq_tail <= '0;
            sq_tail <= sq_head;
            load_in_flight <= 1'b0;
            store_in_flight <= 1'b0;
            mem_req <= 1'b0;
            cdb_req <= 1'b0;
            
        end else begin
            // Default: clear one-cycle signals
            cdb_req <= 1'b0;
            
            // ========================================================
            // STEP 1: Allocation (highest priority - happens first)
            // ========================================================
            if (alloc_en) begin
                if (is_load) begin
                    lq[lq_tail].valid <= 1'b1;
                    lq[lq_tail].dest_tag <= phys_rd;
                    lq[lq_tail].rob_idx <= rob_idx;
                    lq[lq_tail].base_tag <= base_addr_tag;
                    lq[lq_tail].base_ready <= base_addr_ready;
                    lq[lq_tail].base_val <= base_addr_value;
                    lq[lq_tail].offset <= offset;
                    lq[lq_tail].addr_valid <= 1'b0;
                    lq[lq_tail].executing <= 1'b0;
                    lq[lq_tail].exception <= 1'b0;
                    lq_tail <= lq_tail + 1;
                    
                end else begin
                    sq[sq_tail].valid <= 1'b1;
                    sq[sq_tail].rob_idx <= rob_idx;
                    sq[sq_tail].base_tag <= base_addr_tag;
                    sq[sq_tail].base_ready <= base_addr_ready;
                    sq[sq_tail].base_val <= base_addr_value;
                    sq[sq_tail].data_tag <= store_data_tag;
                    sq[sq_tail].data_ready <= store_data_ready;
                    sq[sq_tail].data_val <= store_data_value;
                    sq[sq_tail].offset <= offset;
                    sq[sq_tail].addr_valid <= 1'b0;
                    sq[sq_tail].committed <= 1'b0;
                    sq[sq_tail].executing <= 1'b0;
                    sq[sq_tail].exception <= 1'b0;
                    sq_tail <= sq_tail + 1;
                end
            end
            
            // ========================================================
            // STEP 2: CDB Wakeup - Update operands
            // ========================================================
            for (int i = 0; i < LQ_ENTRIES; i++) begin
                if (lq[i].valid && !lq[i].base_ready) begin
                    for (int j = 0; j < 2; j++) begin
                        if (cdb_valid[j] && lq[i].base_tag == cdb_tag[j]) begin
                            lq[i].base_val <= cdb_value[j];
                            lq[i].base_ready <= 1'b1;
                        end
                    end
                end
            end
            
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (sq[i].valid) begin
                    if (!sq[i].base_ready) begin
                        for (int j = 0; j < 2; j++) begin
                            if (cdb_valid[j] && sq[i].base_tag == cdb_tag[j]) begin
                                sq[i].base_val <= cdb_value[j];
                                sq[i].base_ready <= 1'b1;
                            end
                        end
                    end
                    
                    if (!sq[i].data_ready) begin
                        for (int j = 0; j < 2; j++) begin
                            if (cdb_valid[j] && sq[i].data_tag == cdb_tag[j]) begin
                                sq[i].data_val <= cdb_value[j];
                                sq[i].data_ready <= 1'b1;
                            end
                        end
                    end
                end
            end
            
            // ========================================================
            // STEP 3: Address Computation
            // ========================================================
            for (int i = 0; i < LQ_ENTRIES; i++) begin
                if (lq[i].valid && !lq[i].addr_valid && lq[i].base_ready) begin
                    calc_addr = lq[i].base_val + lq[i].offset;
                    lq[i].addr <= calc_addr;
                    lq[i].addr_valid <= 1'b1;
                    lq[i].exception <= (calc_addr[1:0] != 2'b00);
                end
            end
            
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (sq[i].valid && !sq[i].addr_valid && sq[i].base_ready) begin
                    calc_addr = sq[i].base_val + sq[i].offset;
                    sq[i].addr <= calc_addr;
                    sq[i].addr_valid <= 1'b1;
                    sq[i].exception <= (calc_addr[1:0] != 2'b00);
                end
            end
            
            // ========================================================
            // STEP 4: Mark Stores as Committed
            // ========================================================
            for (int c = 0; c < COMMIT_W; c++) begin
                if (commit_en[c] && commit_is_store[c]) begin
                    for (int i = 0; i < SQ_ENTRIES; i++) begin
                        if (sq[i].valid && sq[i].rob_idx == commit_rob_idx[c]) begin
                            sq[i].committed <= 1'b1;
                        end
                    end
                end
            end
            
            // ========================================================
            // STEP 5: Memory Operations
            // ========================================================
            
            // Check if load completed
            if (load_in_flight && mem_ready && !mem_we) begin
                lq[load_in_flight_idx].valid <= 1'b0;
                lq_head <= lq_head + 1;
                load_in_flight <= 1'b0;
                mem_req <= 1'b0;
                
                // Broadcast result on CDB
                cdb_req <= 1'b1;
                cdb_req_tag <= lq[load_in_flight_idx].dest_tag;
                cdb_req_value <= mem_rdata;
                cdb_req_exception <= mem_error || lq[load_in_flight_idx].exception;
            end
            
            // Check if store completed
            if (store_in_flight && mem_ready && mem_we) begin
                for (int i = 0; i < SQ_ENTRIES; i++) begin
                    if (sq[i].valid && sq[i].executing && sq[i].addr == mem_addr) begin
                        sq[i].valid <= 1'b0;
                        sq_head <= sq_head + 1;
                        break;
                    end
                end
                store_in_flight <= 1'b0;
                mem_req <= 1'b0;
            end
            
            // Issue new load (priority 1)
            found_load = 1'b0;
            if (!load_in_flight && !store_in_flight) begin
                for (int i = 0; i < LQ_ENTRIES; i++) begin
                    lq_search_idx = (lq_head + i) % LQ_ENTRIES;
                    if (lq[lq_search_idx].valid && lq[lq_search_idx].addr_valid && 
                        !lq[lq_search_idx].executing && !lq[lq_search_idx].exception) begin
                        
                        mem_req <= 1'b1;
                        mem_we <= 1'b0;
                        mem_addr <= lq[lq_search_idx].addr;
                        load_in_flight <= 1'b1;
                        load_in_flight_idx <= lq_search_idx[2:0];
                        lq[lq_search_idx].executing <= 1'b1;
                        found_load = 1'b1;
                        break;
                    end
                end
            end
            
            // Issue new store (priority 2 - only if no load found)
            if (!found_load && !load_in_flight && !store_in_flight) begin
                for (int i = 0; i < SQ_ENTRIES; i++) begin
                    sq_search_idx = (sq_head + i) % SQ_ENTRIES;
                    if (sq[sq_search_idx].valid && sq[sq_search_idx].committed &&
                        sq[sq_search_idx].addr_valid && sq[sq_search_idx].data_ready &&
                        !sq[sq_search_idx].executing && !sq[sq_search_idx].exception) begin
                        
                        mem_req <= 1'b1;
                        mem_we <= 1'b1;
                        mem_addr <= sq[sq_search_idx].addr;
                        mem_wdata <= sq[sq_search_idx].data_val;
                        store_in_flight <= 1'b1;
                        sq[sq_search_idx].executing <= 1'b1;
                        break;
                    end
                end
            end
        end
    end
    
    // ============================================================
    // Exception Handling (Combinational - separate from state)
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
