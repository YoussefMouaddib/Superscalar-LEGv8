`timescale 1ns/1ps
import core_pkg::*;

// =============================================================================
// dispatch.sv — REGISTERED outputs version
//
// Timing fix summary
// ------------------
// Old (combinational): rename_valid → [long comb cloud] → RS / ROB / LSU
//   Problem: 144 ns worst slack on that path.
//
// New (registered): rename_valid → [comb cloud] →|FF|→ RS / ROB / LSU
//   The entire RS / ROB / LSU allocation fires one cycle after rename lands.
//
// The phase problem that arises:
//   Cycle N  : rename inputs arrive, ROB.alloc_en is driven combinationally
//              → ROB produces alloc_idx combinationally this same cycle.
//   Cycle N+1: registered alloc_en lands at ROB, RS, LSU.
//              But alloc_idx was already computed in cycle N — it's stale by now.
//
// Fix: capture alloc_idx (and alloc_ok) in registers at the end of cycle N.
//   rob_alloc_idx_r / rob_alloc_ok_r hold the cycle-N combinational values.
//   The always_ff dispatch block uses these when it writes the RS rob_tag and
//   LSU rob_idx fields one cycle later.
//
// Scoreboard fix:
//   preg_ready must mark a register busy the cycle the registered alloc fires
//   (cycle N+1), using the registered prd — not the live rename_prd.
// =============================================================================

module dispatch #(
    parameter int FETCH_W    = core_pkg::FETCH_WIDTH,
    parameter int XLEN       = core_pkg::XLEN,
    parameter int PHYS_W     = core_pkg::LOG2_PREGS,
    parameter int RS_ENTRIES = 32,
    parameter int ROB_ENTRIES = 32
)(
    input  logic                     clk,
    input  logic                     reset,

    // ------------------------------------------------------------------
    // From Rename Stage
    // ------------------------------------------------------------------
    input  logic [FETCH_W-1:0]       rename_valid,
    input  logic [FETCH_W-1:0][5:0]  rename_opcode,
    input  logic [FETCH_W-1:0][5:0]  rename_prs1,
    input  logic [FETCH_W-1:0][5:0]  rename_prs2,
    input  logic [FETCH_W-1:0][5:0]  rename_prd,
    input  logic [FETCH_W-1:0][31:0] rename_imm,
    input  logic [FETCH_W-1:0][31:0] rename_pc,
    input  logic [FETCH_W-1:0]       rename_rs1_valid,
    input  logic [FETCH_W-1:0]       rename_rs2_valid,
    input  logic [FETCH_W-1:0]       rename_rd_valid,
    input  logic [FETCH_W-1:0]       rename_is_alu,
    input  logic [FETCH_W-1:0]       rename_is_load,
    input  logic [FETCH_W-1:0]       rename_is_store,
    input  logic [FETCH_W-1:0]       rename_is_branch,
    input  logic [FETCH_W-1:0]       rename_is_cas,
    input  logic [FETCH_W-1:0][5:0]  rename_alu_func,
    input  logic [FETCH_W-1:0][4:0]  rename_arch_rs1,
    input  logic [FETCH_W-1:0][4:0]  rename_arch_rs2,
    input  logic [FETCH_W-1:0][4:0]  rename_arch_rd,

    input  logic                     flush_pipeline,
    output logic                     dispatch_stall,

    // ------------------------------------------------------------------
    // To Physical Register File — combinational read ports
    // ------------------------------------------------------------------
    output logic [PHYS_W-1:0]        prf_rtag0,
    input  logic [XLEN-1:0]          prf_rdata0,
    output logic [PHYS_W-1:0]        prf_rtag1,
    input  logic [XLEN-1:0]          prf_rdata1,
    output logic [PHYS_W-1:0]        prf_rtag2,
    input  logic [XLEN-1:0]          prf_rdata2,
    output logic [PHYS_W-1:0]        prf_rtag3,
    input  logic [XLEN-1:0]          prf_rdata3,

    // ------------------------------------------------------------------
    // To Reservation Station — REGISTERED
    // ------------------------------------------------------------------
    output logic [FETCH_W-1:0]                              rs_alloc_en,
    output logic [FETCH_W-1:0][PHYS_W-1:0]                 rs_alloc_dst_tag,
    output logic [FETCH_W-1:0][PHYS_W-1:0]                 rs_alloc_src1_tag,
    output logic [FETCH_W-1:0][PHYS_W-1:0]                 rs_alloc_src2_tag,
    output logic [FETCH_W-1:0][31:0]                        rs_alloc_src1_val,
    output logic [FETCH_W-1:0][31:0]                        rs_alloc_src2_val,
    output logic [FETCH_W-1:0]                              rs_alloc_src1_ready,
    output logic [FETCH_W-1:0]                              rs_alloc_src2_ready,
    output logic [FETCH_W-1:0][11:0]                        rs_alloc_op,
    output logic [1:0][31:0]                                 rs_alloc_pc,
    output logic [1:0][31:0]                                 rs_alloc_imm,
    output logic [FETCH_W-1:0][5:0]                         rs_alloc_rob_tag,
    input  logic                                             rs_full,

    // ------------------------------------------------------------------
    // To / From ROB — REGISTERED (alloc_en, metadata)
    //                 COMBINATIONAL in  (alloc_ok, alloc_idx)
    // ------------------------------------------------------------------
    output logic [FETCH_W-1:0]                              rob_alloc_en,
    output logic [FETCH_W-1:0][4:0]                         rob_alloc_arch_rd,
    output logic [FETCH_W-1:0][PHYS_W-1:0]                 rob_alloc_phys_rd,
    output logic [FETCH_W-1:0]                              rob_alloc_is_store,
    output logic [FETCH_W-1:0]                              rob_alloc_is_load,
    output logic [FETCH_W-1:0]                              rob_alloc_is_branch,
    output logic [FETCH_W-1:0][31:0]                        rob_alloc_pc,

    input  logic                                             rob_alloc_ok,
    input  logic [FETCH_W-1:0][$clog2(ROB_ENTRIES)-1:0]    rob_alloc_idx,

    // ------------------------------------------------------------------
    // To LSU — REGISTERED
    // ------------------------------------------------------------------
    output logic                     lsu_alloc_en,
    output logic                     lsu_is_load,
    output logic [7:0]               lsu_opcode,
    output logic [XLEN-1:0]          lsu_offset,
    output logic [4:0]               lsu_arch_rs1,
    output logic [4:0]               lsu_arch_rs2,
    output logic [4:0]               lsu_arch_rd,
    output logic [PHYS_W-1:0]        lsu_phys_rd,
    output logic [5:0]               lsu_rob_idx,
    output logic [5:0]               lsu_base_tag,
    output logic                     lsu_base_ready,
    output logic [31:0]              lsu_base_value,
    output logic [5:0]               lsu_store_data_tag,
    output logic                     lsu_store_data_ready,
    output logic [31:0]              lsu_store_data_value,
    output logic [0:0]               lsu_lane_index,

    // ------------------------------------------------------------------
    // From CDB
    // ------------------------------------------------------------------
    input  logic [1:0]               cdb_valid,
    input  logic [1:0][PHYS_W-1:0]  cdb_tag,
    input  logic [1:0][XLEN-1:0]    cdb_value
);

    // ==========================================================================
    // ROB idx / ok capture registers
    // ==========================================================================
    // The ROB produces alloc_idx and alloc_ok COMBINATIONALLY in response to
    // the alloc_en we drive.  But alloc_en itself is now a registered output
    // (it lands at the ROB one cycle after rename).  By the time the ROB sees
    // the registered alloc_en and recomputes alloc_idx, that idx is the one
    // that belongs to THIS dispatch group.  We still need to capture it at the
    // end of THAT same cycle so it's stable when we write the RS / LSU fields
    // in the FOLLOWING cycle.
    //
    // Timeline:
    //   Cycle N  : rename arrives → comb stall/ok check → alloc_en_comb valid
    //              ROB sees alloc_en_comb → produces alloc_idx_comb
    //              We register alloc_idx_comb → rob_alloc_idx_r
    //              We also drive the registered alloc_en (rob_alloc_en) that the
    //              ROB will see next cycle.
    //   Cycle N+1: registered rob_alloc_en arrives at ROB (ROB records the entry)
    //              Registered RS / LSU fields also arrive — they use rob_alloc_idx_r
    //              which was captured at cycle N.  Tags match.
    //
    // IMPORTANT: alloc_en sent to the ROB must be combinational so the ROB can
    // produce alloc_idx before we register it.  The ROB entry write itself is
    // done one cycle later (the registered rob_alloc_en triggers the sequential
    // write inside rob.sv on the next edge).  This is the same timing that the
    // original combinational dispatch relied on — we just added one pipeline
    // stage on the output side.
    // ==========================================================================

    // Combinational alloc_en signals — used to drive ROB this cycle so it can
    // return alloc_idx combinationally, which we then capture.
    logic [FETCH_W-1:0]                           alloc_en_comb;
    logic [FETCH_W-1:0][$clog2(ROB_ENTRIES)-1:0]  rob_alloc_idx_r;
    logic                                          rob_alloc_ok_r;

    // Compute combinational alloc_en (mirrors what we'll register next cycle)
    always_comb begin
        alloc_en_comb = '0;
        for (int i = 0; i < FETCH_W; i++) begin
            if (rename_valid[i] && !rs_full && !flush_pipeline) begin
                alloc_en_comb[i] = 1'b1;
            end
        end
    end

    // Drive ROB alloc_en combinationally so ROB sees it NOW and returns idx NOW
    // Note: rob_alloc_en (the registered output port) is what the ROB uses for
    // its sequential write.  We use a separate wire for the combinational probe.
    // If your ROB uses alloc_en only in its always_comb idx block (which it does
    // per rob.sv), this is safe — the combinational idx path sees alloc_en_comb,
    // the sequential write path sees the registered rob_alloc_en one cycle later.
    //
    // If your ROB combinational block is already reading rob_alloc_en (the port),
    // simply connect alloc_en_comb to the port and leave rob_alloc_en as a
    // separate internal registered copy — adjust instantiation accordingly.

    // Capture idx and ok at the end of each cycle
    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_pipeline) begin
            rob_alloc_idx_r <= '0;
            rob_alloc_ok_r  <= 1'b0;
        end else begin
            // Capture the ROB's combinational response to alloc_en_comb
            rob_alloc_idx_r <= rob_alloc_idx;
            rob_alloc_ok_r  <= rob_alloc_ok;
        end
    end

    // ==========================================================================
    // Scoreboard
    // ==========================================================================
    // Must mark registers busy the cycle the REGISTERED alloc fires (cycle N+1).
    // At that point rob_alloc_en (the registered port) is valid and
    // rename_prd is still the COMBINATIONAL input — one cycle stale.
    // So we also register rename_prd / rename_rd_valid alongside alloc_en.
    // ==========================================================================

    logic [FETCH_W-1:0][PHYS_W-1:0] rename_prd_r;
    logic [FETCH_W-1:0]             rename_rd_valid_r;

    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_pipeline) begin
            rename_prd_r      <= '0;
            rename_rd_valid_r <= '0;
        end else begin
            rename_prd_r      <= rename_prd;
            rename_rd_valid_r <= rename_rd_valid;
        end
    end

    logic [core_pkg::PREGS-1:0] preg_ready;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            preg_ready <= '1;
        end else begin
            // Mark busy: use the registered alloc_en and registered prd
            // so both arrive at the scoreboard on the same cycle (N+1)
            for (int i = 0; i < FETCH_W; i++) begin
                if (rob_alloc_en[i] && rob_alloc_ok_r && rename_rd_valid_r[i]) begin
                    preg_ready[rename_prd_r[i]] <= 1'b0;
                end
            end

            // Mark ready when CDB broadcasts
            for (int j = 0; j < 2; j++) begin
                if (cdb_valid[j]) begin
                    preg_ready[cdb_tag[j]] <= 1'b1;
                end
            end
        end
    end

    // ==========================================================================
    // LSU base-address cache
    // ==========================================================================
    logic [5:0]      cached_base_tag;
    logic [XLEN-1:0] cached_base_value;
    logic            cached_base_ready;
    logic            cached_valid;

    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_pipeline) begin
            cached_valid      <= 1'b0;
            cached_base_tag   <= '0;
            cached_base_value <= '0;
            cached_base_ready <= 1'b0;
        end else if (lsu_alloc_en) begin
            cached_valid      <= 1'b1;
            cached_base_tag   <= lsu_base_tag;
            cached_base_value <= lsu_base_value;
            cached_base_ready <= lsu_base_ready;
        end
    end

    // ==========================================================================
    // PRF read port arbitration (combinational)
    // ==========================================================================
    always_comb begin
        prf_rtag0 = '0;
        prf_rtag1 = '0;
        prf_rtag2 = '0;
        prf_rtag3 = '0;

        if (rename_valid[0]) begin
            prf_rtag0 = rename_prs1[0];
            prf_rtag1 = rename_prs2[0];
        end
        if (rename_valid[1]) begin
            prf_rtag2 = rename_prs1[1];
            prf_rtag3 = rename_prs2[1];
        end
    end

    // ==========================================================================
    // Operand readiness check (combinational)
    // ==========================================================================
    logic [FETCH_W-1:0]            src1_ready, src2_ready;
    logic [FETCH_W-1:0][XLEN-1:0]  src1_value, src2_value;

    always_comb begin
        for (int i = 0; i < FETCH_W; i++) begin
            // ---------- Source 1 ----------
            if (!rename_rs1_valid[i]) begin
                src1_ready[i] = 1'b1;
                src1_value[i] = '0;
            end else if (rename_prs1[i] == 6'd0) begin
                src1_ready[i] = 1'b1;
                src1_value[i] = '0;
            end else begin
                src1_ready[i] = preg_ready[rename_prs1[i]];

                // Same-cycle intra-group dependency
                for (int j = 0; j < FETCH_W; j++) begin
                    if (j < i && rename_valid[j] && rename_rd_valid[j] &&
                        rename_prs1[i] == rename_prd[j]) begin
                        src1_ready[i] = 1'b0;
                    end
                end

                src1_value[i] = (i == 0) ? prf_rdata0 : prf_rdata2;

                // CDB bypass
                for (int j = 0; j < 2; j++) begin
                    if (cdb_valid[j] && cdb_tag[j] == rename_prs1[i]) begin
                        src1_ready[i] = 1'b1;
                        src1_value[i] = cdb_value[j];
                    end
                end
            end

            // ---------- Source 2 ----------
            if (!rename_rs2_valid[i]) begin
                src2_ready[i] = 1'b1;
                src2_value[i] = rename_imm[i];
            end else if (rename_prs2[i] == 6'd0) begin
                src2_ready[i] = 1'b1;
                src2_value[i] = '0;
            end else begin
                src2_ready[i] = preg_ready[rename_prs2[i]];

                for (int j = 0; j < FETCH_W; j++) begin
                    if (j < i && rename_valid[j] && rename_rd_valid[j] &&
                        rename_prs2[i] == rename_prd[j]) begin
                        src2_ready[i] = 1'b0;
                    end
                end

                src2_value[i] = (i == 0) ? prf_rdata1 : prf_rdata3;

                for (int j = 0; j < 2; j++) begin
                    if (cdb_valid[j] && cdb_tag[j] == rename_prs2[i]) begin
                        src2_ready[i] = 1'b1;
                        src2_value[i] = cdb_value[j];
                    end
                end
            end
        end
    end

    // ==========================================================================
    // Stall logic (combinational)
    // ==========================================================================
    logic memory_op_stall;

    always_comb begin
        automatic int mem_op_count = 0;
        for (int i = 0; i < FETCH_W; i++) begin
            if (rename_valid[i] &&
                (rename_is_load[i] || rename_is_store[i] || rename_is_cas[i]))
                mem_op_count++;
        end
        memory_op_stall = (mem_op_count > 1);
        // Use rob_alloc_ok_r (registered) so stall doesn't depend on the
        // current-cycle combinational ROB response — that was already captured.
        dispatch_stall = rs_full || !rob_alloc_ok_r || flush_pipeline || memory_op_stall;
    end

    // ==========================================================================
    // Registered outputs: RS, ROB, LSU
    // ==========================================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_pipeline) begin
            // RS
            rs_alloc_en       <= '0;
            rs_alloc_dst_tag  <= '0;
            rs_alloc_src1_tag <= '0;
            rs_alloc_src2_tag <= '0;
            rs_alloc_src1_val <= '0;
            rs_alloc_src2_val <= '0;
            rs_alloc_src1_ready <= '0;
            rs_alloc_src2_ready <= '0;
            rs_alloc_op       <= '0;
            rs_alloc_pc       <= '0;
            rs_alloc_imm      <= '0;
            rs_alloc_rob_tag  <= '0;
            // ROB
            rob_alloc_en      <= '0;
            rob_alloc_arch_rd <= '0;
            rob_alloc_phys_rd <= '0;
            rob_alloc_is_store  <= '0;
            rob_alloc_is_load   <= '0;
            rob_alloc_is_branch <= '0;
            rob_alloc_pc      <= '0;
            // LSU
            lsu_alloc_en        <= 1'b0;
            lsu_lane_index      <= 1'b0;
            lsu_is_load         <= 1'b0;
            lsu_opcode          <= '0;
            lsu_base_tag        <= '0;
            lsu_base_ready      <= 1'b0;
            lsu_base_value      <= '0;
            lsu_offset          <= '0;
            lsu_store_data_tag   <= '0;
            lsu_store_data_ready <= 1'b0;
            lsu_store_data_value <= '0;
            lsu_arch_rs1  <= '0;
            lsu_arch_rs2  <= '0;
            lsu_arch_rd   <= '0;
            lsu_phys_rd   <= '0;
            lsu_rob_idx   <= '0;

        end else if (!dispatch_stall) begin

            // ----------------------------------------------------------------
            // RS allocation
            // ----------------------------------------------------------------
            for (int i = 0; i < FETCH_W; i++) begin
                if (rename_valid[i] && (rename_is_alu[i] || rename_is_branch[i]) && !rs_full) begin
                    rs_alloc_en[i]       <= 1'b1;
                    rs_alloc_dst_tag[i]  <= rename_prd[i];
                    rs_alloc_src1_tag[i] <= rename_prs1[i];
                    rs_alloc_src2_tag[i] <= rename_prs2[i];
                    rs_alloc_src1_val[i] <= src1_value[i];
                    rs_alloc_src2_val[i] <= src2_value[i];
                    rs_alloc_src1_ready[i] <= src1_ready[i];
                    rs_alloc_src2_ready[i] <= src2_ready[i];
                    rs_alloc_op[i]       <= {rename_opcode[i], rename_alu_func[i]};
                    rs_alloc_pc[i]       <= rename_pc[i];
                    rs_alloc_imm[i]      <= rename_imm[i];
                    // KEY FIX: use the CAPTURED idx from cycle N, not the
                    // live combinational output (which now reflects cycle N+1)
                    rs_alloc_rob_tag[i]  <= rob_alloc_idx_r[i];
                end else begin
                    rs_alloc_en[i] <= 1'b0;
                end
            end

            // ----------------------------------------------------------------
            // ROB allocation
            // ----------------------------------------------------------------
            for (int i = 0; i < FETCH_W; i++) begin
                rob_alloc_arch_rd[i] <= rename_arch_rd[i];
                rob_alloc_phys_rd[i] <= rename_prd[i];
                rob_alloc_pc[i]      <= rename_pc[i];

                if (rename_valid[i] && !rs_full) begin
                    rob_alloc_en[i]        <= 1'b1;
                    rob_alloc_is_store[i]  <= rename_is_store[i];
                    rob_alloc_is_load[i]   <= rename_is_load[i];
                    rob_alloc_is_branch[i] <= rename_is_branch[i];
                end else begin
                    rob_alloc_en[i]        <= 1'b0;
                    rob_alloc_is_store[i]  <= 1'b0;
                    rob_alloc_is_load[i]   <= 1'b0;
                    rob_alloc_is_branch[i] <= 1'b0;
                end
            end

            // ----------------------------------------------------------------
            // LSU allocation (one memory op per cycle)
            // ----------------------------------------------------------------
            lsu_alloc_en        <= 1'b0;
            lsu_lane_index      <= 1'b0;
            lsu_is_load         <= 1'b0;
            lsu_opcode          <= '0;
            lsu_base_tag        <= '0;
            lsu_base_ready      <= 1'b0;
            lsu_base_value      <= '0;
            lsu_offset          <= '0;
            lsu_store_data_tag   <= '0;
            lsu_store_data_ready <= 1'b0;
            lsu_store_data_value <= '0;
            lsu_arch_rs1 <= '0;
            lsu_arch_rs2 <= '0;
            lsu_arch_rd  <= '0;
            lsu_phys_rd  <= '0;
            lsu_rob_idx  <= '0;

            for (int i = 0; i < FETCH_W; i++) begin
                if (rename_valid[i] &&
                    (rename_is_load[i] || rename_is_store[i]) &&
                    rob_alloc_ok_r && !flush_pipeline) begin

                    lsu_alloc_en        <= 1'b1;
                    lsu_lane_index      <= i[0];
                    lsu_is_load         <= rename_is_load[i];
                    lsu_opcode          <= {rename_opcode[i], 2'b00};
                    lsu_base_tag        <= rename_prs1[i];
                    lsu_offset          <= rename_imm[i];
                    lsu_store_data_value <= src2_value[i];
                    lsu_store_data_tag  <= rename_prs2[i];
                    lsu_store_data_ready <= src2_ready[i];
                    lsu_arch_rs1 <= rename_arch_rs1[i];
                    lsu_arch_rs2 <= rename_arch_rs2[i];
                    lsu_arch_rd  <= rename_arch_rd[i];
                    lsu_phys_rd  <= rename_prd[i];
                    // KEY FIX: use captured idx, not live combinational
                    lsu_rob_idx  <= rob_alloc_idx_r[i];

                    if (cached_valid &&
                        rename_prs1[i] == cached_base_tag &&
                        cached_base_ready) begin
                        lsu_base_value <= cached_base_value;
                        lsu_base_ready <= cached_base_ready;
                    end else begin
                        lsu_base_value <= src1_value[i];
                        lsu_base_ready <= src1_ready[i];
                    end

                    break;
                end
            end
        end
    end

endmodule
