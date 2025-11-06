`timescale 1ns/1ps
import core_pkg::*;

module decode (
  input  logic        clk,
  input  logic        reset,
  
  // Input from Fetch stage
  input  logic [FETCH_WIDTH-1:0]      if_valid,
  input  logic [XLEN-1:0]             if_pc      [FETCH_WIDTH],
  input  logic [XLEN-1:0]             if_instr   [FETCH_WIDTH],
  
  // Output to Rename stage
  output logic [FETCH_WIDTH-1:0]      decode_valid,
  output logic [XLEN-1:0]             decode_pc      [FETCH_WIDTH],
  output logic [7:0]                  decode_opcode  [FETCH_WIDTH],
  output logic [4:0]                  decode_arch_rd [FETCH_WIDTH],
  output logic [4:0]                  decode_arch_rs1[FETCH_WIDTH],
  output logic [4:0]                  decode_arch_rs2[FETCH_WIDTH],
  output logic [XLEN-1:0]             decode_imm     [FETCH_WIDTH],
  output logic                        decode_is_branch [FETCH_WIDTH],
  output logic [XLEN-1:0]             decode_branch_target [FETCH_WIDTH],
  output logic                        decode_is_load  [FETCH_WIDTH],
  output logic                        decode_is_store [FETCH_WIDTH],
  output logic [11:0]                 decode_mem_imm [FETCH_WIDTH],
  
  // Backpressure/stall interface
  input  logic                        rename_ready,
  output logic                        decode_stall,
  output logic                        fetch_stall_req
);

  // PIPELINE REGISTERS - Fix the combinational timing issue
  logic [FETCH_WIDTH-1:0]      if_valid_ff;
  logic [XLEN-1:0]             if_pc_ff      [FETCH_WIDTH];
  logic [XLEN-1:0]             if_instr_ff   [FETCH_WIDTH];

  // Pipeline stage: fetch -> decode
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_valid_ff <= '0;
      for (int i = 0; i < FETCH_WIDTH; i++) begin
        if_pc_ff[i] <= '0;
        if_instr_ff[i] <= '0;
      end
    end else if (rename_ready) begin
      if_valid_ff <= if_valid;
      if_pc_ff <= if_pc;
      if_instr_ff <= if_instr;
    end
  end

  // Internal instruction decoding
  always_comb begin
    // Declare ALL variables at the beginning with automatic
    automatic logic [5:0] opcode_6bit;
    automatic logic [4:0] rd, rn, rm;
    automatic logic [11:0] imm12;
    automatic logic [25:0] imm26;
    automatic logic [18:0] imm19;
    
    decode_stall = 1'b0;
    fetch_stall_req = 1'b0;
    
    for (int i = 0; i < FETCH_WIDTH; i++) begin
      // Use PIPELINE REGISTERS, not direct inputs
      decode_valid[i] = if_valid_ff[i] && rename_ready;
      decode_pc[i] = if_pc_ff[i];
      
      if (if_valid_ff[i] && rename_ready) begin
        // Extract basic fields (LEGv8 encoding)
        opcode_6bit = if_instr_ff[i][31:26];
        rd  = if_instr_ff[i][25:21];
        rn  = if_instr_ff[i][20:16]; 
        rm  = if_instr_ff[i][15:11];
        imm12 = if_instr_ff[i][11:0];
        
        // Default values
        decode_arch_rd[i] = rd;
        decode_arch_rs1[i] = rn;
        decode_arch_rs2[i] = rm;
        decode_imm[i] = '0;
        decode_is_branch[i] = 1'b0;
        decode_branch_target[i] = '0;
        decode_is_load[i] = 1'b0;
        decode_is_store[i] = 1'b0;
        decode_mem_imm[i] = '0;
        
        // Decode instruction types and set micro-op fields
        case (opcode_6bit)
          // R-type: ADD, SUB, AND, ORR, EOR, LSL, LSR
          6'b000000: begin
            decode_opcode[i] = 8'b00000000; // ADD
            decode_arch_rs2[i] = rm; // Second source register
          end
          
          // I-type: ADDI, SUBI, ANDI, ORI, EORI
          6'b001000: begin
            decode_opcode[i] = 8'b00001000; // ADDI
            decode_imm[i] = {{20{imm12[11]}}, imm12}; // Sign-extend
          end
          
          // Load: LDR
          6'b010000: begin
            decode_opcode[i] = 8'b01000000; // LDR
            decode_is_load[i] = 1'b1;
            decode_mem_imm[i] = imm12;
            decode_imm[i] = {{20{imm12[11]}}, imm12}; // Sign-extend offset
          end
          
          // Store: STR  
          6'b010001: begin
            decode_opcode[i] = 8'b01000100; // STR
            decode_is_store[i] = 1'b1;
            decode_mem_imm[i] = imm12;
            decode_imm[i] = {{20{imm12[11]}}, imm12}; // Sign-extend offset
          end
          
          // Branch: B
          6'b100000: begin
            decode_opcode[i] = 8'b10000000; // B
            decode_is_branch[i] = 1'b1;
            // Calculate branch target (PC + sign-extended imm26 << 2)
            imm26 = if_instr_ff[i][25:0];
            decode_branch_target[i] = if_pc_ff[i] + ({{6{imm26[25]}}, imm26, 2'b00});
          end
          
          // CBZ
          6'b100100: begin
            decode_opcode[i] = 8'b10010000; // CBZ
            decode_is_branch[i] = 1'b1;
            // Calculate CBZ target (PC + sign-extended imm19 << 2)
            imm19 = if_instr_ff[i][23:5];
            decode_branch_target[i] = if_pc_ff[i] + ({{13{imm19[18]}}, imm19, 2'b00});
          end
          
          // NOP
          6'b111111: begin
            decode_opcode[i] = 8'b11111111; // NOP
            decode_arch_rd[i] = 5'b0; // x0
            decode_arch_rs1[i] = 5'b0;
            decode_arch_rs2[i] = 5'b0;
          end
          
          default: begin
            // Illegal instruction - convert to NOP
            decode_opcode[i] = 8'b11111111;
            decode_arch_rd[i] = 5'b0;
            decode_arch_rs1[i] = 5'b0;
            decode_arch_rs2[i] = 5'b0;
          end
        endcase
      end else begin
        // Invalid slot
        decode_valid[i] = 1'b0;
        decode_opcode[i] = '0;
        decode_arch_rd[i] = '0;
        decode_arch_rs1[i] = '0;
        decode_arch_rs2[i] = '0;
        decode_imm[i] = '0;
        decode_is_branch[i] = 1'b0;
        decode_branch_target[i] = '0;
        decode_is_load[i] = 1'b0;
        decode_is_store[i] = 1'b0;
        decode_mem_imm[i] = '0;
      end
    end
    
    // Backpressure: stall if rename can't accept instructions
    if (if_valid != '0 && !rename_ready) begin
      decode_stall = 1'b1;
      fetch_stall_req = 1'b1;
    end
  end

endmodule
