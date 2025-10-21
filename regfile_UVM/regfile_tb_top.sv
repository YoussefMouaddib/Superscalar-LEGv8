// regfile_tb_top.sv
`timescale 1ns/1ps
import core_pkg::*;
import regfile_pkg::*;

module regfile_tb_top;
  // clock/reset
  logic clk;
  logic reset_n;

  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz clock for example
  end

  initial begin
    reset_n = 0;
    #25;
    reset_n = 1;
  end

  // instantiate virtual interface
  regfile_if rif(.clk(clk), .reset_n(reset_n));

  // instantiate DUT (connect signals by position or name)
  regfile_synth #(.XLEN(XLEN), .ARCH_REGS(ARCH_REGS), .PREGS(PREGS)) dut (
    .clk     (clk),
    .reset_n (reset_n),

    .wen0    (rif.wen[0]),
    .wtag0   (rif.wtag[0]),
    .wdata0  (rif.wdata[0]),

    .wen1    (rif.wen[1]),
    .wtag1   (rif.wtag[1]),
    .wdata1  (rif.wdata[1]),

    .rtag0   (rif.rtag[0]),
    .rdata0  (rif.rdata[0]),

    .rtag1   (rif.rtag[1]),
    .rdata1  (rif.rdata[1]),

    .rtag2   (rif.rtag[2]),
    .rdata2  (rif.rdata[2]),

    .rtag3   (rif.rtag[3]),
    .rdata3  (rif.rdata[3])
  );

  // set the virtual interface for UVM components
  initial begin
    uvm_config_db#(virtual regfile_if)::set(null, "*", "vif", rif);
    // start UVM test
    run_test("regfile_test");
  end

endmodule : regfile_tb_top
