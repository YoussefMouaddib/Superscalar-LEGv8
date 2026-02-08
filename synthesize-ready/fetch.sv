`timescale 1ns/1ps
import core_pkg::*;
module fetch (
  input  logic        clk,
  input  logic        reset,

  input  logic        fetch_en,
  input  logic        stall,
  input  logic        redirect_en,
  input  logic [XLEN-1:0] redirect_pc,
  
  // NEW: Flush from commit (highest priority)
  input  logic        flush_pipeline,
  input  logic [XLEN-1:0] flush_pc,

  // imem input (from memory model)
  input  logic [XLEN-1:0] imem_rdata0,
  input  logic [XLEN-1:0] imem_rdata1,
  input  logic [XLEN-1:0] imem_pc [1:0],
  input  logic            imem_valid,

  // decode output
  output logic [FETCH_WIDTH-1:0] if_valid,
  output logic [FETCH_WIDTH-1:0][XLEN-1:0] if_pc,
  output logic [FETCH_WIDTH-1:0][XLEN-1:0] if_instr,

  // imem output (to memory model)
  output logic [XLEN-1:0] imem_addr0,
  output logic [XLEN-1:0] imem_addr1,
  output logic            imem_ren
);
  // ============================================================
  //  PC Register and Request Generation
  // ============================================================
  logic [XLEN-1:0] pc_reg;
  logic [XLEN-1:0] pc_next;
  //branch prediction
  logic bp_predict_taken;
  logic [XLEN-1:0] bp_predict_target;
  logic bp_predict_valid;


 // Instantiate predictor
  branch_predictor branch_predictor (
      .clk(clk),
      .reset(reset),
      .predict_req(fetch_en && !stall),
      .predict_pc(pc_reg),
      .predict_taken(bp_predict_taken),
      .predict_target(bp_predict_target),
      .predict_valid(bp_predict_valid),
      // Update signals from branch_ex
      .update_en(branch_result_valid),
      .update_pc(branch_pc),
      .update_taken(branch_taken),
      .update_target(branch_target_pc),
      // ... other signals
  );
  
  // Modify PC calculation:
  always_comb begin
      if (redirect_en) begin
          pc_next = redirect_pc;  // Misprediction recovery
      end else if (bp_predict_valid && bp_predict_taken && fetch_en && !stall) begin
          pc_next = bp_predict_target;  // Follow prediction
      end else if (fetch_en && !stall) begin
          pc_next = pc_reg + 32'd8;  // Sequential fetch
      end else begin
          pc_next = pc_reg;
      end
  end

  // PC register update
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_reg <= '0;
    end else begin
      pc_reg <= pc_next;
    end
  end

  // Memory request generation (combinational for immediate response)
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
