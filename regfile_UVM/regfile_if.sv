// regfile_if.sv
`timescale 1ns/1ps
import core_pkg::*;

interface regfile_if(input logic clk, input logic reset_n);

  // 2-way issue lanes each with wr_en, rd_en, addrs, data
  logic [1:0]                    wen;
  core_pkg::preg_tag_t           wtag [1:0];
  logic [XLEN-1:0]               wdata [1:0];

  core_pkg::preg_tag_t           rtag  [4];
  logic [XLEN-1:0]               rdata [4];

  // Clocking block for synchronous accesses (driver uses posedge)
  clocking cb @(posedge clk);
    default input #1step output #1step;
    output wen;
    output wtag;
    output wdata;
    input  rdata;
  endclocking

  // simple task to write zero to control signals (idle)
  task automatic drive_idle();
    wen[0] = 0; wen[1] = 0;
    wtag[0] = '0; wtag[1] = '0;
    wdata[0] = '0; wdata[1] = '0;
  endtask

endinterface : regfile_if
