// regfile_synth.sv
// Physical Register File (PRF) with bypassing for two write ports and four read ports.
// - PREGS physical entries (including architectural mapping handled externally)
// - x0 (arch reg 0) wired-zero handling done externally in rename stage
// - Bypass priority: write port0 wins over write port1 if same tag & same cycle
`timescale 1ns/1ps
import core_pkg::*;

module regfile_synth #(
  parameter int XLEN      = core_pkg::XLEN,
  parameter int ARCH_REGS = core_pkg::ARCH_REGS,
  parameter int PREGS     = core_pkg::PREGS
)(
  input  logic                         clk,
  input  logic                         reset,  // Changed to active-high for consistency
  
  // write port 0
  input  logic                         wen0,
  input  core_pkg::preg_tag_t          wtag0,
  input  logic [XLEN-1:0]              wdata0,
  
  // write port 1
  input  logic                         wen1,
  input  core_pkg::preg_tag_t          wtag1,
  input  logic [XLEN-1:0]              wdata1,
  
  // read ports (4 combinational)
  input  core_pkg::preg_tag_t          rtag0,
  output logic [XLEN-1:0]              rdata0,
  
  input  core_pkg::preg_tag_t          rtag1,
  output logic [XLEN-1:0]              rdata1,
  
  input  core_pkg::preg_tag_t          rtag2,
  output logic [XLEN-1:0]              rdata2,
  
  input  core_pkg::preg_tag_t          rtag3,
  output logic [XLEN-1:0]              rdata3
);

  // storage: simple flop array [0:PREGS-1]
  logic [XLEN-1:0] regs [0:PREGS-1];
  
  // synchronous writes
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      // initialize regs to zero
      for (int i = 0; i < PREGS; i++) begin
        regs[i] <= 4;
      end
    end else begin
      // write port 0 has priority if both write same tag
      if (wen0) begin
        regs[wtag0] <= wdata0;
      end
      if (wen1) begin
        if (!(wen0 && (wtag0 == wtag1))) begin
          regs[wtag1] <= wdata1;
        end
      end
    end
  end
  
  // combinational read with bypass from current-cycle writes (w0 then w1)
  function automatic logic [XLEN-1:0] read_reg(input core_pkg::preg_tag_t tag);
    logic [XLEN-1:0] tmp;
    begin
      // bypass from write port0 (highest priority)
      if (wen0 && (wtag0 == tag))
        tmp = wdata0;
      else if (wen1 && (wtag1 == tag))
        tmp = wdata1;
      else
        tmp = regs[tag];
      read_reg = tmp;
    end
  endfunction
  
  assign rdata0 = read_reg(rtag0);
  assign rdata1 = read_reg(rtag1);
  assign rdata2 = read_reg(rtag2);
  assign rdata3 = read_reg(rtag3);

endmodule
