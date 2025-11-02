`timescale 1ns/1ps
import core_pkg::*;

module fetch_tb;

  // Parameters
  localparam int PC_W     = 32;
  localparam int INSTR_W  = 32;
  localparam int FETCH_W  = 2;

  // DUT signals
  logic clk, reset;
  logic fetch_en, stall;
  logic redirect_en;
  logic [PC_W-1:0] redirect_pc;

  logic [FETCH_W-1:0]          if_valid;
  logic [PC_W-1:0]             if_pc  [FETCH_W-1:0];
  logic [INSTR_W-1:0]          if_instr [FETCH_W-1:0];

  logic [PC_W-1:0] imem_addr;
  logic imem_ren;
  logic [INSTR_W-1:0] imem_rdata;

  // DUT
  fetch #(
    .FETCH_W(FETCH_W),
    .PC_W(PC_W),
    .INSTR_W(INSTR_W)
  ) dut (
    .clk(clk),
    .reset(reset),
    .fetch_en(fetch_en),
    .stall(stall),
    .redirect_en(redirect_en),
    .redirect_pc(redirect_pc),
    .if_valid(if_valid),
    .if_pc(if_pc),
    .if_instr(if_instr),
    .imem_addr(imem_addr),
    .imem_ren(imem_ren),
    .imem_rdata(imem_rdata)
  );

  // Simple instruction memory (acts like synchronous BRAM with 1-cycle latency)
  logic [INSTR_W-1:0] imem [0:15];
  logic [INSTR_W-1:0] imem_read_data;
  always_ff @(posedge clk)
    if (imem_ren)
      imem_read_data <= imem[imem_addr[5:2]];  // word addressing
  assign imem_rdata = imem_read_data;

  // Clock generation
  always #5 clk = ~clk;

  // Cycle counter for visualization
  int cycle;

  // Trace printing
  task show_state;
    $display("----------------------------------------------------------------");
    $display("Cycle %0d", cycle);
    $display("imem_ren=%0b addr=0x%08h rdata=0x%08h", imem_ren, imem_addr, imem_rdata);
    $display("Fetch_en=%0b Stall=%0b Redirect=%0b PC_redirect=0x%08h",
              fetch_en, stall, redirect_en, redirect_pc);
    $display("if_valid={%0b,%0b}", if_valid[1], if_valid[0]);
    for (int i=0; i<FETCH_W; i++) begin
      $display("  SLOT[%0d]: PC=0x%08h INSTR=0x%08h", i, if_pc[i], if_instr[i]);
    end
  endtask

  // Initialize instruction memory
  initial begin
    // Four dummy instructions (each 32-bit)
    imem[0] = 32'h11111111;
    imem[1] = 32'h22222222;
    imem[2] = 32'h33333333;
    imem[3] = 32'h44444444;
    for (int i = 4; i < 16; i++)
      imem[i] = 32'h00000013; // NOP
  end

  // Stimulus
  initial begin
    clk = 0; reset = 1;
    fetch_en = 0;
    stall = 0;
    redirect_en = 0;
    redirect_pc = 32'h00000000;
    cycle = 0;

    repeat (2) @(posedge clk);
    reset = 0;
    fetch_en = 1;

    // Simulate 10 cycles of fetch
    repeat (10) begin
      @(posedge clk);
      cycle++;
      show_state();

      // For visualization: simulate a stall on cycle 5
      if (cycle == 5) stall = 1;
      if (cycle == 6) stall = 0;

      // On cycle 7, simulate a branch redirect to address 0x8
      if (cycle == 7) begin
        redirect_en = 1;
        redirect_pc = 32'h00000008;
      end else redirect_en = 0;
    end

    $display("----------------------------------------------------------------");
    $display("Simulation finished.");
    $finish;
  end

endmodule
