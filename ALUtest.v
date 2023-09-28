`timescale 1ns / 1ps
`define CYCLE 10
`define WORD  64
`define INSTR_LEN 32
//`define DMEMFILE  "H:/ELC3338/Team8/CompOrg_Spring2018_S1_Team8/testfiles/ramData2.data"
//`define IMEMFILE  "H:/ELC3338/Team8/CompOrg_Spring2018_S1_Team8/testfiles/instrData2.data"
//`define RMEMFILE  "H:/ELC3338/Team8/CompOrg_Spring2018_S1_Team8/testfiles//regData2.data"

`define ADD  11'b10001011000
`define SUB  11'b11001011000
`define STUR 11'b11111000000
`define CBZ  11'b10110100XXX
`define B    11'b000101XXXXX
`define ORR  11'b10101010000
`define AND  11'b10001010000
`define LDUR 11'b11111000010

`define ALUOp_DTYPE  2'b00
`define ALUOp_RTYPE  2'b10
`define ALUOp_BRANCH 2'b01

`define alu_add 4'b0010
`define alu_cbz 4'b0111
`define alu_and 4'b0000
`define alu_orr 4'b0001
`define alu_sub 4'b0110

module ALU_test;

reg[`WORD-1:0] a;
reg[`WORD-1:0] b;
wire [3:0] alu_control;
wire [`WORD-1:0] alu_result;
wire zero;
reg [1:0] alu_op;
reg [10:0] opcode;

oscillator myOsc(clk);

ALU myALU(
    .data_1(a),
    .data_2(b),
    .control(alu_control),
    .result(alu_result),
    .flag(zero)
    );
    
alu_control myALU_control(
    .alu_op(alu_op),
    .opcode(opcode),
    .control_bits(alu_control)
    );

initial 
begin
    a<=`WORD'd15;
    b<=`WORD'd10;
    opcode<=`ADD;
    alu_op<=2'b10;
    
    #`CYCLE;
    opcode<=`SUB;
    
    #`CYCLE;
    opcode<=`AND;
    
    #`CYCLE;
    opcode<=`ORR;
    
    #`CYCLE;
    alu_op<=`ALUOp_DTYPE;
    opcode<=`LDUR;
    
    #`CYCLE;
    alu_op<=`ALUOp_DTYPE;
    opcode<=`STUR;
    
    #`CYCLE;
    alu_op<=`ALUOp_BRANCH;
    opcode<=`CBZ;
    
    #`CYCLE;
    opcode<=`B;
    
    #`CYCLE;
    a<=`WORD'd15;
    b<=`WORD'd15;
    opcode<=`ADD;
    alu_op<=`ALUOp_RTYPE;
    
    #`CYCLE;
    opcode<=`SUB;
       
    #`CYCLE;
    opcode<=`ADD;    
    
    #`CYCLE;
    a<=`WORD'd15;
    b<=`WORD'd0;
    opcode<=`CBZ;
    alu_op<=`ALUOp_BRANCH;
    
    #`CYCLE;
    a<=`WORD'd15;
    b<=`WORD'd15;
    opcode<=`ADD;
    alu_op<=`ALUOp_RTYPE;    
end            
endmodule