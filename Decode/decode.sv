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
  output logic [7:0]                  decode_opcode  [FETCH_WIDTH],  // 8-bit for RS
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
  input  logic                        rename_ready,    // Rename can accept instructions
  output logic                        decode_stall,    // Backpressure to fetch
  output logic                        fetch_stall_req  // Request fetch to stall
);

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
      decode_valid[i] = if_valid[i] && rename_ready;
      decode_pc[i] = if_pc[i];
      
      if (if_valid[i] && rename_ready) begin
        // Extract basic fields (consistent with LEGv8-style encoding)
        opcode_6bit = if_instr[i][31:26];
        rd  = if_instr[i][25:21];
        rn  = if_instr[i][20:16]; 
        rm  = if_instr[i][15:11];
        imm12 = if_instr[i][11:0];
        
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
          6'b000000, 6'b000001, 6'b000010, 6'b000011, 6'b000100, 6'b000101, 6'b000110: begin
            decode_opcode[i] = {2'b00, opcode_6bit}; // Map to 8-bit
            decode_arch_rs2[i] = rm; // Second source register
          end
          
          // I-type: ADDI, SUBI, ANDI, ORI, EORI
          6'b001000, 6'b001001, 6'b001010, 6'b001011, 6'b001100: begin
            decode_opcode[i] = {2'b00, opcode_6bit};
            decode_imm[i] = {{20{imm12[11]}}, imm12}; // Sign-extend
          end
          
          // Load: LDR
          6'b010000: begin
            decode_opcode[i] = 8'b01000000;
            decode_is_load[i] = 1'b1;
            decode_mem_imm[i] = imm12;
            decode_imm[i] = {{20{imm12[11]}}, imm12}; // Sign-extend offset
          end
          
          // Store: STR  
          6'b010001: begin
            decode_opcode[i] = 8'b01000100;
            decode_is_store[i] = 1'b1;
            decode_mem_imm[i] = imm12;
            decode_imm[i] = {{20{imm12[11]}}, imm12}; // Sign-extend offset
          end
          
          // Branch: B
          6'b100000: begin
            decode_opcode[i] = 8'b10000000;
            decode_is_branch[i] = 1'b1;
            // Calculate branch target (PC + sign-extended imm26 << 2)
            imm26 = if_instr[i][25:0];
            decode_branch_target[i] = if_pc[i] + {{6{imm26[25]}}, imm26, 2'b00};
          end
          
          // CBZ
          6'b100100: begin
            decode_opcode[i] = 8'b10010000;
            decode_is_branch[i] = 1'b1;
            // Calculate CBZ target (PC + sign-extended imm19 << 2)
            imm19 = if_instr[i][23:5];
            decode_branch_target[i] = if_pc[i] + {{13{imm19[18]}}, imm19, 2'b00};
          end
          
          // NOP (ANDI x0, x0, 0 pattern or dedicated encoding)
          6'b111111: begin
            decode_opcode[i] = 8'b11111111;
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
