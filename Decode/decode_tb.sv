`timescale 1ns/1ps
import core_pkg::*;

module fetch_decode_tb;

  // Parameters
  parameter int XLEN = core_pkg::XLEN;
  parameter int FETCH_W = core_pkg::FETCH_WIDTH;

  // Clock and reset
  logic clk, reset;

  // Fetch stage signals
  logic fetch_en, stall, redirect_en;
  logic [XLEN-1:0] redirect_pc;
  logic [FETCH_W-1:0] if_valid;
  logic [XLEN-1:0] if_pc [FETCH_W];
  logic [XLEN-1:0] if_instr [FETCH_W];
  
  // Memory interface
  logic [XLEN-1:0] imem_addr0, imem_addr1;
  logic imem_ren;
  logic [XLEN-1:0] imem_rdata0, imem_rdata1;
  logic [XLEN-1:0] imem_pc [FETCH_W];
  logic imem_valid;

  // Decode stage signals  
  logic [FETCH_W-1:0] decode_valid;
  logic [XLEN-1:0] decode_pc [FETCH_W];
  logic [7:0] decode_opcode [FETCH_W];
  logic [4:0] decode_arch_rd [FETCH_W];
  logic [4:0] decode_arch_rs1 [FETCH_W];
  logic [4:0] decode_arch_rs2 [FETCH_W];
  logic [XLEN-1:0] decode_imm [FETCH_W];
  logic decode_is_branch [FETCH_W];
  logic [XLEN-1:0] decode_branch_target [FETCH_W];
  logic decode_is_load [FETCH_W];
  logic decode_is_store [FETCH_W];
  logic [11:0] decode_mem_imm [FETCH_W];
  
  logic rename_ready, decode_stall, fetch_stall_req;

  // DUT instances
  fetch fetch_dut (
    .clk(clk), .reset(reset),
    .fetch_en(fetch_en), .stall(stall), .redirect_en(redirect_en), .redirect_pc(redirect_pc),
    .if_valid(if_valid), .if_pc(if_pc), .if_instr(if_instr),
    .imem_addr0(imem_addr0), .imem_addr1(imem_addr1), .imem_ren(imem_ren),
    .imem_rdata0(imem_rdata0), .imem_rdata1(imem_rdata1),
    .imem_pc(imem_pc), .imem_valid(imem_valid)
  );

  decode decode_dut (
    .clk(clk), .reset(reset),
    .if_valid(if_valid), .if_pc(if_pc), .if_instr(if_instr),
    .decode_valid(decode_valid), .decode_pc(decode_pc), .decode_opcode(decode_opcode),
    .decode_arch_rd(decode_arch_rd), .decode_arch_rs1(decode_arch_rs1), .decode_arch_rs2(decode_arch_rs2),
    .decode_imm(decode_imm), .decode_is_branch(decode_is_branch), .decode_branch_target(decode_branch_target),
    .decode_is_load(decode_is_load), .decode_is_store(decode_is_store), .decode_mem_imm(decode_mem_imm),
    .rename_ready(rename_ready), .decode_stall(decode_stall), .fetch_stall_req(fetch_stall_req)
  );

  // Instruction memory (6 instructions total)
  logic [XLEN-1:0] imem [0:15];
  
  // Request tracking for memory responses
  logic [XLEN-1:0] saved_addr0, saved_addr1;
  logic saved_ren;
  
  always_ff @(posedge clk) begin
    if (reset) begin
      saved_ren <= 1'b0;
      imem_valid <= 1'b0;
      imem_rdata0 <= '0;
      imem_rdata1 <= '0;
      imem_pc[0] <= '0;
      imem_pc[1] <= '0;
    end else begin
      // Save request addresses
      saved_ren <= imem_ren;
      saved_addr0 <= imem_addr0;
      saved_addr1 <= imem_addr1;
      
      // Generate response with 1-cycle latency
      imem_valid <= saved_ren;
      if (saved_ren) begin
        imem_rdata0 <= imem[saved_addr0[5:2]];  // word addressing
        imem_rdata1 <= imem[saved_addr1[5:2]];
        imem_pc[0] <= saved_addr0;
        imem_pc[1] <= saved_addr1;
      end else begin
        imem_valid <= 1'b0;
      end
    end
  end

  // Clock generation
  always #5 clk = ~clk;

  // Cycle counter
  int cycle;

  // Instruction disassembly helper - FIXED with automatic variables
  function string disassemble_instr(input logic [XLEN-1:0] instr, input logic [XLEN-1:0] pc);
    automatic logic [5:0] opcode;
    automatic logic [4:0] rd, rn, rm;
    automatic logic [11:0] imm12;
    automatic logic [25:0] imm26;
    automatic logic [18:0] imm19;
    
    opcode = instr[31:26];
    rd = instr[25:21];
    rn = instr[20:16];
    rm = instr[15:11];
    imm12 = instr[11:0];
    
    case (opcode)
      // ADD Xd, Xn, Xm
      6'b000000: return $sformatf("ADD x%0d, x%0d, x%0d", rd, rn, rm);
      // ADDI Xd, Xn, #imm
      6'b001000: return $sformatf("ADDI x%0d, x%0d, #0x%03h", rd, rn, imm12);
      // LDR Xt, [Xn, #imm]
      6'b010000: return $sformatf("LDR x%0d, [x%0d, #0x%03h]", rd, rn, imm12);
      // STR Xt, [Xn, #imm]  
      6'b010001: return $sformatf("STR x%0d, [x%0d, #0x%03h]", rd, rn, imm12);
      // B label
      6'b100000: begin
        imm26 = instr[25:0];
        return $sformatf("B 0x%08h", pc + {{6{imm26[25]}}, imm26, 2'b00});
      end
      // CBZ Xn, label
      6'b100100: begin
        imm19 = instr[23:5];
        return $sformatf("CBZ x%0d, 0x%08h", rn, pc + {{13{imm19[18]}}, imm19, 2'b00});
      end
      // NOP
      6'b111111: return "NOP";
      default: return $sformatf("UNKNOWN (opcode: 0x%02h)", opcode);
    endcase
  endfunction

  // Enhanced trace printing
  task print_cycle_state;
    $display("═══════════════════════════════════════════════════════════════════════════════");
    $display("CYCLE %0d", cycle);
    $display("═══════════════════════════════════════════════════════════════════════════════");
    
    // Fetch stage status
    $display("🎯 FETCH STAGE:");
    $display("   Inputs  → fetch_en: %b | stall: %b | redirect: %b | redirect_pc: 0x%08h", 
             fetch_en, stall, redirect_en, redirect_pc);
    $display("   Outputs → if_valid: {%b,%b}", if_valid[1], if_valid[0]);
    for (int i = 0; i < FETCH_W; i++) begin
      if (if_valid[i]) begin
        $display("     SLOT[%0d] ✅: PC=0x%08h INSTR=0x%08h", i, if_pc[i], if_instr[i]);
      end else begin
        $display("     SLOT[%0d] ❌: PC=0x%08h INSTR=0x%08h", i, if_pc[i], if_instr[i]);
      end
    end
    
    // Memory interface
    $display("🔌 MEMORY INTERFACE:");
    $display("   Request  → imem_ren: %b | Addr0: 0x%08h | Addr1: 0x%08h", 
             imem_ren, imem_addr0, imem_addr1);
    $display("   Response → imem_valid: %b | Data0: 0x%08h | Data1: 0x%08h",
             imem_valid, imem_rdata0, imem_rdata1);
    $display("              imem_pc0: 0x%08h | imem_pc1: 0x%08h", imem_pc[0], imem_pc[1]);
    
    // Decode stage status
    $display("🔍 DECODE STAGE:");
    $display("   Control  → rename_ready: %b | decode_stall: %b | fetch_stall_req: %b",
             rename_ready, decode_stall, fetch_stall_req);
    $display("   Outputs  → decode_valid: {%b,%b}", decode_valid[1], decode_valid[0]);
    for (int i = 0; i < FETCH_W; i++) begin
      if (decode_valid[i]) begin
        $display("     SLOT[%0d] ✅ DECODED:", i);
        $display("        PC=0x%08h | Opcode: 0x%02h", decode_pc[i], decode_opcode[i]);
        $display("        Regs: rd=x%0d rs1=x%0d rs2=x%0d", 
                 decode_arch_rd[i], decode_arch_rs1[i], decode_arch_rs2[i]);
        $display("        Imm: 0x%08h | Branch: %b (target: 0x%08h)",
                 decode_imm[i], decode_is_branch[i], decode_branch_target[i]);
        $display("        Memory: load=%b store=%b (offset: 0x%03h)",
                 decode_is_load[i], decode_is_store[i], decode_mem_imm[i]);
      end else begin
        $display("     SLOT[%0d] ❌: No valid decode", i);
      end
    end
    $display("");
  endtask

  // Initialize instruction memory with 6 test instructions
  initial begin
    // Initialize memory with test pattern
    imem[0] = 32'h8B020000; // ADD x0, x0, x2
    imem[1] = 32'h910003E1; // ADDI x1, x0, #1
    imem[2] = 32'hF8400022; // LDR x2, [x1, #0]
    imem[3] = 32'hF8000023; // STR x3, [x1, #0]  
    imem[4] = 32'h14000002; // B +8 (to PC 0x10)
    imem[5] = 32'hB4000044; // CBZ x4, +8 (to PC 0x14)
    
    // Fill rest with NOPs
    for (int i = 6; i < 16; i++)
      imem[i] = 32'hD503201F; // NOP
  end

  // Test sequence
  initial begin
    // Initialize
    clk = 0; reset = 1;
    fetch_en = 0; stall = 0; redirect_en = 0; redirect_pc = '0;
    rename_ready = 1; // Always ready for this test
    cycle = 0;

    // Reset
    repeat (2) @(posedge clk);
    reset = 0;
    fetch_en = 1;

    $display("🚀 STARTING FETCH-DECODE SIMULATION");
    $display("📋 TEST INSTRUCTIONS:");
    $display("   0x00: %s", disassemble_instr(imem[0], 32'h00));
    $display("   0x04: %s", disassemble_instr(imem[1], 32'h04));  
    $display("   0x08: %s", disassemble_instr(imem[2], 32'h08));
    $display("   0x0C: %s", disassemble_instr(imem[3], 32'h0C));
    $display("   0x10: %s", disassemble_instr(imem[4], 32'h10));
    $display("   0x14: %s", disassemble_instr(imem[5], 32'h14));
    $display("");

    // Run simulation for 12 cycles to see pipeline fill
    repeat (12) begin
      @(posedge clk);
      cycle++;
      print_cycle_state();
    end

    $display("🎯 SIMULATION COMPLETED");
    $finish;
  end

endmodule
