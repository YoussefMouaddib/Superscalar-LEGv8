// Detailed Fetch Testbench with Visual Debugging
`timescale 1ns/1ps
import core_pkg::*;

module fetch_tb;

  // Parameters
  parameter int ADDR_WIDTH = core_pkg::XLEN;
  parameter int INSTR_WIDTH = core_pkg::XLEN;
  parameter int FETCH_W = core_pkg::FETCH_WIDTH;

  // DUT signals
  logic clk, reset;
  logic fetch_en, stall;
  logic redirect_en;
  logic [ADDR_WIDTH-1:0] redirect_pc;

  logic [FETCH_W-1:0]          if_valid;
  logic [ADDR_WIDTH-1:0]       if_pc  [FETCH_W-1:0];
  logic [INSTR_WIDTH-1:0]      if_instr [FETCH_W-1:0];

  logic [ADDR_WIDTH-1:0] imem_addr0, imem_addr1;
  logic imem_ren;
  logic [INSTR_WIDTH-1:0] imem_rdata0, imem_rdata1;
  
  // imem response interface
  logic [ADDR_WIDTH-1:0] imem_pc [FETCH_W-1:0];
  logic imem_valid;

  // DUT
  fetch dut (
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
    .imem_rdata1(imem_rdata1),
    .imem_pc(imem_pc),
    .imem_valid(imem_valid)
  );

  // ============================================================
  //  Instruction Memory Model (Synchronous 1-cycle latency)
  // ============================================================
  logic [INSTR_WIDTH-1:0] imem [15:0];
  
  // Memory response pipeline - captures request and responds next cycle
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      imem_valid <= 1'b0;
      imem_rdata0 <= '0;
      imem_rdata1 <= '0;
      imem_pc[0] <= '0;
      imem_pc[1] <= '0;
    end else begin
      // Memory responds in the cycle AFTER a request
      if (imem_ren) begin
        // Capture the request addresses and return data next cycle
        imem_valid <= 1'b1;
        imem_rdata0 <= imem[imem_addr0[5:2]];  // Word-addressed
        imem_rdata1 <= imem[imem_addr1[5:2]];
        imem_pc[0] <= imem_addr0;
        imem_pc[1] <= imem_addr1;
      end else begin
        // No request this cycle, clear valid
        imem_valid <= 1'b0;
      end
    end
  end

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // Cycle counter
  int cycle;

  // ============================================================
  //  Enhanced Trace Printing
  // ============================================================
  task show_state;
    $display("\n================================================================");
    $display("CYCLE %0d", cycle);
    $display("================================================================");
    
    $display("\n📥 INPUTS TO FETCH:");
    $display("  fetch_en: %b | stall: %b | redirect_en: %b | redirect_pc: 0x%08h",
             fetch_en, stall, redirect_en, redirect_pc);
    
    $display("\n🔌 MEMORY INTERFACE:");
    $display("  REQUEST  → imem_ren: %b | addr0: 0x%08h | addr1: 0x%08h", 
             imem_ren, imem_addr0, imem_addr1);
    $display("  RESPONSE ← imem_valid: %b | rdata0: 0x%08h | rdata1: 0x%08h", 
             imem_valid, imem_rdata0, imem_rdata1);
    $display("             imem_pc[0]: 0x%08h | imem_pc[1]: 0x%08h",
             imem_pc[0], imem_pc[1]);
    
    $display("\n📤 OUTPUTS TO DECODE:");
    $display("  if_valid: {%b, %b}", if_valid[1], if_valid[0]);
    for (int i=0; i<FETCH_W; i++) begin
      if (if_valid[i]) begin
        $display("  SLOT[%0d] ✅ VALID  : PC=0x%08h  INSTR=0x%08h", 
                 i, if_pc[i], if_instr[i]);
      end else begin
        $display("  SLOT[%0d] ❌ INVALID: PC=0x%08h  INSTR=0x%08h", 
                 i, if_pc[i], if_instr[i]);
      end
    end
    
    // Verification check
    if (if_valid[0]) begin
      automatic logic [INSTR_WIDTH-1:0] expected_instr0 = imem[if_pc[0][5:2]];
      if (if_instr[0] !== expected_instr0) begin
        $display("  ⚠️  ERROR: SLOT[0] instruction mismatch!");
        $display("      Expected: 0x%08h, Got: 0x%08h", expected_instr0, if_instr[0]);
      end else begin
        $display("  ✓ SLOT[0] instruction correct");
      end
    end
    
    if (if_valid[1]) begin
      automatic logic [INSTR_WIDTH-1:0] expected_instr1 = imem[if_pc[1][5:2]];
      if (if_instr[1] !== expected_instr1) begin
        $display("  ⚠️  ERROR: SLOT[1] instruction mismatch!");
        $display("      Expected: 0x%08h, Got: 0x%08h", expected_instr1, if_instr[1]);
      end else begin
        $display("  ✓ SLOT[1] instruction correct");
      end
    end
    
    $display("================================================================");
  endtask

  // ============================================================
  //  Initialize Instruction Memory
  // ============================================================
  initial begin
    // Initialize with test pattern
    imem[0]  = 32'h11111111;  // PC 0x00
    imem[1]  = 32'h22222222;  // PC 0x04  
    imem[2]  = 32'h33333333;  // PC 0x08
    imem[3]  = 32'h44444444;  // PC 0x0C
    imem[4]  = 32'h55555555;  // PC 0x10
    imem[5]  = 32'h66666666;  // PC 0x14
    imem[6]  = 32'h77777777;  // PC 0x18
    imem[7]  = 32'h88888888;  // PC 0x1C
    imem[8]  = 32'h99999999;  // PC 0x20
    imem[9]  = 32'hAAAAAAAA;  // PC 0x24
    imem[10] = 32'hBBBBBBBB;  // PC 0x28
    imem[11] = 32'hCCCCCCCC;  // PC 0x2C
    for (int i = 12; i < 16; i++)
      imem[i] = 32'h00000013; // NOP
  end

  // ============================================================
  //  Test Sequence
  // ============================================================
  initial begin
    $display("\n╔══════════════════════════════════════════════════════════════╗");
    $display("║           FETCH MODULE TESTBENCH                             ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    
    // Initialize signals
    clk = 0;
    reset = 1;
    fetch_en = 0;
    stall = 0;
    redirect_en = 0;
    redirect_pc = '0;
    cycle = 0;

    // ==================== Reset ====================
    $display("\n🔄 Asserting Reset...");
    repeat (2) @(posedge clk);
    
    @(posedge clk);
    cycle++;
    reset = 0;
    $display("\n✅ Reset Released - Starting Fetch");
    show_state();

    // ==================== Normal Sequential Fetch ====================
    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 1: Normal Sequential Fetch");
    fetch_en = 1;
    #1; // Let combinational logic settle
    show_state();

    // Let it fetch for several cycles
    repeat (4) begin
      @(posedge clk);
      cycle++;
      #1;
      show_state();
    end

    // ==================== Test Stall ====================
    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 2: Stall Asserted (outputs should freeze)");
    stall = 1;
    #1;
    show_state();

    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 2: Stall Held (outputs still frozen)");
    #1;
    show_state();

    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 2: Stall Released (resume fetching)");
    stall = 0;
    #1;
    show_state();

    // ==================== Test Branch Redirect ====================
    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 3: Branch Redirect to 0x00000008");
    redirect_en = 1;
    redirect_pc = 32'h00000008;
    #1;
    show_state();

    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 3: After Redirect (should fetch from 0x08)");
    redirect_en = 0;
    #1;
    show_state();

    // Continue for a few more cycles
    repeat (3) begin
      @(posedge clk);
      cycle++;
      #1;
      show_state();
    end

    // ==================== Test Fetch Disable ====================
    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 4: Fetch Disabled");
    fetch_en = 0;
    #1;
    show_state();

    @(posedge clk);
    cycle++;
    $display("\n🎯 TEST 4: Fetch Re-enabled");
    fetch_en = 1;
    #1;
    show_state();

    // Final cycles
    repeat (2) begin
      @(posedge clk);
      cycle++;
      #1;
      show_state();
    end

    $display("\n\n╔══════════════════════════════════════════════════════════════╗");
    $display("║                   TEST COMPLETE                              ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    $finish;
  end

  // Timeout watchdog
  initial begin
    #10000;
    $display("\n❌ ERROR: Simulation timeout!");
    $finish;
  end

endmodule
