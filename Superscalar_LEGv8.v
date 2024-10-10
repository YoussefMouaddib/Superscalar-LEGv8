module ARM_CPU

(
  input RESET,
  input CLOCK,

  // Instruction Cache/Memory Input (Two instructions fetched simultaneously)
  input [31:0] IC1,  // First instruction
  input [31:0] IC2,  // Second instruction

  // Data Memory Inputs (Shared memory data bus for both instructions)
  input [63:0] mem_data_in1,  // Data for first instruction
  input [63:0] mem_data_in2,  // Data for second instruction

  // Program Counter for both pipelines (superscalar requires two PCs)
  output reg [63:0] PC1,  // PC for first instruction stream

  // Register File Interface (For both instructions)
  // Read registers for instruction 1
  output [4:0] read_reg1_1,   // First source register for first instruction
  output [4:0] read_reg2_1,   // Second source register for first instruction
  input  [63:0] reg_data1_1,  // Data from first source register (first instruction)
  input  [63:0] reg_data2_1,  // Data from second source register (first instruction)
  output [4:0] write_reg1_1,   // Destination register for first instruction
  output [63:0] write_data1_1, // Data to write back (first instruction)
  output regwrite1_1,          // Write enable signal for first instruction

  // Read registers for instruction 2
  output [4:0] read_reg1_2,   // First source register for second instruction
  output [4:0] read_reg2_2,   // Second source register for second instruction
  input  [63:0] reg_data1_2,  // Data from first source register (second instruction)
  input  [63:0] reg_data2_2,  // Data from second source register (second instruction)

  // Write-back to register file for instruction 2
  output [4:0] write_reg1_2,   // Destination register for second instruction
  output [63:0] write_data1_2, // Data to write back (second instruction)
  output regwrite1_2,          // Write enable signal for second instruction

  // Memory interface for both instruction streams
  output [63:0] mem_address_out1,  // Memory address for first instruction
  output [63:0] mem_address_out2,  // Memory address for second instruction
  output [63:0] mem_data_out1,     // Data to write to memory for first instruction
  output [63:0] mem_data_out2,     // Data to write to memory for second instruction
  output control_memwrite_out1,    // Memory write control for first instruction
  output control_memwrite_out2,    // Memory write control for second instruction
  output control_memread_out1,     // Memory read control for first instruction
  output control_memread_out2      // Memory read control for second instruction
);


 // Superscalar: Fetch two instructions per cycle
wire Hazard_PCWrite1, Hazard_PCWrite2, Hazard_IFIDWrite1, Hazard_IFIDWrite2;
wire [63:0] PC1, PC2;
wire [31:0] IC1, IC2;
wire PCSrc_wire;
wire [63:0] jump_PC_wire;

