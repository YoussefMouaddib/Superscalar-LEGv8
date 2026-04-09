module lsu #(
    parameter int LQ_ENTRIES = 12,
    parameter int SQ_ENTRIES = 12,
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
    
    logic [$clog2(LQ_ENTRIES)-1:0] lq_head, lq_tail;
    logic [$clog2(SQ_ENTRIES)-1:0] sq_head, sq_tail;
    
    // Memory operation tracking
    logic load_in_flight;
    logic [$clog2(LQ_ENTRIES)-1:0] load_in_flight_idx;
    logic store_in_flight;
    
    // ============================================================
    // PIPELINE REGISTERS
    // ============================================================
    // Stage 1 results (from priority encoders)
    logic        winner_low_valid, winner_high_valid;
    logic [$clog2(LQ_ENTRIES)-1:0] winner_low_idx, winner_high_idx;
    logic [XLEN-1:0] winner_low_base, winner_high_base;
    logic [XLEN-1:0] winner_low_offset, winner_high_offset;
    logic [5:0] winner_low_dest, winner_high_dest;
    
    // Stage 1 registered
    logic        winner_low_valid_r, winner_high_valid_r;
    logic [$clog2(LQ_ENTRIES)-1:0] winner_low_idx_r, winner_high_idx_r;
    logic [XLEN-1:0] winner_low_base_r, winner_high_base_r;
    logic [XLEN-1:0] winner_low_offset_r, winner_high_offset_r;
    logic [5:0] winner_low_dest_r, winner_high_dest_r;
    
    // Stage 2 selection
    logic        issue_load_comb;
    logic [$clog2(LQ_ENTRIES)-1:0] issue_load_idx_comb;
    logic [XLEN-1:0] issue_base_comb;
    logic [XLEN-1:0] issue_offset_comb;
    logic [5:0] issue_dest_comb;
    
    // Stage 2 registered (to memory)
    logic        issue_load_reg;
    logic [$clog2(LQ_ENTRIES)-1:0] issue_load_idx_reg;
    logic [XLEN-1:0] issue_base_reg;
    logic [XLEN-1:0] issue_offset_reg;
    logic [5:0] issue_dest_reg;
    logic        issue_exception_reg;
    
    // Memory request pipeline
    logic        mem_req_reg;
    logic        mem_we_reg;
    logic [XLEN-1:0] mem_addr_reg;
    logic [XLEN-1:0] mem_wdata_reg;
    logic [5:0] cdb_tag_reg;
    logic        cdb_exception_reg;
    logic [$clog2(LQ_ENTRIES)-1:0] load_idx_reg;

    // ============================================================
    // Helper function for older stores check
    // ============================================================
    function automatic logic all_older_stores_committed(int lq_idx);
        all_older_stores_committed = 1'b1;
        for (int s = 0; s < SQ_ENTRIES; s++) begin
            if (sq[s].valid && sq[s].seq < lq[lq_idx].seq && !sq[s].committed) begin
                all_older_stores_committed = 1'b0;
            end
        end
    endfunction

    // ============================================================
    // STAGE 1a: Lower half priority encoder (entries 0-5)
    // ============================================================
    always_comb begin
        winner_low_valid = 1'b0;
        winner_low_idx = '0;
        winner_low_base = '0;
        winner_low_offset = '0;
        winner_low_dest = '0;
        
        for (int i = 0; i < 6; i++) begin
            int idx = (lq_head + i) % LQ_ENTRIES;
            
            if (lq[idx].valid && lq[idx].addr_valid && 
                !lq[idx].executing && !lq[idx].exception &&
                all_older_stores_committed(idx) && !winner_low_valid) begin
                winner_low_valid = 1'b1;
                winner_low_idx = idx;
                winner_low_base = lq[idx].base_val;
                winner_low_offset = lq[idx].offset;
                winner_low_dest = lq[idx].dest_tag;
            end
        end
    end
    
    // ============================================================
    // STAGE 1b: Upper half priority encoder (entries 6-11)
    // ============================================================
    always_comb begin
        winner_high_valid = 1'b0;
        winner_high_idx = '0;
        winner_high_base = '0;
        winner_high_offset = '0;
        winner_high_dest = '0;
        
        for (int i = 6; i < LQ_ENTRIES; i++) begin
            int idx = (lq_head + i) % LQ_ENTRIES;
            
            if (lq[idx].valid && lq[idx].addr_valid && 
                !lq[idx].executing && !lq[idx].exception &&
                all_older_stores_committed(idx) && !winner_high_valid) begin
                winner_high_valid = 1'b1;
                winner_high_idx = idx;
                winner_high_base = lq[idx].base_val;
                winner_high_offset = lq[idx].offset;
                winner_high_dest = lq[idx].dest_tag;
            end
        end
    end
    
    // ============================================================
    // STAGE 1 PIPELINE REGISTERS
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            winner_low_valid_r <= 1'b0;
            winner_low_idx_r <= '0;
            winner_low_base_r <= '0;
            winner_low_offset_r <= '0;
            winner_low_dest_r <= '0;
            
            winner_high_valid_r <= 1'b0;
            winner_high_idx_r <= '0;
            winner_high_base_r <= '0;
            winner_high_offset_r <= '0;
            winner_high_dest_r <= '0;
        end else if (!flush_pipeline) begin
            winner_low_valid_r <= winner_low_valid;
            winner_low_idx_r <= winner_low_idx;
            winner_low_base_r <= winner_low_base;
            winner_low_offset_r <= winner_low_offset;
            winner_low_dest_r <= winner_low_dest;
            
            winner_high_valid_r <= winner_high_valid;
            winner_high_idx_r <= winner_high_idx;
            winner_high_base_r <= winner_high_base;
            winner_high_offset_r <= winner_high_offset;
            winner_high_dest_r <= winner_high_dest;
        end
    end
    
    // ============================================================
    // STAGE 2: Select between low and high winner
    // ============================================================
    always_comb begin
        issue_load_comb = 1'b0;
        issue_load_idx_comb = '0;
        issue_base_comb = '0;
        issue_offset_comb = '0;
        issue_dest_comb = '0;
        
        if (winner_low_valid_r) begin
            issue_load_comb = 1'b1;
            issue_load_idx_comb = winner_low_idx_r;
            issue_base_comb = winner_low_base_r;
            issue_offset_comb = winner_low_offset_r;
            issue_dest_comb = winner_low_dest_r;
        end else if (winner_high_valid_r) begin
            issue_load_comb = 1'b1;
            issue_load_idx_comb = winner_high_idx_r;
            issue_base_comb = winner_high_base_r;
            issue_offset_comb = winner_high_offset_r;
            issue_dest_comb = winner_high_dest_r;
        end
    end
    
    // ============================================================
    // MAIN SEQUENTIAL BLOCK
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [XLEN-1:0] calc_addr;
        
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
            
            issue_load_reg <= 1'b0;
            issue_load_idx_reg <= '0;
            issue_base_reg <= '0;
            issue_offset_reg <= '0;
            issue_dest_reg <= '0;
            issue_exception_reg <= 1'b0;
            
            mem_req_reg <= 1'b0;
            mem_we_reg <= 1'b0;
            mem_addr_reg <= '0;
            mem_wdata_reg <= '0;
            cdb_tag_reg <= '0;
            cdb_exception_reg <= 1'b0;
            load_idx_reg <= '0;
            
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
        
            // Find new sq_head
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
                sq_head <= found ? new_head[$clog2(SQ_ENTRIES)-1:0] : sq_head;
            end
        
            if (load_in_flight) load_in_flight <= 1'b0;
            if (store_in_flight) store_in_flight <= 1'b0;
            
            issue_load_reg <= 1'b0;
            mem_req_reg <= 1'b0;
            cdb_req <= 1'b0;
            
        end else begin
            // Defaults
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
            // STEP 5: Memory Response
            // ========================================================
            if (load_in_flight && mem_ready && !mem_we) begin
                lq[load_in_flight_idx].valid <= 1'b0;
                lq_head <= lq_head + 1;
                load_in_flight <= 1'b0;
                
                cdb_req <= 1'b1;
                cdb_req_tag <= lq[load_in_flight_idx].dest_tag;
                cdb_req_value <= mem_rdata;
                cdb_req_exception <= mem_error || lq[load_in_flight_idx].exception;
            end
            
            if (store_in_flight && mem_ready && mem_we) begin
                for (int i = 0; i < SQ_ENTRIES; i++) begin
                    if (sq[i].valid && sq[i].executing && sq[i].addr == mem_addr) begin
                        sq[i].valid <= 1'b0;
                        sq_head <= sq_head + 1;
                        break;
                    end
                end
                store_in_flight <= 1'b0;
                mem_req_reg <= 1'b0;
            end
            
            // ========================================================
            // STEP 6: Issue New Load (using pipelined winner selection)
            // ========================================================
            issue_load_reg <= 1'b0;
            
            if (!load_in_flight && !store_in_flight && !mem_req_reg && issue_load_comb) begin
                issue_load_reg <= 1'b1;
                issue_load_idx_reg <= issue_load_idx_comb;
                issue_base_reg <= issue_base_comb;
                issue_offset_reg <= issue_offset_comb;
                issue_dest_reg <= issue_dest_comb;
                issue_exception_reg <= 1'b0;  // Will get from lq later
                lq[issue_load_idx_comb].executing <= 1'b1;
            end
            
            // ========================================================
            // STEP 7: Memory Request (address calculation)
            // ========================================================
            mem_req_reg <= 1'b0;
            
            if (issue_load_reg) begin
                calc_addr = issue_base_reg + issue_offset_reg;
                mem_req_reg <= 1'b1;
                mem_we_reg <= 1'b0;
                mem_addr_reg <= calc_addr;
                mem_wdata_reg <= '0;
                cdb_tag_reg <= issue_dest_reg;
                cdb_exception_reg <= issue_exception_reg;
                load_idx_reg <= issue_load_idx_reg;
                load_in_flight <= 1'b1;
                load_in_flight_idx <= issue_load_idx_reg;
            end
            
            // ========================================================
            // STEP 8: Drive Outputs
            // ========================================================
            mem_req <= mem_req_reg;
            mem_we <= mem_we_reg;
            mem_addr <= mem_addr_reg;
            mem_wdata <= mem_wdata_reg;
            
            // Clean up zombie stores
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (!sq[i].valid && sq[i].committed && sq[i].executing) begin
                    sq[i] <= '{default: '0};
                    if (i == sq_head) sq_head <= sq_head + 1;
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
