`timescale 1ns/1ps
import core_pkg::*;

module fetch #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int FETCH_WIDTH = core_pkg::FETCH_WIDTH
)(
    input  logic        clk,
    input  logic        reset,
    
    input  logic        fetch_en,
    input  logic        stall,
    input  logic        redirect_en,
    input  logic [XLEN-1:0] redirect_pc,
    
    // Flush from commit (highest priority)
    input  logic        flush_pipeline,
    input  logic [XLEN-1:0] flush_pc,
    
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
    //  Branch Predictor Instance
    // ============================================================
    branch_predictor bp_inst (
        .clk(clk),
        .reset(reset),
        .predict_req(fetch_en && !stall && !flush_pipeline),
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
            pc_next = flush_pc;  // Highest priority: exception/flush
        end else if (redirect_en) begin
            pc_next = redirect_pc;  // Misprediction recovery
        end else if (bp_predict_valid && bp_predict_taken && fetch_en && !stall) begin
            pc_next = bp_predict_target;  // Follow prediction
        end else if (fetch_en && !stall) begin
            pc_next = pc_reg + 32'd8;  // Sequential fetch (2-wide)
        end else begin
            pc_next = pc_reg;  // Stall
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
        // Generate request if fetch enabled, not stalled, no redirect, no flush
        imem_ren = fetch_en && !stall && !redirect_en && !flush_pipeline;
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
            // Handle stall: freeze outputs
            if (stall) begin
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