always @(posedge CLOCK) begin
    if (Hazard_PCWrite1 !== 1'b1) begin
        if (PC1 === 64'bx) begin
            PC1 <= 0;
        end else if (PCSrc_wire == 1'b1) begin
            PC1 <= jump_PC_wire;
        end else begin
            PC1 <= PC1 + 4;
        end
    end
    if (Hazard_PCWrite2 !== 1'b1) begin
        if (PC2 === 64'bx) begin
            PC2 <= 4; // Next instruction's PC
        end else if (PCSrc_wire == 1'b1) begin
            PC2 <= jump_PC_wire + 4;
        end else begin
            PC2 <= PC2 + 4;
        end
    end
end

// Fetch both instructions
IFID IFID1 (CLOCK, PC1, IC1, Hazard_IFIDWrite1, IFID_PC1, IFID_IC1);
IFID IFID2 (CLOCK, PC2, IC2, Hazard_IFIDWrite2, IFID_PC2, IFID_IC2);

	/* Stage : Instruction Decode */

// Wires for the first instruction
wire IDEX_memRead1;
wire [4:0] IDEX_write_reg1;
wire Control_mux_wire1;
HazardDetection HazardDetection1 (IDEX_memRead1, IDEX_write_reg1, IFID_PC1, IFID_IC1, Hazard_IFIDWrite1, Hazard_PCWrite1, Control_mux_wire1);

// Wires for the second instruction
wire IDEX_memRead2;
wire [4:0] IDEX_write_reg2;
wire Control_mux_wire2;
HazardDetection HazardDetection2 (IDEX_memRead2, IDEX_write_reg2, IFID_PC2, IFID_IC2, Hazard_IFIDWrite2, Hazard_PCWrite2, Control_mux_wire2);

// Control signals for the first instruction
wire [1:0] CONTROL_aluop1; // EX
wire CONTROL_alusrc1;       // EX
wire CONTROL_isZeroBranch1; // M
wire CONTROL_isUnconBranch1;// M
wire CONTROL_memRead1;      // M
wire CONTROL_memwrite1;     // M
wire CONTROL_regwrite1;     // WB
wire CONTROL_mem2reg1;      // WB

// Control signals for the second instruction
wire [1:0] CONTROL_aluop2; // EX
wire CONTROL_alusrc2;       // EX
wire CONTROL_isZeroBranch2; // M
wire CONTROL_isUnconBranch2;// M
wire CONTROL_memRead2;      // M
wire CONTROL_memwrite2;     // M
wire CONTROL_regwrite2;     // WB
wire CONTROL_mem2reg2;      // WB

// ARM Control for first instruction
ARM_Control arm_control1 (IFID_IC1[31:21], CONTROL_aluop1, CONTROL_alusrc1, CONTROL_isZeroBranch1, CONTROL_isUnconBranch1, CONTROL_memRead1, CONTROL_memwrite1, CONTROL_regwrite1, CONTROL_mem2reg1);

// ARM Control for second instruction
ARM_Control arm_control2 (IFID_IC2[31:21], CONTROL_aluop2, CONTROL_alusrc2, CONTROL_isZeroBranch2, CONTROL_isUnconBranch2, CONTROL_memRead2, CONTROL_memwrite2, CONTROL_regwrite2, CONTROL_mem2reg2);

// Control Mux for first instruction
wire [1:0] CONTROL_aluop_wire1; // EX
wire CONTROL_alusrc_wire1;       // EX
wire CONTROL_isZeroBranch_wire1; // M
wire CONTROL_isUnconBranch_wire1;// M
wire CONTROL_memRead_wire1;      // M
wire CONTROL_memwrite_wire1;     // M
wire CONTROL_regwrite_wire1;     // WB
wire CONTROL_mem2reg_wire1;      // WB

// Control Mux for second instruction
wire [1:0] CONTROL_aluop_wire2; // EX
wire CONTROL_alusrc_wire2;       // EX
wire CONTROL_isZeroBranch_wire2; // M
wire CONTROL_isUnconBranch_wire2;// M
wire CONTROL_memRead_wire2;      // M
wire CONTROL_memwrite_wire2;     // M
wire CONTROL_regwrite_wire2;     // WB
wire CONTROL_mem2reg_wire2;      // WB

// Control Mux logic for first instruction
Control_Mux control_mux1 (
    CONTROL_aluop1, CONTROL_alusrc1, CONTROL_isZeroBranch1, CONTROL_isUnconBranch1, CONTROL_memRead1, CONTROL_memwrite1, CONTROL_regwrite1, CONTROL_mem2reg1, 
    Control_mux_wire1, CONTROL_aluop_wire1, CONTROL_alusrc_wire1, CONTROL_isZeroBranch_wire1, CONTROL_isUnconBranch_wire1, CONTROL_memRead_wire1, CONTROL_memwrite_wire1, 
    CONTROL_regwrite_wire1, CONTROL_mem2reg_wire1
);

// Control Mux logic for second instruction
Control_Mux control_mux2 (
    CONTROL_aluop2, CONTROL_alusrc2, CONTROL_isZeroBranch2, CONTROL_isUnconBranch2, CONTROL_memRead2, CONTROL_memwrite2, CONTROL_regwrite2, CONTROL_mem2reg2, 
    Control_mux_wire2, CONTROL_aluop_wire2, CONTROL_alusrc_wire2, CONTROL_isZeroBranch_wire2, CONTROL_isUnconBranch_wire2, CONTROL_memRead_wire2, CONTROL_memwrite_wire2, 
    CONTROL_regwrite_wire2, CONTROL_mem2reg_wire2
);

// ID Mux for both instructions
wire [4:0] reg2_wire1, reg2_wire2;
ID_Mux id_mux1(IFID_IC1[20:16], IFID_IC1[4:0], IFID_IC1[28], reg2_wire1);
ID_Mux id_mux2(IFID_IC2[20:16], IFID_IC2[4:0], IFID_IC2[28], reg2_wire2);


// Sign Extend for both instructions
wire [63:0] sign_extend_wire1, sign_extend_wire2;
SignExtend signextend1 (IFID_IC1, sign_extend_wire1);
SignExtend signedextend2 (IFID_IC2, sign_extend_wire2);

// IDEX stage for both instructions
IDEX IDEX1 (
    CLOCK, CONTROL_aluop_wire1, CONTROL_alusrc_wire1, CONTROL_isZeroBranch_wire1, CONTROL_isUnconBranch_wire1, CONTROL_memRead_wire1, CONTROL_memwrite_wire1, 
    CONTROL_regwrite_wire1, CONTROL_mem2reg_wire1, IFID_PC1, reg1_data1, reg2_data1, sign_extend_wire1, IFID_IC1[31:21], IFID_IC1[4:0], IFID_IC1[9:5], reg2_wire1, 
    IDEX_aluop1, IDEX_alusrc1, IDEX_isZeroBranch1, IDEX_isUnconBranch1, IDEX_memRead1, IDEX_memwrite1, IDEX_regwrite1, IDEX_mem2reg1, IDEX_PC1, IDEX_reg1_data1, 
    IDEX_reg2_data1, IDEX_sign_extend1, IDEX_alu_control1, IDEX_write_reg1, IDEX_forward_reg1, IDEX_forward_reg2
);

IDEX IDEX2 (
    CLOCK, CONTROL_aluop_wire2, CONTROL_alusrc_wire2, CONTROL_isZeroBranch_wire2, CONTROL_isUnconBranch_wire2, CONTROL_memRead_wire2, CONTROL_memwrite_wire2, 
    CONTROL_regwrite_wire2, CONTROL_mem2reg_wire2, IFID_PC2, reg1_data2, reg2_data2, sign_extend_wire2, IFID_IC2[31:21], IFID_IC2[4:0], IFID_IC2[9:5], reg2_wire2, 
    IDEX_aluop2, IDEX_alusrc2, IDEX_isZeroBranch2, IDEX_isUnconBranch2, IDEX_memRead2, IDEX_memwrite2, IDEX_regwrite2, IDEX_mem2reg2, IDEX_PC2, IDEX_reg1_data2, 
    IDEX_reg2_data2, IDEX_sign_extend2, IDEX_alu_control2, IDEX_write_reg2, IDEX_forward_reg1, IDEX_forward_reg2
);

	/* Stage : Execute for Instruction 1 and Instruction 2 */

/* Instruction 1 */
  wire [63:0] shift_left_wire1;
  wire [63:0] PC_jump1;
  wire jump_is_zero1;
  Shift_Left shift__left1 (IDEX_sign_extend1, shift_left_wire1);
  ALU ALU1 (IDEX_PC1, shift_left_wire1, 4'b0010, PC_jump1, jump_is_zero1);

  wire [4:0] EXMEM_write_reg1;
  wire EXMEM_regwrite1;
  wire EXMEM_mem2reg1;
  wire [1:0] Forward_A1;
  wire [1:0] Forward_B1;
  ForwardingUnit ForwardingUnit1 (IDEX_forward_reg1_1, IDEX_forward_reg2_1, EXMEM_write_reg1, MEMWB_write_reg1, EXMEM_regwrite1, MEMWB_regwrite1, Forward_A1, Forward_B1);

  wire [63:0] alu_1_wire1;
  Forward_ALU_Mux Forward_ALU_Mux11 (IDEX_reg1_data1, write_reg_data1, mem_address_out1, Forward_A1, alu_1_wire1);

  wire [63:0] alu_2_wire1;
  Forward_ALU_Mux Forward_ALU_Mux12 (IDEX_reg2_data1, write_reg_data1, mem_address_out1, Forward_B1, alu_2_wire1);

  wire [3:0] alu_main_control_wire1;
  ALU_Control ALU_control1(IDEX_aluop1, IDEX_alu_control1, alu_main_control_wire1);

  wire [63:0] alu_data2_wire1;
  ALU_Mux ALU_Mux1(alu_2_wire1, IDEX_sign_extend1, IDEX_alusrc1, alu_data2_wire1);

  wire alu_main_is_zero1;
  wire [63:0] alu_main_result1;
  ALU MAIN_ALU1(alu_1_wire1, alu_data2_wire1, alu_main_control_wire1, alu_main_result1, alu_main_is_zero1);

/* Instruction 2 */
  wire [63:0] shift_left_wire2;
  wire [63:0] PC_jump2;
  wire jump_is_zero2;
  Shift_Left Shift_Left2 (IDEX_sign_extend2, shift_left_wire2);
  ALU ALU2 (IDEX_PC2, shift_left_wire2, 4'b0010, PC_jump2, jump_is_zero2);

  wire [4:0] EXMEM_write_reg2;
  wire EXMEM_regwrite2;
  wire EXMEM_mem2reg2;
  wire [1:0] Forward_A2;
  wire [1:0] Forward_B2;
  ForwardingUnit ForwardingUnit2 (IDEX_forward_reg1_2, IDEX_forward_reg2_2, EXMEM_write_reg2, MEMWB_write_reg2, EXMEM_regwrite2, MEMWB_regwrite2, Forward_A2, Forward_B2);

  wire [63:0] alu_1_wire2;
  Forward_ALU_Mux Forward_ALU_Mux21 (IDEX_reg1_data2, write_reg_data2, mem_address_out2, Forward_A2, alu_1_wire2);

  wire [63:0] alu_2_wire2;
  Forward_ALU_Mux FOrward_ALU_Mux22 (IDEX_reg2_data2, write_reg_data2, mem_address_out2, Forward_B2, alu_2_wire2);

  wire [3:0] alu_main_control_wire2;
  ALU_Control ARM_control2(IDEX_aluop2, IDEX_alu_control2, alu_main_control_wire2);

  wire [63:0] alu_data2_wire2;
  ALU_Mux ALU_Mux2(alu_2_wire2, IDEX_sign_extend2, IDEX_alusrc2, alu_data2_wire2);

  wire alu_main_is_zero2;
  wire [63:0] alu_main_result2;
  ALU MAIN_ALU2(alu_1_wire2, alu_data2_wire2, alu_main_control_wire2, alu_main_result2, alu_main_is_zero2);

/* EXMEM for both Instructions */
  wire EXMEM_isZeroBranch1, EXMEM_isZeroBranch2;
  wire EXMEM_isUnconBranch1, EXMEM_isUnconBranch2;
  wire EXMEM_alu_zero1, EXMEM_alu_zero2;

  EXMEM EXMEM1(CLOCK, IDEX_isZeroBranch1, IDEX_isUnconBranch1, IDEX_memRead1, IDEX_memwrite1, IDEX_regwrite1, IDEX_mem2reg1, PC_jump1, alu_main_is_zero1, alu_main_result1, IDEX_reg2_data1, IDEX_write_reg1, EXMEM_isZeroBranch1, EXMEM_isUnconBranch1, control_memread_out1, control_memwrite_out1, EXMEM_regwrite1, EXMEM_mem2reg1, jump_PC_wire1, EXMEM_alu_zero1, mem_address_out1, mem_data_out1, EXMEM_write_reg1);

  EXMEM EXMEM2(CLOCK, IDEX_isZeroBranch2, IDEX_isUnconBranch2, IDEX_memRead2, IDEX_memwrite2, IDEX_regwrite2, IDEX_mem2reg2, PC_jump2, alu_main_is_zero2, alu_main_result2, IDEX_reg2_data2, IDEX_write_reg2, EXMEM_isZeroBranch2, EXMEM_isUnconBranch2, control_memread_out2, control_memwrite_out2, EXMEM_regwrite2, EXMEM_mem2reg2, jump_PC_wire2, EXMEM_alu_zero2, mem_address_out2, mem_data_out2, EXMEM_write_reg2);
 
	/* Stage : Memory for Instruction 1 and Instruction 2 */

/* Instruction 1 */
  Branch Branch1 (EXMEM_isUnconBranch1, EXMEM_isZeroBranch1, EXMEM_alu_zero1, PCSrc_wire1);

  wire [63:0] MEMWB_address1;
  wire [63:0] MEMWB_read_data1;
  MEMWB MEMWB1(CLOCK, mem_address_out1, mem_data_in1, EXMEM_write_reg1, EXMEM_regwrite1, EXMEM_mem2reg1, MEMWB_address1, MEMWB_read_data1, MEMWB_write_reg1, MEMWB_regwrite1, MEMWB_mem2reg1);

/* Instruction 2 */
  Branch Branch2 (EXMEM_isUnconBranch2, EXMEM_isZeroBranch2, EXMEM_alu_zero2, PCSrc_wire2);

  wire [63:0] MEMWB_address2;
  wire [63:0] MEMWB_read_data2;
  MEMWB MEMWB2(CLOCK, mem_address_out2, mem_data_in2, EXMEM_write_reg2, EXMEM_regwrite2, EXMEM_mem2reg2, MEMWB_address2, MEMWB_read_data2, MEMWB_write_reg2, MEMWB_regwrite2, MEMWB_mem2reg2);

	/* Stage : Writeback for Instruction 1 and Instruction 2 */

/* Instruction 1 */
  WB_Mux WB_Mux1 (MEMWB_address1, MEMWB_read_data1, MEMWB_mem2reg1, write_reg_data1);

/* Instruction 2 */
  WB_Mux WB_Mux2 (MEMWB_address2, MEMWB_read_data2, MEMWB_mem2reg2, write_reg_data2);


module ForwardingUnit
(
	input [4:0] EX_Rn_in,
	input [4:0] EX_Rm_in,
	input [4:0] MEM_Rd_in,
	input [4:0] WB_Rd_in,
	input MEM_regwrite_in,
	input WB_regwrite_in,
	output reg [1:0] A_out,
	output reg [1:0] B_out
);
  always @(*) begin
		if ((WB_regwrite_in == 1'b1) &&
				(WB_Rd_in !== 31) &&
			/*	(!((MEM_regwrite_in == 1'b1) && (MEM_Rd_in !== 31) && (MEM_Rd_in !== EX_Rn_in))) && */
				(WB_Rd_in === EX_Rn_in)) begin
			A_out <= 2'b01;
		end else if ((MEM_regwrite_in == 1'b1) &&
				(MEM_Rd_in !== 31) &&
				(MEM_Rd_in === EX_Rn_in)) begin
			A_out <= 2'b10;
		end else begin
			A_out <= 2'b00;
		end

		if ((WB_regwrite_in == 1'b1) &&
				(WB_Rd_in !== 31) &&
			/*	(!((MEM_regwrite_in == 1'b1) && (MEM_Rd_in !== 31) && (MEM_Rd_in !== EX_Rm_in))) && */
				(WB_Rd_in === EX_Rm_in)) begin
			B_out <= 2'b01;
		end else if ((MEM_regwrite_in == 1'b1) &&
				(MEM_Rd_in !== 31) &&
				(MEM_Rd_in === EX_Rm_in)) begin
			B_out <= 2'b10;
		end else begin
			B_out <= 2'b00;
		end
  end
endmodule


module HazardDetection
(
	input EX_memRead_in,
	input [4:0] EX_write_reg,
	input [63:0] ID_PC,
	input [31:0] ID_IC,
	output reg IFID_write_out,
	output reg PC_Write_out,
	output reg Control_mux_out
);
	always @(*) begin
		if (EX_memRead_in == 1'b1 && ((EX_write_reg === ID_IC[9:5]) || (EX_write_reg === ID_IC[20:16]))) begin
			IFID_write_out <= 1'b1;
			PC_Write_out <= 1'b1;
			Control_mux_out <= 1'b1;

		end else begin
			IFID_write_out <= 1'b0;
			PC_Write_out <= 1'b0;
			Control_mux_out <= 1'b0;
		end

	end
endmodule


module IFID
(
  input CLOCK,
  input [63:0] PC_in,
  input [31:0] IC_in,
  input Hazard_in,
  output reg [63:0] PC_out,
  output reg [31:0] IC_out
);
	always @(negedge CLOCK) begin
		if (Hazard_in !== 1'b1) begin
			PC_out <= PC_in;
			IC_out <= IC_in;
		end
  end
endmodule


module IDEX
(
  input CLOCK,
  input [1:0] aluop_in,
  input alusrc_in,
  input isZeroBranch_in,
  input isUnconBranch_in,
  input memRead_in,
  input memwrite_in,
  input regwrite_in,
  input mem2reg_in,
  input [63:0] PC_in,
  input [63:0] regdata1_in,
  input [63:0] regdata2_in,
  input [63:0] sign_extend_in,
  input [10:0] alu_control_in,
  input [4:0] write_reg_in,
  input [4:0] forward_reg_1_in,		// Forwarding
  input [4:0] forward_reg_2_in,		// Forwarding
  output reg [1:0] aluop_out,
  output reg alusrc_out,
  output reg isZeroBranch_out,
  output reg isUnconBranch_out,
  output reg memRead_out,
  output reg memwrite_out,
  output reg regwrite_out,
  output reg mem2reg_out,
  output reg [63:0] PC_out,
  output reg [63:0] regdata1_out,
  output reg [63:0] regdata2_out,
  output reg [63:0] sign_extend_out,
  output reg [10:0] alu_control_out,
  output reg [4:0] write_reg_out,
  output reg [4:0] forward_reg_1_out,		// Forwarding
  output reg [4:0] forward_reg_2_out		// Forwarding
);
  always @(negedge CLOCK) begin
    /* Values for EX */
    aluop_out <= aluop_in;
	  alusrc_out <= alusrc_in;

    /* Values for M */
  	isZeroBranch_out <= isZeroBranch_in;
    isUnconBranch_out <= isUnconBranch_in;
  	memRead_out <= memRead_in;
 	  memwrite_out <= memwrite_in;

    /* Values for WB */
    regwrite_out <= regwrite_in;
  	mem2reg_out <= mem2reg_in;

    /* Values for all Stages */
    PC_out <= PC_in;
    regdata1_out <= regdata1_in;
    regdata2_out <= regdata2_in;

    /* Values for variable stages */
    sign_extend_out <= sign_extend_in;
  	alu_control_out <= alu_control_in;
  	write_reg_out <= write_reg_in;
	  forward_reg_1_out <= forward_reg_1_in;
	  forward_reg_2_out <= forward_reg_2_in;
  end
endmodule


module EXMEM
(
  input CLOCK,
  input isZeroBranch_in, 	// M Stage
  input isUnconBranch_in, 	// M Stage
  input memRead_in, 		// M Stage
  input memwrite_in, 		// M Stage
  input regwrite_in, 		// WB Stage
  input mem2reg_in, 		// WB Stage
  input [63:0] shifted_PC_in,
  input alu_zero_in,
  input [63:0] alu_result_in,
  input [63:0] write_data_mem_in,
  input [4:0] write_reg_in,
  output reg isZeroBranch_out, 	// M Stage
  output reg isUnconBranch_out, // M Stage
  output reg memRead_out, 		// M Stage
  output reg memwrite_out, 		// M Stage
  output reg regwrite_out,		// WB Stage
  output reg mem2reg_out,		// WB Stage
  output reg [63:0] shifted_PC_out,
  output reg alu_zero_out,
  output reg [63:0] alu_result_out,
  output reg [63:0] write_data_mem_out,
  output reg [4:0] write_reg_out
);
	always @(negedge CLOCK) begin
		/* Values for M */
		isZeroBranch_out <= isZeroBranch_in;
		isUnconBranch_out <= isUnconBranch_in;
		memRead_out <= memRead_in;
		memwrite_out <= memwrite_in;

		/* Values for WB */
		regwrite_out <= regwrite_in;
		mem2reg_out <= mem2reg_in;

		/* Values for all Stages */
		shifted_PC_out <= shifted_PC_in;
		alu_zero_out <= alu_zero_in;
		alu_result_out <= alu_result_in;
		write_data_mem_out <= write_data_mem_in;
		write_reg_out <= write_reg_in;
	end
endmodule


module MEMWB
(
  input CLOCK,
  input [63:0] mem_address_in,
  input [63:0] mem_data_in,
  input [4:0] write_reg_in,
  input regwrite_in,
  input mem2reg_in,
  output reg [63:0] mem_address_out,
  output reg [63:0] mem_data_out,
  output reg [4:0] write_reg_out,
  output reg regwrite_out,
  output reg mem2reg_out
);
  always @(negedge CLOCK) begin
    regwrite_out <= regwrite_in;
    mem2reg_out <= mem2reg_in;
    mem_address_out <= mem_address_in;
    mem_data_out <= mem_data_in;
    write_reg_out <= write_reg_in;
  end
endmodule


module Registers
(
  input CLOCK,
  
  // 2 read and write register address inputs for each instruction
  input [4:0] read1_1, // instruction 1
  input [4:0] read2_1, // instruction 1
  input [4:0] read1_2, // instruction 2
  input [4:0] read2_2, // instruction 2
  
  input [4:0] writeReg1, // instruction 1
  input [4:0] writeReg2, // instruction 2

  // Write data for each instruction
  input [63:0] writeData1, // instruction 1
  input [63:0] writeData2, // instruction 2
  
  // Write enable signals for each instruction
  input CONTROL_REGWRITE1,
  input CONTROL_REGWRITE2,
  
  // Outputs for reading data for both instructions
  output reg [63:0] data1_1,
  output reg [63:0] data2_1,
  output reg [63:0] data1_2,
  output reg [63:0] data2_2
);
	reg [63:0] Data[127:0];
  integer initCount;

  // Initialize the register values
  initial begin
    for (initCount = 0; initCount < 31; initCount = initCount + 1) begin
      Data[initCount] = initCount;
    end
	  for (initCount = 32; initCount < 127; initCount = initCount + 1) begin
		  Data[initCount] = 0;
    end

    Data[31] = 64'h00000000; // x31 is the zero register
  end

  // Always block triggered on the clock edge
  always @(posedge CLOCK) begin
    // Write back for instruction 1
    if (CONTROL_REGWRITE1 == 1'b1) begin
      Data[writeReg1] = writeData1;
    end
    
    // Write back for instruction 2
    if (CONTROL_REGWRITE2 == 1'b1) begin
      Data[writeReg2] = writeData2;
    end
  end

  // Read register values for both instructions (combinational)
  always @(*) begin
    // Instruction 1
    data1_1 = Data[read1_1];
    data2_1 = Data[read2_1];
    
    // Instruction 2
    data1_2 = Data[read1_2];
    data2_2 = Data[read2_2];
  end

endmodule

module IC
(
  input [63:0] PC_in,                  // Program counter input
  output reg [31:0] instruction_out1,   // First instruction output
  output reg [31:0] instruction_out2    // Second instruction output
);

  reg [8:0] Data[63:0];

  initial begin
    // LDUR x0, [x2, #3]
    Data[0] = 8'hf8; Data[1] = 8'h40; Data[2] = 8'h30; Data[3] = 8'h40;

    // ADD x9, x0, x5
    Data[4] = 8'h8b; Data[5] = 8'h05; Data[6] = 8'h00; Data[7] = 8'h09;

    // ORR x10, x1, x9
    Data[8] = 8'haa; Data[9] = 8'h09; Data[10] = 8'h00; Data[11] = 8'h2a;

    // AND x11, x9, x0
    Data[12] = 8'h8a; Data[13] = 8'h00; Data[14] = 8'h01; Data[15] = 8'h2b;

    // SUB x12 x0 x11
    Data[16] = 8'hcb; Data[17] = 8'h0b; Data[18] = 8'h00; Data[19] = 8'h0c;

    // STUR x9, [x3, #6]
    Data[20] = 8'hf8; Data[21] = 8'h00; Data[22] = 8'h60; Data[23] = 8'h69;

    // STUR x10, [x4, #6]
    Data[24] = 8'hf8; Data[25] = 8'h00; Data[26] = 8'h60; Data[27] = 8'h8a;

    // STUR x11, [x5, #6]
    Data[28] = 8'hf8; Data[29] = 8'h00; Data[30] = 8'h60; Data[31] = 8'hab;

    // STUR x12, [x6, #6]
    Data[32] = 8'hf8; Data[33] = 8'h00; Data[34] = 8'h60; Data[35] = 8'hcc;

    // B #10
    Data[36] = 8'h14; Data[37] = 8'h00; Data[38] = 8'h00; Data[39] = 8'h0a;
  end

  always @(PC_in) begin
    // Fetch first instruction
    instruction_out1[7:0] = Data[PC_in];
    instruction_out1[15:8] = Data[PC_in + 1];
    instruction_out1[23:16] = Data[PC_in + 2];
    instruction_out1[31:24] = Data[PC_in + 3];

    // Fetch second instruction 
    instruction_out2[7:0] = Data[PC_in + 4];
    instruction_out2[15:8] = Data[PC_in + 5];
    instruction_out2[23:16] = Data[PC_in + 6];
    instruction_out2[31:24] = Data[PC_in + 7];
  end
endmodule

module Data_Memory
(
  input [63:0] inputAddress1,
  input [63:0] inputData1,
  input CONTROL_MemWrite1,
  input CONTROL_MemRead1,
  
  input [63:0] inputAddress2,
  input [63:0] inputData2,
  input CONTROL_MemWrite2,
  input CONTROL_MemRead2,

  output reg [63:0] outputData1,
  output reg [63:0] outputData2
);
  reg [63:0] Data[127:0];  
  integer initCount;

  initial begin
    for (initCount = 0; initCount < 128; initCount = initCount + 1) begin
      Data[initCount] = initCount * 5;
    end
  end

  always @(*) begin
    // Handle first memory access
    if (CONTROL_MemWrite1 == 1'b1) begin
      Data[inputAddress1] = inputData1;
    end else if (CONTROL_MemRead1 == 1'b1) begin
      outputData1 = Data[inputAddress1];
    end else begin
      outputData1 = 64'hxxxxxxxx;
    end

    // Handle second memory access
    if (CONTROL_MemWrite2 == 1'b1) begin
      Data[inputAddress2] = inputData2;
    end else if (CONTROL_MemRead2 == 1'b1) begin
      outputData2 = Data[inputAddress2];
    end else begin
      outputData2 = 64'hxxxxxxxx;
    end

    // Debug use only
    for (initCount = 0; initCount < 128; initCount = initCount + 1) begin
      $display("RAM[%0d] = %0d", initCount, Data[initCount]);
    end
  end
endmodule


module ALU
(
  input [63:0] A,
  input [63:0] B,
  input [3:0] CONTROL,
  output reg [63:0] RESULT,
  output reg ZEROFLAG
);
  always @(*) begin
    case (CONTROL)
      4'b0000 : RESULT = A & B;
      4'b0001 : RESULT = A | B;
      4'b0010 : RESULT = A + B;
      4'b0110 : RESULT = A - B;
      4'b0111 : RESULT = B;
      4'b1100 : RESULT = ~(A | B);
      default : RESULT = 64'hxxxxxxxx;
    endcase

    if (RESULT == 0) begin
      ZEROFLAG = 1'b1;
    end else if (RESULT != 0) begin
      ZEROFLAG = 1'b0;
    end else begin
      ZEROFLAG = 1'bx;
    end
  end
endmodule


module ALU_Control
(
  input [1:0] ALU_Op,
  input [10:0] ALU_INSTRUCTION,
  output reg [3:0] ALU_Out
);
  always @(ALU_Op or ALU_INSTRUCTION) begin
    case (ALU_Op)
      2'b00 : ALU_Out <= 4'b0010;
      2'b01 : ALU_Out <= 4'b0111;
      2'b10 : begin

        case (ALU_INSTRUCTION)
          11'b10001011000 : ALU_Out <= 4'b0010; // ADD
          11'b11001011000 : ALU_Out <= 4'b0110; // SUB
          11'b10001010000 : ALU_Out <= 4'b0000; // AND
          11'b10101010000 : ALU_Out <= 4'b0001; // ORR
        endcase
      end
      default : ALU_Out = 4'bxxxx;
    endcase
  end
endmodule


module Control_Mux
(
  input [1:0] CONTROL_aluop_in,
  input CONTROL_alusrc_in,
  input CONTROL_isZeroBranch_in,
  input CONTROL_isUnconBranch_in,
  input CONTROL_memRead_in,
  input CONTROL_memwrite_in,
  input CONTROL_regwrite_in,
  input CONTROL_mem2reg_in,
  input mux_control_in,
  output reg [1:0] CONTROL_aluop_out,
  output reg CONTROL_alusrc_out,
  output reg CONTROL_isZeroBranch_out,
  output reg CONTROL_isUnconBranch_out,
  output reg CONTROL_memRead_out,
  output reg CONTROL_memwrite_out,
  output reg CONTROL_regwrite_out,
  output reg CONTROL_mem2reg_out
);
	always @(*) begin
		if (mux_control_in === 1'b1) begin
		  CONTROL_aluop_out <= 2'b00;
		  CONTROL_alusrc_out <= 1'b0;
		  CONTROL_isZeroBranch_out <= 1'b0;
		  CONTROL_isUnconBranch_out <= 1'b0;
		  CONTROL_memRead_out <= 1'b0;
		  CONTROL_memwrite_out <= 1'b0;
		  CONTROL_regwrite_out <= 1'b0;
		  CONTROL_mem2reg_out <= 1'b0;
		end else begin
		  CONTROL_aluop_out <= CONTROL_aluop_in;
		  CONTROL_alusrc_out <= CONTROL_alusrc_in;
		  CONTROL_isZeroBranch_out <= CONTROL_isZeroBranch_in;
		  CONTROL_isUnconBranch_out <= CONTROL_isUnconBranch_in;
		  CONTROL_memRead_out <= CONTROL_memRead_in;
		  CONTROL_memwrite_out <= CONTROL_memwrite_in;
		  CONTROL_regwrite_out <= CONTROL_regwrite_in;
		  CONTROL_mem2reg_out <= CONTROL_mem2reg_in;
		end
	end
endmodule


module Forward_ALU_Mux
(
  input [63:0] reg_ex_in,
  input [63:0] reg_wb_in,
  input [63:0] reg_mem_in,
  input [1:0] forward_control_in,
  output reg [63:0] reg_out
);
	always @(*) begin
		case (forward_control_in)
        2'b01 : reg_out <= reg_wb_in;
        2'b10 : reg_out <= reg_mem_in;
        default : reg_out <= reg_ex_in;
      endcase
	end
endmodule


module ALU_Mux
(
  input [63:0] input1,
  input [63:0] input2,
  input CONTROL_ALUSRC,
  output reg [63:0] out
);
  always @(input1, input2, CONTROL_ALUSRC, out) begin
    if (CONTROL_ALUSRC === 0) begin
      out <= input1;
    end

    else begin
      out <= input2;
    end
  end
endmodule


module ID_Mux
(
  input [4:0] read1_in,
  input [4:0] read2_in,
  input reg2loc_in,
  output reg [4:0] reg_out
);
  always @(read1_in, read2_in, reg2loc_in) begin
    case (reg2loc_in)
        1'b0 : begin
            reg_out <= read1_in;
        end
        1'b1 : begin
            reg_out <= read2_in;
        end
        default : begin
            reg_out <= 1'bx;
        end
    endcase
  end
endmodule


module WB_Mux
(
  input [63:0] input1,
  input [63:0] input2,
  input mem2reg_control,
  output reg [63:0] out
);
  always @(*) begin
    if (mem2reg_control == 0) begin
      out <= input1;
    end

    else begin
      out <= input2;
    end
  end
endmodule


module Shift_Left
(
  input [63:0] data_in,
  output reg [63:0] data_out
);
  always @(data_in) begin
    data_out <= data_in << 2;
  end
endmodule


module SignExtend
(
  input [31:0] inputInstruction,
  output reg [63:0] outImmediate
);
  always @(inputInstruction) begin
    if (inputInstruction[31:26] == 6'b000101) begin // B
        outImmediate[25:0] = inputInstruction[25:0];
        outImmediate[63:26] = {64{outImmediate[25]}};

    end else if (inputInstruction[31:24] == 8'b10110100) begin // CBZ
        outImmediate[19:0] = inputInstruction[23:5];
        outImmediate[63:20] = {64{outImmediate[19]}};

    end else begin // D Type, ignored if R type
        outImmediate[9:0] = inputInstruction[20:12];
        outImmediate[63:10] = {64{outImmediate[9]}};
    end
  end
endmodule


module Branch
(
  input unconditional_branch_in,
  input conditional_branch_in,
  input alu_main_is_zero,
  output reg PC_src_out
);

	reg conditional_branch_temp;

  always @(unconditional_branch_in, conditional_branch_in, alu_main_is_zero) begin
    conditional_branch_temp <= conditional_branch_in & alu_main_is_zero;
    PC_src_out <= unconditional_branch_in | conditional_branch_temp;
  end
endmodule


module ARM_Control
(
  input [10:0] instruction,
  output reg [1:0] control_aluop,
  output reg control_alusrc,
  output reg control_isZeroBranch,
  output reg control_isUnconBranch,
  output reg control_memRead,
  output reg control_memwrite,
  output reg control_regwrite,
  output reg control_mem2reg
);

  always @(instruction) begin
    if (instruction[10:5] == 6'b000101) begin // B
      control_mem2reg <= 1'bx;
      control_memRead <= 1'b0;
      control_memwrite <= 1'b0;
      control_alusrc <= 1'b0;
      control_aluop <= 2'b01;
      control_isZeroBranch <= 1'b0;
      control_isUnconBranch <= 1'b1;
      control_regwrite <= 1'b0;

    end else if (instruction[10:3] == 8'b10110100) begin // CBZ
      control_mem2reg <= 1'bx;
      control_memRead <= 1'b0;
      control_memwrite <= 1'b0;
      control_alusrc <= 1'b0;
      control_aluop <= 2'b01;
      control_isZeroBranch <= 1'b1;
      control_isUnconBranch <= 1'b0;
      control_regwrite <= 1'b0;

    end else begin // R-Type Instructions
      control_isZeroBranch <= 1'b0;
      control_isUnconBranch <= 1'b0;

      case (instruction[10:0])
        11'b11111000010 : begin // LDUR
          control_mem2reg <= 1'b1;
          control_memRead <= 1'b1;
          control_memwrite <= 1'b0;
          control_alusrc <= 1'b1;
          control_aluop <= 2'b00;
          control_regwrite <= 1'b1;
        end

        11'b11111000000 : begin // STUR
          control_mem2reg <= 1'bx;
          control_memRead <= 1'b0;
          control_memwrite <= 1'b1;
          control_alusrc <= 1'b1;
          control_aluop <= 2'b00;
          control_regwrite <= 1'b0;
        end

        11'b10001011000 : begin // ADD
          control_mem2reg <= 1'b0;
          control_memRead <= 1'b0;
          control_memwrite <= 1'b0;
          control_alusrc <= 1'b0;
          control_aluop <= 2'b10;
          control_regwrite <= 1'b1;
        end

        11'b11001011000 : begin // SUB
          control_mem2reg <= 1'b0;
          control_memRead <= 1'b0;
          control_memwrite <= 1'b0;
          control_alusrc <= 1'b0;
          control_aluop <= 2'b10;
          control_regwrite <= 1'b1;
        end

        11'b10001010000 : begin // AND
          control_mem2reg <= 1'b0;
          control_memRead <= 1'b0;
          control_memwrite <= 1'b0;
          control_alusrc <= 1'b0;
          control_aluop <= 2'b10;
          control_regwrite <= 1'b1;
        end

        11'b10101010000 : begin // ORR
          control_mem2reg <= 1'b0;
          control_memRead <= 1'b0;
          control_memwrite <= 1'b0;
          control_alusrc <= 1'b0;
          control_aluop <= 2'b10;
          control_regwrite <= 1'b1;
        end

        default : begin // NOP
          control_isZeroBranch <= 1'bx;
      	 control_isUnconBranch <= 1'bx;
          control_mem2reg <= 1'bx;
          control_memRead <= 1'bx;
          control_memwrite <= 1'bx;
          control_alusrc <= 1'bx;
          control_aluop <= 2'bxx;
          control_regwrite <= 1'bx;
        end
      endcase
    end
  
end
endmodule
