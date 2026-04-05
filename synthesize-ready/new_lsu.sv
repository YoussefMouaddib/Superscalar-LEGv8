module lsu #(
    parameter int LQ_ENTRIES = 16,
    parameter int SQ_ENTRIES = 16,
    parameter int XLEN = 32,
    parameter int COMMIT_W = 2,
    parameter int ROB_ENTRIES = 32
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        flush_pipeline,
    
    // Allocation interface
    input  logic        alloc_en,
    input  logic        is_load,
    input  logic [7:0]  opcode,
    input logic [31:0] alloc_seq,
    
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
        logic [31:0] seq;
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
        logic [31:0] seq;
    } sq_entry_t;

    lq_entry_t [LQ_ENTRIES-1:0] lq;
    sq_entry_t [SQ_ENTRIES-1:0] sq;
    
    logic [3:0] lq_head, lq_tail;
    logic [3:0] sq_head, sq_tail;
    
    // Memory operation tracking
    logic load_in_flight;
    logic [3:0] load_in_flight_idx;
    logic store_in_flight;
    
    // ============================================================
    // PIPELINE REGISTERS FOR MEMORY OPERATIONS
    // ============================================================
    logic        mem_req_pipe;
    logic        mem_we_pipe;
    logic [XLEN-1:0] mem_addr_pipe;
    logic [XLEN-1:0] mem_wdata_pipe;
    logic        load_in_flight_pipe;
    logic [3:0]  load_in_flight_idx_pipe;
    logic        store_in_flight_pipe;
    logic [5:0]  cdb_tag_pipe;
    logic        cdb_exception_pipe;
    
    // Issue request signals (combinational)
    logic        issue_load_comb;
    logic        issue_store_comb;
    logic [XLEN-1:0] issue_addr_comb;
    logic [XLEN-1:0] issue_wdata_comb;
    logic [3:0]  issue_load_idx_comb;
    logic [5:0]  issue_cdb_tag_comb;
    logic        issue_exception_comb;

    // ============================================================
    // SINGLE UNIFIED ALWAYS_FF BLOCK
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
            
            // Pipeline registers
            mem_req_pipe <= 1'b0;
            mem_we_pipe <= 1'b0;
            mem_addr_pipe <= '0;
            mem_wdata_pipe <= '0;
            load_in_flight_pipe <= 1'b0;
            load_in_flight_idx_pipe <= '0;
            store_in_flight_pipe <= 1'b0;
            cdb_tag_pipe <= '0;
            cdb_exception_pipe <= 1'b0;
            
            // Outputs
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
                if (!sq[i].committed) begin
                    sq[i].valid <= 1'b0;
                end else begin
                    if (!sq[i].executing) begin
                        sq[i].base_ready <= 1'b0;
                        sq[i].data_ready <= 1'b0;
                        sq[i].addr_valid <= 1'b0;
                    end
                end
            end
        
            lq_head <= '0;
            lq_tail <= '0;
        
            // Keep sq_tail, but ensure sq_head points to first valid committed entry
            begin
                automatic int new_head = sq_head;
                automatic logic found = 1'b0;
                
                for (int i = 0; i < SQ_ENTRIES; i++) begin
                    automatic int idx = (sq_head + i) % SQ_ENTRIES;
                    if (!found && sq[idx].valid && sq[idx].committed) begin
                        new_head = idx;
                        found = 1'b1;
                    end
                end
                
                sq_head <= found ? new_head[3:0] : sq_head;
            end
        
            if (load_in_flight) begin
                load_in_flight <= 1'b0;
            end
        
            if (store_in_flight) begin
                store_in_flight <= 1'b0;
            end
            
            // Clear pipeline
            mem_req_pipe <= 1'b0;
            load_in_flight_pipe <= 1'b0;
            store_in_flight_pipe <= 1'b0;
            cdb_req <= 1'b0;
            
        end else begin
            // Default: clear one-cycle signals
            cdb_req <= 1'b0;
            
            // ========================================================
            // STEP 1: Allocation
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
                    lq[lq_tail].seq <= alloc_seq; 
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
                    sq[sq_tail].seq <= alloc_seq;
                    sq_tail <= sq_tail + 1;
                end
            end
            
            // ========================================================
            // STEP 2: CDB Wakeup
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
            // STEP 5: Handle Memory Response (from previous cycle)
            // ========================================================
            
            // Load completed
            if (load_in_flight_pipe && mem_ready && !mem_we_pipe) begin
                lq[load_in_flight_idx_pipe].valid <= 1'b0;
                lq_head <= lq_head + 1;
                load_in_flight <= 1'b0;
                
                // Broadcast result on CDB
                cdb_req <= 1'b1;
                cdb_req_tag <= cdb_tag_pipe;
                cdb_req_value <= mem_rdata;
                cdb_req_exception <= mem_error || cdb_exception_pipe;
            end
            
            // Store completed
            if (store_in_flight_pipe && mem_ready && mem_we_pipe) begin
                for (int i = 0; i < SQ_ENTRIES; i++) begin
                    if (sq[i].valid && sq[i].executing && sq[i].addr == mem_addr_pipe) begin
                        sq[i].valid <= 1'b0;
                        sq_head <= sq_head + 1;
                        break;
                    end
                end
                store_in_flight <= 1'b0;
            end
            
            // Clear pipeline memory request after response
            if (mem_ready && (load_in_flight_pipe || store_in_flight_pipe)) begin
                mem_req_pipe <= 1'b0;
                load_in_flight_pipe <= 1'b0;
                store_in_flight_pipe <= 1'b0;
            end
            
            // ========================================================
            // STEP 6: Issue New Memory Operation (Combinational logic, results piped)
            // ========================================================
            
            // Default: no issue
            issue_load_comb = 1'b0;
            issue_store_comb = 1'b0;
            issue_addr_comb = '0;
            issue_wdata_comb = '0;
            issue_load_idx_comb = '0;
            issue_cdb_tag_comb = '0;
            issue_exception_comb = 1'b0;
            
            // Issue new load (priority 1)
            found_load = 1'b0;
            if (!load_in_flight && !store_in_flight && !load_in_flight_pipe && !store_in_flight_pipe) begin
                for (int i = 0; i < LQ_ENTRIES; i++) begin
                    lq_search_idx = (lq_head + i) % LQ_ENTRIES;
                    if (lq[lq_search_idx].valid && lq[lq_search_idx].addr_valid && 
                        !lq[lq_search_idx].executing && !lq[lq_search_idx].exception) begin

                        automatic logic all_older_stores_committed = 1'b1;
                        for (int s = 0; s < SQ_ENTRIES; s++) begin
                            if (sq[s].valid && sq[s].seq < lq[lq_search_idx].seq) begin
                                if (!sq[s].committed) begin
                                    all_older_stores_committed = 1'b0;
                                    break;
                                end
                            end
                        end

                        if (all_older_stores_committed) begin
                            issue_load_comb = 1'b1;
                            issue_addr_comb = lq[lq_search_idx].addr;
                            issue_load_idx_comb = lq_search_idx;
                            issue_cdb_tag_comb = lq[lq_search_idx].dest_tag;
                            issue_exception_comb = lq[lq_search_idx].exception;
                            lq[lq_search_idx].executing <= 1'b1;
                            found_load = 1'b1;
                            break;
                        end
                    end
                end
            end
            
            // Issue new store (priority 2)
            if (!found_load && !load_in_flight && !store_in_flight && !load_in_flight_pipe && !store_in_flight_pipe) begin
                for (int i = 0; i < SQ_ENTRIES; i++) begin
                    sq_search_idx = (sq_head + i) % SQ_ENTRIES;
                    if (sq[sq_search_idx].valid && sq[sq_search_idx].committed &&
                        sq[sq_search_idx].addr_valid && sq[sq_search_idx].data_ready &&
                        !sq[sq_search_idx].executing && !sq[sq_search_idx].exception) begin

                        automatic logic all_older_stores_executed = 1'b1;
                        for (int s = 0; s < SQ_ENTRIES; s++) begin
                            if (sq[s].valid && sq[s].seq < sq[sq_search_idx].seq) begin
                                if (sq[s].executing || !sq[s].committed) begin
                                    all_older_stores_executed = 1'b0;
                                    break;
                                end
                            end
                        end
                        
                        if (all_older_stores_executed) begin
                            issue_store_comb = 1'b1;
                            issue_addr_comb = sq[sq_search_idx].addr;
                            issue_wdata_comb = sq[sq_search_idx].data_val;
                            issue_cdb_tag_comb = sq[sq_search_idx].rob_idx;  // Stores don't broadcast
                            issue_exception_comb = sq[sq_search_idx].exception;
                            sq[sq_search_idx].executing <= 1'b1;
                            break;
                        end
                    end
                end
            end
            
            // ========================================================
            // STEP 7: Pipeline the Memory Request
            // ========================================================
            if (issue_load_comb) begin
                mem_req_pipe <= 1'b1;
                mem_we_pipe <= 1'b0;
                mem_addr_pipe <= issue_addr_comb;
                mem_wdata_pipe <= '0;
                load_in_flight_pipe <= 1'b1;
                load_in_flight_idx_pipe <= issue_load_idx_comb;
                store_in_flight_pipe <= 1'b0;
                cdb_tag_pipe <= issue_cdb_tag_comb;
                cdb_exception_pipe <= issue_exception_comb;
                load_in_flight <= 1'b1;
            end else if (issue_store_comb) begin
                mem_req_pipe <= 1'b1;
                mem_we_pipe <= 1'b1;
                mem_addr_pipe <= issue_addr_comb;
                mem_wdata_pipe <= issue_wdata_comb;
                load_in_flight_pipe <= 1'b0;
                store_in_flight_pipe <= 1'b1;
                cdb_tag_pipe <= issue_cdb_tag_comb;
                cdb_exception_pipe <= issue_exception_comb;
                store_in_flight <= 1'b1;
            end
            
            // ========================================================
            // STEP 8: Drive Outputs from Pipeline Registers
            // ========================================================
            mem_req <= mem_req_pipe;
            mem_we <= mem_we_pipe;
            mem_addr <= mem_addr_pipe;
            mem_wdata <= mem_wdata_pipe;
            
            // Clean up zombie store entries
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (!sq[i].valid && sq[i].committed && sq[i].executing) begin
                    sq[i] <= '{default: '0};
                    if (i == sq_head) begin
                        sq_head <= sq_head + 1;
                    end
                end
            end
        end
    end
    
    // ============================================================
    // Exception Handling
    // ============================================================
    always_comb begin
        lsu_exception = 1'b0;
        lsu_exception_cause = '0;
    end

endmodule
