// thread_ctx.sv
// Minimal thread context manager for single-thread core.
// Holds PC and simple control signals (stall, flush, next PC)

`timescale 1ns/1ps
import core_pkg::*;

module thread_ctx #(
  parameter int XLEN = core_pkg::XLEN
)(
  input  logic              clk,
  input  logic              reset_n,

  // control
  input  logic              flush,      // flush pipeline; set PC <- flush_target
  input  logic [31:0]       flush_target,
  input  logic              stall,      // prevent PC update (e.g., stalling fetch)

  // branch redirect from EX
  input  logic              redirect,
  input  logic [31:0]       redirect_target,

  // outputs
  output logic [31:0]       pc_out,     // current fetch PC
  output logic [31:0]       pc_next     // predicted/next PC (for IF)
);

  logic [31:0] pc_reg;

  // reset vector = 0x0 (can be parameterized)
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pc_reg <= 32'h0;
    end else begin
      if (flush) pc_reg <= flush_target;
      else if (redirect) pc_reg <= redirect_target;
      else if (!stall) pc_reg <= pc_reg + 4; // sequential fetch by default
      // if stall: hold pc_reg
    end
  end

  assign pc_out  = pc_reg;
  assign pc_next = pc_reg + 4;

endmodule
