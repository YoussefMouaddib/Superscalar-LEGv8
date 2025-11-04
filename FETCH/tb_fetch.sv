`timescale 1ns/1ps
import core_pkg::*;

module fetch_tb;

  // Parameters
  parameter int PC_W = core_pkg::XLEN;
  parameter int INSTR_W = core_pkg::XLEN;
  parameter int FETCH_W = core_pkg::FETCH_WIDTH;

  // DUT signals
  logic clk, reset;
  logic fetch_en, stall;
  logic redirect_en;
  logic [PC_W-1:0] redirect_pc;

  logic [FETCH_W-1:0]          if_valid;
  logic [PC_W-1:0]             if_pc  [FETCH_W-1:0];
  logic [INSTR_W-1:0]          if_instr [FETCH_W-1:0];

  logic [PC_W-1:0] imem_addr0, imem_addr1;
  logic imem_ren;
  logic [INSTR_W-1:0] imem_rdata0, imem_rdata1;

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
    .imem_addr0(imem_addr0),
    .imem_addr1(imem_addr1),
    .imem_ren(imem_ren),
    .imem_rdata0(imem_rdata0),
    .imem_rdata1(imem_rdata1)
  );

  // Dual-port instruction memory (synchronous BRAM with 1-cycle latency)
  logic [INSTR_W-1:0] imem [0:15];
  
  always_ff @(posedge clk) begin
    if (imem_ren) begin
      imem_rdata0 <= imem[imem_addr0[5:2]];  // word addressing
      imem_rdata1 <= imem[imem_addr1[5:2]];  // word addressing  
    end
  end

  // Clock generation
  always #5 clk = ~clk;

  // Cycle counter
  int cycle;

  // Enhanced trace printing
  task show_state;
    $display("----------------------------------------------------------------");
    $display("CYCLE %0d", cycle);
    $display("----------------------------------------------------------------");
    
    $display("\n📥 INPUTS:");
    $display("Fetch_en: %b | Stall: %b | Redirect: %b | Redirect_PC: 0x%08h",
             fetch_en, stall, redirect_en, redirect_pc);
    
    $display("\n🔌 MEMORY INTERFACE:");
    $display("imem_ren: %b | Addr0: 0x%08h | Addr1: 0x%08h", 
             imem_ren, imem_addr0, imem_addr1);
    $display("imem_rdata0: 0x%08h | imem_rdata1: 0x%08h", imem_rdata0, imem_rdata1);
    
    $display("\n📤 OUTPUTS:");
    $display("if_valid: {%b,%b}", if_valid[1], if_valid[0]);
    for (int i=0; i<FETCH_W; i++) begin
      if (if_valid[i]) begin
        $display("  SLOT[%0d] ✅: PC=0x%08h INSTR=0x%08h", i, if_pc[i], if_instr[i]);
      end else begin
        $display("  SLOT[%0d] ❌: PC=0x%08h INSTR=0x%08h", i, if_pc[i], if_instr[i]);
      end
    end
  endtask

  // Initialize instruction memory
  initial begin
    // Initialize with test pattern
    imem[0] = 32'h11111111;  // PC 0x00
    imem[1] = 32'h22222222;  // PC 0x04  
    imem[2] = 32'h33333333;  // PC 0x08
    imem[3] = 32'h44444444;  // PC 0x0C
    imem[4] = 32'h55555555;  // PC 0x10
    imem[5] = 32'h66666666;  // PC 0x14
    for (int i = 6; i < 16; i++)
      imem[i] = 32'h00000013; // NOP
  end

  // Test sequence
  initial begin
    clk = 0; reset = 1;
    fetch_en = 0;
    stall = 0;
    redirect_en = 0;
    redirect_pc = '0;
    cycle = 0;

    // Reset
    repeat (2) @(posedge clk);
    reset = 0;
    fetch_en = 1;

    // Test scenarios
    repeat (12) begin
      @(posedge clk);
      cycle++;
      show_state();

      // Test stall on cycle 4
      if (cycle == 4) stall = 1;
      if (cycle == 5) stall = 0;

      // Test branch redirect on cycle 7 to address 0x08
      if (cycle == 7) begin
        redirect_en = 1;
        redirect_pc = 32'h00000008;
      end else begin
        redirect_en = 0;
      end
    end

    $display("\n🎯 SIMULATION FINISHED");
    $finish;
  end

endmodule
