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
    
    input  logic        alloc_en,
    input  logic        is_load,
    input  logic [7:0]  opcode,
    input  logic [31:0] alloc_seq,
    
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
    
    input  logic [1:0]       cdb_valid,
    input  logic [1:0][5:0]  cdb_tag,
    input  logic [1:0][31:0] cdb_value,
    
    output logic        cdb_req,
    output logic [5:0]  cdb_req_tag,
    output logic [XLEN-1:0] cdb_req_value,
    output logic        cdb_req_exception,
    
    input  logic [COMMIT_W-1:0]  commit_en,
    input  logic [COMMIT_W-1:0]  commit_is_store,
    input  logic [COMMIT_W-1:0][$clog2(ROB_ENTRIES)-1:0] commit_rob_idx,
    
    output logic        lsu_exception,
    output logic [4:0]  lsu_exception_cause,
    
    output logic        mem_req,
    output logic        mem_we,
    output logic [XLEN-1:0] mem_addr,
    output logic [XLEN-1:0] mem_wdata,
    input  logic        mem_ready,
    input  logic [XLEN-1:0] mem_rdata,
    input  logic        mem_error
);

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
    
    logic load_in_flight;
    logic [$clog2(LQ_ENTRIES)-1:0] load_in_flight_idx;
    logic store_in_flight;
    logic [$clog2(SQ_ENTRIES)-1:0] store_in_flight_idx;

    // ============================================================
    // Helper: are all older stores committed (needed before a load can issue)
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
    // SIMPLE COMBINATIONAL WINNER SELECT — one load, one store, per cycle
    // Straightforward priority encoder, oldest-first (head-relative scan)
    // ============================================================
    logic        winner_load_valid;
    logic [$clog2(LQ_ENTRIES)-1:0] winner_load_idx;
    logic [XLEN-1:0] winner_load_addr;
    logic [5:0]  winner_load_dest;

    always_comb begin
        integer idx;   // declare once, outside/before the loop
        winner_load_valid = 1'b0;
        winner_load_idx = '0;
        winner_load_addr = '0;
        winner_load_dest = '0;
    
        for (int i = 0; i < LQ_ENTRIES; i++) begin
            idx = (lq_head + i) % LQ_ENTRIES;
            if (!winner_load_valid && lq[idx].valid && lq[idx].addr_valid &&
                !lq[idx].executing && !lq[idx].exception &&
                all_older_stores_committed(idx)) begin
                winner_load_valid = 1'b1;
                winner_load_idx = idx[$clog2(LQ_ENTRIES)-1:0];
                winner_load_addr = lq[idx].addr;
                winner_load_dest = lq[idx].dest_tag;
            end
        end
    end

    logic        winner_store_valid;
    logic [$clog2(SQ_ENTRIES)-1:0] winner_store_idx;
    logic [XLEN-1:0] winner_store_addr;
    logic [XLEN-1:0] winner_store_data;

    always_comb begin
        integer idx;
        winner_store_valid = 1'b0;
        winner_store_idx = '0;
        winner_store_addr = '0;
        winner_store_data = '0;
    
        for (int i = 0; i < SQ_ENTRIES; i++) begin
            idx = (sq_head + i) % SQ_ENTRIES;
            if ( sq[idx].valid && sq[idx].committed &&
                sq[idx].addr_valid && sq[idx].data_ready &&
                !sq[idx].executing && !sq[idx].exception) begin
                winner_store_valid = 1'b1;
                winner_store_idx = idx[$clog2(SQ_ENTRIES)-1:0];
                winner_store_addr = sq[idx].addr;
                winner_store_data = sq[idx].data_val;
            end
        end
    end

    // ============================================================
    // MAIN SEQUENTIAL BLOCK
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [XLEN-1:0] calc_addr;

        if (reset) begin
            lq <= '{default: '0};
            sq <= '{default: '0};
            lq_head <= '0;
            lq_tail <= '0;
            sq_head <= '0;
            sq_tail <= '0;
            load_in_flight <= 1'b0;
            load_in_flight_idx <= '0;
            store_in_flight <= 1'b0;
            store_in_flight_idx <= '0;

            mem_req <= 1'b0;
            mem_we <= 1'b0;
            mem_addr <= '0;
            mem_wdata <= '0;
            cdb_req <= 1'b0;
            cdb_req_tag <= '0;
            cdb_req_value <= '0;
            cdb_req_exception <= 1'b0;

        end else if (flush_pipeline) begin
            for (int i = 0; i < LQ_ENTRIES; i++) lq[i].valid <= 1'b0;
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                if (!sq[i].committed) sq[i].valid <= 1'b0;
            end
            lq_head <= '0;
            lq_tail <= '0;
            load_in_flight <= 1'b0;
            store_in_flight <= 1'b0;
            mem_req <= 1'b0;
            cdb_req <= 1'b0;

        end else begin
            cdb_req <= 1'b0;

            // ----------------------------------------------------
            // STEP 1: Allocation
            // ----------------------------------------------------
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

            // ----------------------------------------------------
            // STEP 2: CDB Wakeup
            // ----------------------------------------------------
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

            // ----------------------------------------------------
            // STEP 3: Address Computation
            // ----------------------------------------------------
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

            // ----------------------------------------------------
            // STEP 4: Mark Stores as Committed
            // ----------------------------------------------------
            for (int c = 0; c < COMMIT_W; c++) begin
                if (commit_en[c] && commit_is_store[c]) begin
                    for (int i = 0; i < SQ_ENTRIES; i++) begin
                        if (sq[i].valid && sq[i].rob_idx == commit_rob_idx[c]) begin
                            sq[i].committed <= 1'b1;
                        end
                    end
                end
            end

            // ----------------------------------------------------
            // STEP 5: Memory Response (completes whatever was issued last cycle)
            // ----------------------------------------------------
            if (load_in_flight && mem_ready && !mem_we) begin
                lq[load_in_flight_idx].valid <= 1'b0;
                lq_head <= lq_head + 1;
                load_in_flight <= 1'b0;

                cdb_req <= 1'b1;
                cdb_req_tag <= lq[load_in_flight_idx].dest_tag;
                cdb_req_value <= mem_rdata;
                cdb_req_exception <= mem_error || lq[load_in_flight_idx].exception;

                mem_req <= 1'b0;
            end

            if (store_in_flight && mem_ready && mem_we) begin
                sq[store_in_flight_idx].valid <= 1'b0;
                sq_head <= sq_head + 1;
                store_in_flight <= 1'b0;

                mem_req <= 1'b0;
            end

            // ----------------------------------------------------
            // STEP 6: Issue New Load OR Store — straightforward, single cycle
            // Only fires when nothing is currently in flight.
            // ----------------------------------------------------
            if (!load_in_flight && !store_in_flight) begin
                if (winner_load_valid) begin
                    mem_req <= 1'b1;
                    mem_we <= 1'b0;
                    mem_addr <= winner_load_addr;
                    mem_wdata <= '0;
                    lq[winner_load_idx].executing <= 1'b1;
                    load_in_flight <= 1'b1;
                    load_in_flight_idx <= winner_load_idx;
                end else if (winner_store_valid) begin
                    mem_req <= 1'b1;
                    mem_we <= 1'b1;
                    mem_addr <= winner_store_addr;
                    mem_wdata <= winner_store_data;
                    sq[winner_store_idx].executing <= 1'b1;
                    store_in_flight <= 1'b1;
                    store_in_flight_idx <= winner_store_idx;
                end
            end
        end
    end

    always_comb begin
        lsu_exception = 1'b0;
        lsu_exception_cause = '0;
    end

endmodule
