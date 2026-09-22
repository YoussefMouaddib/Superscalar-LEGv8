`timescale 1ns/1ps
import core_pkg::*;

module fetch #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int FETCH_WIDTH = core_pkg::FETCH_WIDTH
)(
    input  logic        clk,
    input  logic        reset,

    input  logic        branch_taken,
    input  logic [31:0] branch_target_pc,
    input  logic        flush_pipeline, 
    
    input  logic        fetch_en,
    input  logic        stall,
    input  logic        redirect_en,
    input  logic [XLEN-1:0] redirect_pc,
    
    
    // Branch predictor update from commit
    input  logic        bp_update_en,
    input  logic [31:0] bp_update_pc,
    input  logic        bp_update_taken,
    input  logic [31:0] bp_update_target,
    input  logic        bp_update_is_branch,
    input  logic        bp_update_is_call,
    input  logic        bp_update_is_return,
    
    // imem input (from inst_rom)
    input  logic [XLEN-1:0] imem_rdata0,
    input  logic [XLEN-1:0] imem_rdata1,
    input  logic [1:0][XLEN-1:0] imem_pc ,
    input  logic            imem_valid,
    
    // decode output
    output logic [FETCH_WIDTH-1:0] if_valid,
    output logic [FETCH_WIDTH-1:0][XLEN-1:0] if_pc,
    output logic [FETCH_WIDTH-1:0][XLEN-1:0] if_instr,
    
    // imem output (to inst_rom)
    output logic [XLEN-1:0] imem_addr0,
    output logic [XLEN-1:0] imem_addr1,
    output logic            imem_ren
);

    // ============================================================
    //  PC Register and Prediction Signals
    // ============================================================
    logic [XLEN-1:0] pc_reg;
    logic [XLEN-1:0] pc_next;
    
    logic bp_predict_taken;
    logic [XLEN-1:0] bp_predict_target;
    logic bp_predict_valid;

    // ============================================================
    //  Post-redirect "stretch" logic
    //  ---------------------------------------------------------
    //  On a real redirect (flush_pipeline or redirect_en), the
    //  first valid fetch pair of the new stream normally reaches
    //  if_pc/if_instr and advances again on the very next cycle.
    //  Rename's registered rename_table lookup needs one extra
    //  cycle to catch up (this happens "for free" at reset because
    //  if_valid sits low for a cycle before the first real
    //  response). We reproduce that here explicitly.
    //
    //  inst_rom has NO backpressure: imem_valid/rdata are only
    //  held for the one cycle after imem_ren was asserted, then
    //  gone. So we must stop ISSUING a new request the cycle we
    //  grab the first post-redirect pair (stretch_latch_cycle),
    //  one cycle BEFORE we actually hold the output (stretching).
    //  That way nothing is in flight during the hold cycle, and
    //  requests resume immediately during the hold cycle itself so
    //  the next response lands exactly when the hold ends — no
    //  dropped pair, no extra gap.
    //
    //    1. pc_redirected pulses the cycle a redirect is asserted.
    //    2. stretch_pending arms and stays armed until the first
    //       post-redirect imem_valid response appears.
    //    3. stretch_latch_cycle (comb) is true on that cycle: pair
    //       A gets latched into if_pc/if_instr as normal, but
    //       imem_ren/pc_next are frozen THIS SAME cycle so no
    //       request is in flight for the next (hold) cycle.
    //    4. stretching (registered from stretch_latch_cycle) is
    //       true the following cycle: it holds if_pc/if_instr/
    //       if_valid steady, while imem_ren/pc_next run normally
    //       (freshly un-frozen), so the next response arrives
    //       exactly as the hold ends.
    // ============================================================
    logic pc_redirected;
    logic stretch_pending;
    logic stretching;
    logic stretch_latch_cycle; // comb: this cycle latches pair A AND must freeze new requests
    logic addr_freeze;         // gates imem_ren / pc_next / predict_req
    logic output_hold;         // gates if_pc / if_instr / if_valid

    assign pc_redirected       = flush_pipeline || redirect_en;
    assign stretch_latch_cycle = stretch_pending && !stall && imem_valid;
    assign addr_freeze         = stall || stretch_latch_cycle;
    assign output_hold         = stall || stretching;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            stretch_pending <= 1'b0;
            stretching      <= 1'b0;
        end else begin
            // A fresh redirect always (re)arms stretch_pending, even if
            // we were already mid-stretch from a previous one — the
            // newest redirect's first pair is the one that matters.
            if (pc_redirected) begin
                stretch_pending <= 1'b1;
                stretching      <= 1'b0;
            end else if (stretching) begin
                // We already held for our one bonus cycle; release now.
                stretching <= 1'b0;
            end else if (stretch_latch_cycle) begin
                // Pair A is being latched into if_pc/if_instr below
                // this same cycle. Disarm and hold it one more cycle.
                stretch_pending <= 1'b0;
                stretching      <= 1'b1;
            end
        end
    end
    
    // ============================================================
    //  Branch Predictor Instance
    // ============================================================
    branch_predictor bp_inst (
        .clk(clk),
        .reset(reset),
        .predict_req(fetch_en && !addr_freeze && !flush_pipeline),
        .predict_pc(pc_reg),
        .predict_taken(bp_predict_taken),
        .predict_target(bp_predict_target),
        .predict_valid(bp_predict_valid),
        .update_en(bp_update_en),
        .update_pc(bp_update_pc),
        .update_taken(bp_update_taken),
        .update_target(bp_update_target),
        .update_is_branch(bp_update_is_branch),
        .update_is_call(bp_update_is_call),
        .update_is_return(bp_update_is_return),
        .stat_predictions(),
        .stat_mispredictions(),
        .stat_btb_hits(),
        .stat_btb_misses()
    );
    
    // ============================================================
    //  PC Calculation
    // ============================================================
    always_comb begin
        if (flush_pipeline) begin
            pc_next = branch_target_pc;  // Use branch_target_pc instead of flush_pc
        end else if (redirect_en) begin
            pc_next = redirect_pc;
        end else if (bp_predict_valid && bp_predict_taken && fetch_en && !addr_freeze) begin
            pc_next = bp_predict_target;
        end else if (fetch_en && !addr_freeze) begin
            pc_next = pc_reg + 32'd8;
        end else begin
            pc_next = pc_reg;
        end
    end
    
    // ============================================================
    //  PC Register Update
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_reg <= '0;
        end else begin
            pc_reg <= pc_next;
        end
    end
    
    // ============================================================
    //  Memory Request Generation
    // ============================================================
    always_comb begin
        imem_addr0 = pc_reg;
        imem_addr1 = pc_reg + 32'd4;
        // Generate request if fetch enabled, not stalled/about-to-stretch, no redirect, no flush
        imem_ren = fetch_en && !addr_freeze && !redirect_en && !flush_pipeline;
    end
    
    // ============================================================
    //  Pipeline Stage: Memory Response → Output
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            if_valid <= '0;
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                if_pc[i] <= '0;
                if_instr[i] <= '0;
            end
        end else if (flush_pipeline) begin
            // Flush: invalidate fetch outputs
            if_valid <= '0;
        end else begin
            // Handle stall or internally-generated stretch: freeze outputs
            if (output_hold) begin
                // Keep current values
            end 
            // Handle redirect: flush pipeline
            else if (redirect_en) begin
                if_valid <= '0;
            end
            // Normal operation: accept memory response
            else if (imem_valid) begin
                if_valid <= {FETCH_WIDTH{1'b1}};
                if_pc[0] <= imem_pc[0];
                if_pc[1] <= imem_pc[1];
                if_instr[0] <= imem_rdata0;
                if_instr[1] <= imem_rdata1;
            end
        end
    end

endmodule
