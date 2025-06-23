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
  output reg [63:0] PC1,   // PC for first instruction stream
  output reg [63:0] PC2, // PC for 2nd instruction stream

  // Register File Interface (For both instructions)
  // Read registers for instruction 1
  output [4:0] read_reg1_1,   // First source register for first instruction
  output [4:0] read_reg2_1,   // Second source register for first instruction
  input  [63:0] reg_data1_1,  // Data from first source register (first instruction)
  input  [63:0] reg_data2_1,  // Data from second source register (first instruction)
  // Write-back to register file for instruction
  output [4:0] write_reg1_1,   // Destination register for first instruction
  output [63:0] write_data_1, // Data to write back (first instruction)
  output regwrite1_1,          // Write enable signal for first instruction

  // Read registers for instruction 2
  output [4:0] read_reg1_2,   // First source register for second instruction
  output [4:0] read_reg2_2,   // Second source register for second instruction
  input  [63:0] reg_data1_2,  // Data from first source register (second instruction)
  input  [63:0] reg_data2_2,  // Data from second source register (second instruction)
 // Write-back to register file for instruction 2
  output [4:0] write_reg1_2,   // Destination register for second instruction
  output [63:0] write_data_2, // Data to write back (second instruction)
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

wire PCSrc_wire1,PCSrc_wire2;
wire [31:0] IFID_IC1, IFID_IC2;
wire [63:0] IFID_PC1, IFID_PC2;
wire [63:0] IDEX_reg2_data1, IDEX_reg2_data2;
	wire [1:0] IDEX_aluop1, IDEX_aluop2;

wire [63:0] jump_PC_wire;

always @(posedge CLOCK) begin
    if (Hazard_PCWrite1 !== 1'b1) begin
        if (PC1 === 64'bx) begin
            PC1 <= 0;
	end else if (PCSrc_wire1 == 1'b1) begin
            PC1 <= jump_PC_wire;
        end else begin
            PC1 <= PC1 + 8;
        end
    end
    if (Hazard_PCWrite2 !== 1'b1) begin
        if (PC2 === 64'bx) begin
            PC2 <= 4; 
	end else if (PCSrc_wire2 == 1'b1) begin
            PC2 <= jump_PC_wire + 8;
        end else begin
            PC2 <= PC2 + 8;
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
SignExtend signextend2 (IFID_IC2, sign_extend_wire2);

// IDEX stage for both instructions
IDEX IDEX1 (
    CLOCK, CONTROL_aluop_wire1, CONTROL_alusrc_wire1, CONTROL_isZeroBranch_wire1, CONTROL_isUnconBranch_wire1, CONTROL_memRead_wire1, CONTROL_memwrite_wire1, 
    CONTROL_regwrite_wire1, CONTROL_mem2reg_wire1, IFID_PC1, reg1_data1, reg2_data1, sign_extend_wire1, IFID_IC1[31:21], IFID_IC1[4:0], IFID_IC1[9:5], reg2_wire1, 
    IDEX_aluop1, IDEX_alusrc1, IDEX_isZeroBranch1, IDEX_isUnconBranch1, IDEX_memRead1, IDEX_memwrite1, IDEX_regwrite1, IDEX_mem2reg1, IDEX_PC1, IDEX_reg1_data1, 
    IDEX_reg2_data1, IDEX_sign_extend1, IDEX_alu_control1, IDEX_write_reg1, IDEX_forward_reg1_1, IDEX_forward_reg2_1
);
	
IDEX IDEX2 (
    CLOCK, CONTROL_aluop_wire2, CONTROL_alusrc_wire2, CONTROL_isZeroBranch_wire2, CONTROL_isUnconBranch_wire2, CONTROL_memRead_wire2, CONTROL_memwrite_wire2, 
    CONTROL_regwrite_wire2, CONTROL_mem2reg_wire2, IFID_PC2, reg1_data2, reg2_data2, sign_extend_wire2, IFID_IC2[31:21], IFID_IC2[4:0], IFID_IC2[9:5], reg2_wire2, 
    IDEX_aluop2, IDEX_alusrc2, IDEX_isZeroBranch2, IDEX_isUnconBranch2, IDEX_memRead2, IDEX_memwrite2, IDEX_regwrite2, IDEX_mem2reg2, IDEX_PC2, IDEX_reg1_data2, 
    IDEX_reg2_data2, IDEX_sign_extend2, IDEX_alu_control2, IDEX_write_reg2, IDEX_forward_reg1_2, IDEX_forward_reg2_2
);

	/* Stage : Execute */
	
wire [63:0] write_reg_data1, write_reg_data2;
	
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

assign write_data_1 = write_reg_data1;
assign write_data_2 = write_reg_data2;

endmodule
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


module ARF (
  input CLOCK,
  input [4:0] writeAddr,
  input [63:0] writeData,
  input commitEn,
  output [63:0] regOut [31:0]
);
  reg [63:0] archRegs [31:0];
  integer i;

  initial begin
    for (i = 0; i < 31; i = i + 1) archRegs[i] = 0;
    archRegs[31] = 64'h0; // x31 is zero
  end

  always @(posedge CLOCK) begin
    if (commitEn && writeAddr != 31) begin
      archRegs[writeAddr] <= writeData;
    end
  end

  // Output as an array for readback/debug
  assign regOut = archRegs;
endmodule


module PRF (
  input CLOCK,
  input [5:0] writeAddr1,
  input [63:0] writeData1,
  input writeEn1,

  input [5:0] writeAddr2,
  input [63:0] writeData2,
  input writeEn2,

  output [63:0] physOut [63:0]
);
  reg [63:0] physRegs [63:0];
  integer i;

  initial begin
    for (i = 0; i < 64; i = i + 1) physRegs[i] = 0;
  end

  always @(posedge CLOCK) begin
    if (writeEn1) physRegs[writeAddr1] <= writeData1;
    if (writeEn2) physRegs[writeAddr2] <= writeData2;
  end

  // Output as an array for external reads
  assign physOut = physRegs;
endmodule


module RenameTable (
  input CLOCK,
  input [4:0] archRegIn,
  input [5:0] physRegIn,
  input mapEn,
  output [5:0] physRegOut

);
  reg [5:0] renameTable [31:0];
  integer i;

  initial begin
    for (i = 0; i < 32; i = i + 1) renameTable[i] = i; // 1-to-1 initially
  end

  always @(posedge CLOCK) begin
    if (mapEn) begin
      renameTable[archRegIn] <= physRegIn;
    end
  end

  assign physRegOut = renameTable[archRegIn];

endmodule



module ROB #(
  parameter DEPTH = 32
)(
  input CLOCK,
  input RESET,

  // New instruction enqueue
  input enq_valid,
  input [4:0] destArchReg,
  input [5:0] destPhysReg,
  output reg [4:0] rob_head,
  output reg [4:0] rob_tail,

  // Commit logic
  input commit_en,
  output reg commit_valid,
  output reg [4:0] commit_archReg,
  output reg [5:0] commit_physReg,

  // Mark instruction as complete
  input [4:0] writeback_idx,
  input mark_ready,

  output reg [DEPTH-1:0] readyFlags
);

  // ROB entry
  typedef struct packed {
    logic valid;
    logic ready;
    logic [4:0] archReg;
    logic [5:0] physReg;
  } ROBEntry;

  ROBEntry buffer [DEPTH-1:0];
  integer i;

  // Init
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) begin
      buffer[i].valid = 0;
      buffer[i].ready = 0;
      buffer[i].archReg = 0;
      buffer[i].physReg = 0;
    end
    rob_head = 0;
    rob_tail = 0;
  end

  // Enqueue new instruction
  always @(posedge CLOCK or posedge RESET) begin
    if (RESET) begin
      rob_head <= 0;
      rob_tail <= 0;
      for (i = 0; i < DEPTH; i = i + 1) begin
        buffer[i].valid <= 0;
        buffer[i].ready <= 0;
      end
    end else begin
      if (enq_valid) begin
        buffer[rob_tail].valid <= 1;
        buffer[rob_tail].ready <= 0;
        buffer[rob_tail].archReg <= destArchReg;
        buffer[rob_tail].physReg <= destPhysReg;
        rob_tail <= (rob_tail + 1) % DEPTH;
      end

      if (mark_ready) begin
        buffer[writeback_idx].ready <= 1;
      end

      if (commit_en && buffer[rob_head].valid && buffer[rob_head].ready) begin
        commit_valid <= 1;
        commit_archReg <= buffer[rob_head].archReg;
        commit_physReg <= buffer[rob_head].physReg;

        buffer[rob_head].valid <= 0;
        rob_head <= (rob_head + 1) % DEPTH;
      end else begin
        commit_valid <= 0;
      end

      for (i = 0; i < DEPTH; i = i + 1) begin
        readyFlags[i] <= buffer[i].ready;
      end
    end
  end
endmodule



module FreeList #(
  parameter PHYS_REGS = 64,
  parameter ISSUE_WIDTH = 2
)(
  input CLOCK,
  input RESET,

  // Allocation request per instruction
  input [ISSUE_WIDTH-1:0] alloc_req,
  output reg [5:0] alloc_physRegs [ISSUE_WIDTH-1:0],
  output reg [ISSUE_WIDTH-1:0] alloc_valid,

  // Freeing registers (from ROB commit)
  input [ISSUE_WIDTH-1:0] free_en,
  input [5:0] free_physRegs [ISSUE_WIDTH-1:0]
);

  reg free_bitmap [PHYS_REGS-1:0];
  integer i, j;

  // Initialize free list
  initial begin
    for (i = 0; i < PHYS_REGS; i = i + 1) begin
      free_bitmap[i] = 1;
    end
    // Assume first 32 are ARF-mapped and reserved
    for (i = 0; i < 32; i = i + 1) begin
      free_bitmap[i] = 0;
    end
  end

  // Allocation logic
  always @(posedge CLOCK or posedge RESET) begin
    if (RESET) begin
      for (i = 0; i < PHYS_REGS; i = i + 1) begin
        free_bitmap[i] <= (i >= 32) ? 1 : 0;
      end
    end else begin
      // Handle freeing first (e.g., commit stage)
      for (j = 0; j < ISSUE_WIDTH; j = j + 1) begin
        if (free_en[j]) begin
          free_bitmap[free_physRegs[j]] <= 1;
        end
      end

      // Allocate registers
      integer k = 0;
      for (j = 0; j < ISSUE_WIDTH; j = j + 1) begin
        alloc_valid[j] = 0;
        alloc_physRegs[j] = 6'b111111;
        for (k = 32; k < PHYS_REGS; k = k + 1) begin
          if (free_bitmap[k]) begin
            free_bitmap[k] <= 0;
            alloc_physRegs[j] <= k[5:0];
            alloc_valid[j] <= 1;
            disable inner_loop;
          end
        end
      end
    end
  end

endmodule
module IssueQueue #(
  parameter ISSUE_WIDTH = 2,
  parameter QUEUE_SIZE = 16
)(
  input CLOCK,
  input RESET,

  // Enqueue from decode/rename
  input [ISSUE_WIDTH-1:0] enq_valid,
  input [5:0] enq_src1 [ISSUE_WIDTH-1:0],
  input [5:0] enq_src2 [ISSUE_WIDTH-1:0],
  input [5:0] enq_dest [ISSUE_WIDTH-1:0],
  input [3:0] enq_opcode [ISSUE_WIDTH-1:0], // Simplified opcode for now

  // Wakeup from writeback
  input [5:0] wb_physReg [ISSUE_WIDTH-1:0],
  input [ISSUE_WIDTH-1:0] wb_valid,

  // Dispatch outputs
  output reg [5:0] issue_src1 [ISSUE_WIDTH-1:0],
  output reg [5:0] issue_src2 [ISSUE_WIDTH-1:0],
  output reg [5:0] issue_dest [ISSUE_WIDTH-1:0],
  output reg [3:0] issue_opcode [ISSUE_WIDTH-1:0],
  output reg [ISSUE_WIDTH-1:0] issue_valid
);

  typedef struct packed {
    logic valid;
    logic [5:0] src1;
    logic [5:0] src2;
    logic [5:0] dest;
    logic [3:0] opcode;
    logic src1_ready;
    logic src2_ready;
  } IQEntry;

  IQEntry iq [QUEUE_SIZE-1:0];
  integer i, j;

  // Reset logic
  always @(posedge CLOCK or posedge RESET) begin
    if (RESET) begin
      for (i = 0; i < QUEUE_SIZE; i = i + 1)
        iq[i].valid <= 0;
    end else begin
      // Wakeup logic
      for (i = 0; i < QUEUE_SIZE; i = i + 1) begin
        if (iq[i].valid) begin
          for (j = 0; j < ISSUE_WIDTH; j = j + 1) begin
            if (wb_valid[j]) begin
              if (iq[i].src1 == wb_physReg[j]) iq[i].src1_ready <= 1;
              if (iq[i].src2 == wb_physReg[j]) iq[i].src2_ready <= 1;
            end
          end
        end
      end

      // Enqueue logic
      for (j = 0; j < ISSUE_WIDTH; j = j + 1) begin
        if (enq_valid[j]) begin
          for (i = 0; i < QUEUE_SIZE; i = i + 1) begin
            if (!iq[i].valid) begin
              iq[i].valid <= 1;
              iq[i].src1 <= enq_src1[j];
              iq[i].src2 <= enq_src2[j];
              iq[i].dest <= enq_dest[j];
              iq[i].opcode <= enq_opcode[j];
              iq[i].src1_ready <= 0;
              iq[i].src2_ready <= 0;
              disable enqueue_loop;
            end
          end
        end
      end

      // Dispatch logic
      integer issued = 0;
      for (i = 0; i < QUEUE_SIZE && issued < ISSUE_WIDTH; i = i + 1) begin
        if (iq[i].valid && iq[i].src1_ready && iq[i].src2_ready) begin
          issue_valid[issued] <= 1;
          issue_src1[issued] <= iq[i].src1;
          issue_src2[issued] <= iq[i].src2;
          issue_dest[issued] <= iq[i].dest;
          issue_opcode[issued] <= iq[i].opcode;
          iq[i].valid <= 0;
          issued = issued + 1;
        end
      end

      // Clear unused outputs
      for (j = issued; j < ISSUE_WIDTH; j = j + 1) begin
        issue_valid[j] <= 0;
        issue_src1[j] <= 6'b0;
        issue_src2[j] <= 6'b0;
        issue_dest[j] <= 6'b0;
        issue_opcode[j] <= 4'b0;
      end
    end
  end
endmodule



module ExecutionUnitWrapper (
  input CLOCK,
  input RESET,

  // From Issue Queue
  input [3:0] issue_opcode [1:0],
  input [5:0] issue_src1 [1:0],
  input [5:0] issue_src2 [1:0],
  input [5:0] issue_dest [1:0],
  input issue_valid [1:0],

  // Operand values from PRF
  input [31:0] src1_val [1:0],
  input [31:0] src2_val [1:0],

  // Outputs to Writeback
  output reg [5:0] wb_dest [1:0],
  output reg [31:0] wb_val [1:0],
  output reg wb_valid [1:0]
);

  // ALUs
  wire [31:0] alu_result [1:0];
  wire alu_valid [1:0];

  ALU alu0 (
    .opcode(issue_opcode[0]),
    .src1(src1_val[0]),
    .src2(src2_val[0]),
    .result(alu_result[0]),
    .valid(alu_valid[0])
  );

  ALU alu1 (
    .opcode(issue_opcode[1]),
    .src1(src1_val[1]),
    .src2(src2_val[1]),
    .result(alu_result[1]),
    .valid(alu_valid[1])
  );

  always @(posedge CLOCK or posedge RESET) begin
    if (RESET) begin
      wb_valid[0] <= 0;
      wb_valid[1] <= 0;
      wb_val[0] <= 32'b0;
      wb_val[1] <= 32'b0;
      wb_dest[0] <= 6'b0;
      wb_dest[1] <= 6'b0;
    end else begin
      wb_valid[0] <= issue_valid[0] & alu_valid[0];
      wb_valid[1] <= issue_valid[1] & alu_valid[1];
      wb_val[0] <= alu_result[0];
      wb_val[1] <= alu_result[1];
      wb_dest[0] <= issue_dest[0];
      wb_dest[1] <= issue_dest[1];
    end
  end

endmodule



module ALU (
  input [3:0] opcode,
  input [31:0] src1,
  input [31:0] src2,
  output reg [31:0] result,
  output valid
);

  assign valid = 1'b1;

  always @(*) begin
    case (opcode)
      4'b0000: result = src1 + src2;   // ADD
      4'b0001: result = src1 - src2;   // SUB
      4'b0010: result = src1 & src2;   // AND
      4'b0011: result = src1 | src2;   // OR
      4'b0100: result = src1 ^ src2;   // XOR
      4'b0101: result = src1 << src2[4:0]; // SLL
      4'b0110: result = src1 >> src2[4:0]; // SRL
      4'b0111: result = $signed(src1) >>> src2[4:0]; // SRA
      default: result = 32'b0;
    endcase
  end
endmodule
   


module BypassNetwork (
  // Inputs from Execution Units (for WB stage)
  input [5:0] wb_dest [1:0],
  input [31:0] wb_val [1:0],
  input wb_valid [1:0],

  // Incoming source registers from Issue Queue
  input [5:0] issue_src1 [1:0],
  input [5:0] issue_src2 [1:0],

  // Original values from PRF
  input [31:0] prf_src1_val [1:0],
  input [31:0] prf_src2_val [1:0],

  // Output forwarded values to Execution Unit
  output reg [31:0] final_src1_val [1:0],
  output reg [31:0] final_src2_val [1:0]
);

  integer i;

  always @(*) begin
    for (i = 0; i < 2; i = i + 1) begin
      // Default: use PRF
      final_src1_val[i] = prf_src1_val[i];
      final_src2_val[i] = prf_src2_val[i];

      // Check src1 for forwarding
      if (wb_valid[0] && (issue_src1[i] == wb_dest[0]))
        final_src1_val[i] = wb_val[0];
      else if (wb_valid[1] && (issue_src1[i] == wb_dest[1]))
        final_src1_val[i] = wb_val[1];

      // Check src2 for forwarding
      if (wb_valid[0] && (issue_src2[i] == wb_dest[0]))
        final_src2_val[i] = wb_val[0];
      else if (wb_valid[1] && (issue_src2[i] == wb_dest[1]))
        final_src2_val[i] = wb_val[1];
    end
  end

endmodule
// Integration Hint: Wire final_srcX_val[i] into your ExecutionUnitWrapper instead of srcX_val[i] directly from PRF. This adds dynamic forwarding from in-flight instructions and reduces RAW stalls.

module CommonDataBus #(
  parameter ISSUE_WIDTH = 2
)(
  input CLOCK,
  input RESET,

  // Inputs from Execution Units
  input [ISSUE_WIDTH-1:0] exec_valid,
  input [5:0] exec_physDest [ISSUE_WIDTH-1:0],
  input [63:0] exec_result [ISSUE_WIDTH-1:0],

  // Outputs to ROB, PRF, IQ, etc.
  output reg cdb_broadcast_valid [ISSUE_WIDTH-1:0],
  output reg [5:0] cdb_physDest [ISSUE_WIDTH-1:0],
  output reg [63:0] cdb_result [ISSUE_WIDTH-1:0]
);

  integer i;
  always @(posedge CLOCK or posedge RESET) begin
    if (RESET) begin
      for (i = 0; i < ISSUE_WIDTH; i = i + 1) begin
        cdb_broadcast_valid[i] <= 0;
        cdb_physDest[i] <= 6'b0;
        cdb_result[i] <= 64'b0;
      end
    end else begin
      for (i = 0; i < ISSUE_WIDTH; i = i + 1) begin
        cdb_broadcast_valid[i] <= exec_valid[i];
        cdb_physDest[i] <= exec_physDest[i];
        cdb_result[i] <= exec_result[i];
      end
    end
  end
endmodule



module RegisterReadBypass #(
  parameter ISSUE_WIDTH = 2,
  parameter PHYS_REG_COUNT = 64
)(
  input CLOCK,
  input RESET,

  // Inputs from Issue Queue
  input [5:0] srcA_phys [ISSUE_WIDTH-1:0],
  input [5:0] srcB_phys [ISSUE_WIDTH-1:0],
  input [ISSUE_WIDTH-1:0] valid_issue,

  // Inputs from CDB for bypassing
  input [5:0] cdb_physDest [ISSUE_WIDTH-1:0],
  input [63:0] cdb_result [ISSUE_WIDTH-1:0],
  input [ISSUE_WIDTH-1:0] cdb_broadcast_valid,

  // Physical Register File (PRF)
  input [63:0] prf_read [PHYS_REG_COUNT-1:0],

  // Outputs to Execution Units
  output reg [63:0] srcA_val [ISSUE_WIDTH-1:0],
  output reg [63:0] srcB_val [ISSUE_WIDTH-1:0]
);

  integer i, j;
  always @(*) begin
    for (i = 0; i < ISSUE_WIDTH; i = i + 1) begin
      srcA_val[i] = prf_read[srcA_phys[i]];
      srcB_val[i] = prf_read[srcB_phys[i]];

      for (j = 0; j < ISSUE_WIDTH; j = j + 1) begin
        if (cdb_broadcast_valid[j]) begin
          if (srcA_phys[i] == cdb_physDest[j]) srcA_val[i] = cdb_result[j];
          if (srcB_phys[i] == cdb_physDest[j]) srcB_val[i] = cdb_result[j];
        end
      end
    end
  end
endmodule



module DecodeRename #(
  parameter ISSUE_WIDTH = 2,
  parameter ARCH_REG_COUNT = 32,
  parameter PHYS_REG_COUNT = 64
)(
  input CLOCK,
  input RESET,

  // From Fetch/Decode
  input [4:0] srcA_arch [ISSUE_WIDTH-1:0],
  input [4:0] srcB_arch [ISSUE_WIDTH-1:0],
  input [4:0] dest_arch [ISSUE_WIDTH-1:0],
  input [ISSUE_WIDTH-1:0] valid_decode,
  input [31:0] inst_pc [ISSUE_WIDTH-1:0],
  input [31:0] inst_opcode [ISSUE_WIDTH-1:0],

  // Free List interface
  input [5:0] free_phys_regs [ISSUE_WIDTH-1:0],
  input [ISSUE_WIDTH-1:0] free_valid,

  // Current Rename Table (RAT) - maps arch to phys
  input [5:0] rat_map [ARCH_REG_COUNT-1:0],

  // Outputs to Issue Queue
  output reg [5:0] renamed_srcA [ISSUE_WIDTH-1:0],
  output reg [5:0] renamed_srcB [ISSUE_WIDTH-1:0],
  output reg [5:0] renamed_dest [ISSUE_WIDTH-1:0],
  output reg [4:0] dest_arch_out [ISSUE_WIDTH-1:0],
  output reg [31:0] inst_pc_out [ISSUE_WIDTH-1:0],
  output reg [31:0] inst_opcode_out [ISSUE_WIDTH-1:0],
  output reg [ISSUE_WIDTH-1:0] valid_rename,

  // New RAT updates (to be committed if dispatch successful)
  output reg [4:0] rat_update_arch [ISSUE_WIDTH-1:0],
  output reg [5:0] rat_update_phys [ISSUE_WIDTH-1:0],
  output reg [ISSUE_WIDTH-1:0] rat_update_valid
);

  integer i;
  always @(*) begin
    for (i = 0; i < ISSUE_WIDTH; i = i + 1) begin
      if (valid_decode[i] && free_valid[i]) begin
        renamed_srcA[i] = rat_map[srcA_arch[i]];
        renamed_srcB[i] = rat_map[srcB_arch[i]];
        renamed_dest[i] = free_phys_regs[i];

        rat_update_arch[i] = dest_arch[i];
        rat_update_phys[i] = free_phys_regs[i];
        rat_update_valid[i] = 1'b1;

        inst_pc_out[i] = inst_pc[i];
        inst_opcode_out[i] = inst_opcode[i];
        dest_arch_out[i] = dest_arch[i];
        valid_rename[i] = 1'b1;
      end else begin
        renamed_srcA[i] = 6'b0;
        renamed_srcB[i] = 6'b0;
        renamed_dest[i] = 6'b0;
        rat_update_valid[i] = 1'b0;
        valid_rename[i] = 1'b0;
      end
    end
  end
endmodule



module BranchPredictor #(
  parameter BHT_SIZE = 64
)(
  input CLOCK,
  input RESET,

  // From Decode
  input [31:0] decode_pc,
  input is_branch,
  input decode_valid,

  // From Commit (for training)
  input commit_valid,
  input [31:0] commit_pc,
  input branch_taken_actual,
  input is_branch_commit,

  // Output to Fetch
  output reg predict_taken,
  output reg [31:0] target_pc_predicted,

  // Redirect on mispredict
  output reg mispredict,
  output reg [31:0] correct_target
);

  // Simple 1-bit BHT indexed by PC bits
  reg bht [BHT_SIZE-1:0];
  wire [$clog2(BHT_SIZE)-1:0] index_decode = decode_pc[$clog2(BHT_SIZE)+1:2];
  wire [$clog2(BHT_SIZE)-1:0] index_commit = commit_pc[$clog2(BHT_SIZE)+1:2];

  always @(*) begin
    predict_taken = is_branch && bht[index_decode];
    target_pc_predicted = predict_taken ? decode_target : decode_pc + 4; // replace with real target from decode if known
    mispredict = 0;
    correct_target = 0;
  end

  always @(posedge CLOCK) begin
    if (RESET) begin
      integer i;
      for (i = 0; i < BHT_SIZE; i = i + 1) begin
        bht[i] <= 0;
      end
    end else if (commit_valid && is_branch_commit) begin
      mispredict <= (predict_taken != branch_taken_actual);
      correct_target <= commit_pc + (branch_taken_actual ? 4 : 4); // update with actual target
      bht[index_commit] <= branch_taken_actual;
    end
  end
endmodule




module LoadStoreQueue #(
  parameter ISSUE_WIDTH = 2,
  parameter LSQ_SIZE    = 16,
  parameter ROB_SIZE    = 32,
  // LEGv8 Specifics (Implicit: 64-bit data paths)
  parameter PHYS_REG_COUNT = 64 // Used for tag widths
)(
  input CLOCK,
  input RESET,

  // Enqueue from Decode/Rename
  input                                 enq_valid     [ISSUE_WIDTH-1:0],
  input                                 enq_is_store  [ISSUE_WIDTH-1:0],
  input [5:0]                           enq_addr_src  [ISSUE_WIDTH-1:0], // PhysReg for Rn (Base Address)
  input [31:0]                          enq_addr_imm  [ISSUE_WIDTH-1:0], // Sign-extended offset
  input [5:0]                           enq_data_src  [ISSUE_WIDTH-1:0], // PhysReg for Rt (Store Data)
  input [5:0]                           enq_dest_phys [ISSUE_WIDTH-1:0], // PhysReg for Rt (Load Dest)
  input [$clog2(ROB_SIZE)-1:0]          enq_rob_idx   [ISSUE_WIDTH-1:0],
  input [1:0]                           enq_mem_size  [ISSUE_WIDTH-1:0], // 00:B, 01:H, 10:W(32b), 11:D(64b) - LEGv8 convention

  // Wakeup/Bypass from CDB
  input                                 cdb_broadcast_valid [ISSUE_WIDTH-1:0],
  input [5:0]                           cdb_physDest        [ISSUE_WIDTH-1:0],
  input [63:0]                          cdb_result          [ISSUE_WIDTH-1:0], // LEGv8 data width

  // Commit signal from ROB
  input                                 commit_valid,
  input [$clog2(ROB_SIZE)-1:0]          commit_rob_idx,
  input                                 commit_is_store,

  // Data Cache Interface
  output reg                            dcache_req_valid,
  output reg                            dcache_req_is_write,
  output reg [63:0]                     dcache_req_addr,     // LEGv8 address width
  output reg [63:0]                     dcache_req_data,     // LEGv8 data width
  output reg [1:0]                      dcache_req_size,     // Pass size to cache
  input                                 dcache_resp_valid,
  input [63:0]                          dcache_resp_data,    // LEGv8 data width
  input [$clog2(ROB_SIZE)-1:0]          dcache_resp_rob_idx,

  // Output to Wakeup/CDB (for completed loads)
  output reg                            load_complete_valid,
  output reg [5:0]                      load_complete_dest_phys,
  output reg [63:0]                     load_complete_data,    // LEGv8 data width
  output reg [$clog2(ROB_SIZE)-1:0]      load_complete_rob_idx,

  // Output Ready/Full Status
  output logic                          lsq_ready
);

  typedef struct packed {
    logic                         valid;
    logic                         is_store;
    logic                         addr_ready;
    logic                         data_ready;
    logic                         mem_issued;
    logic                         mem_completed;

    logic [5:0]                   addr_src_phys;
    logic [31:0]                  addr_imm;       // Assuming sign-extended by Rename
    logic [63:0]                  address;        // LEGv8 64-bit address
    logic [5:0]                   data_src_phys;
    logic [63:0]                  store_data;     // LEGv8 64-bit data
    logic [5:0]                   dest_phys;
    logic [$clog2(ROB_SIZE)-1:0]  rob_idx;
    logic [1:0]                   mem_size;       // Store access size
  } LSQEntry;

  LSQEntry lsq [LSQ_SIZE-1:0];
  logic [LSQ_SIZE-1:0] lsq_entry_valid;
  assign lsq_ready = (|lsq_entry_valid == LSQ_SIZE) ? 1'b0 : 1'b1;

  integer i, j, k;
  logic [$clog2(LSQ_SIZE)-1:0] free_idx;

  // (Reset Logic - unchanged)
  // ...
  always_ff @(posedge CLOCK or posedge RESET) begin
    if (RESET) begin
        // ... reset lsq entries ...
        for (i = 0; i < LSQ_SIZE; i = i + 1) begin
            lsq[i].valid <= 1'b0;
        end
        dcache_req_valid    <= 1'b0;
        load_complete_valid <= 1'b0;
    end else begin
        // Defaults
        dcache_req_valid    <= 1'b0;
        load_complete_valid <= 1'b0;

        // (Dequeue Logic - unchanged)
        // ...

        // (Enqueue Logic - ADD mem_size)
        free_idx = '0;
        // ... find free_idx ...
        for (k = 0; k < LSQ_SIZE; k = k + 1) begin
            if (!lsq[k].valid) begin free_idx = k; break; end
        end

        for (j = 0; j < ISSUE_WIDTH; j = j + 1) begin
            if (enq_valid[j] && lsq_ready) begin
                 // ... assign other fields ...
                 lsq[free_idx].valid         <= 1'b1;
                 lsq[free_idx].is_store      <= enq_is_store[j];
                 lsq[free_idx].addr_src_phys <= enq_addr_src[j];
                 lsq[free_idx].addr_imm      <= enq_addr_imm[j];
                 lsq[free_idx].data_src_phys <= enq_data_src[j];
                 lsq[free_idx].dest_phys     <= enq_dest_phys[j];
                 lsq[free_idx].rob_idx       <= enq_rob_idx[j];
                 lsq[free_idx].mem_size      <= enq_mem_size[j]; // *** Store mem size ***
                 // Readiness checks need careful thought regarding XZR phys reg tag
                 lsq[free_idx].addr_ready    <= (enq_addr_src[j] == /* Phys tag for XZR? */ 6'b0); // Placeholder check
                 lsq[free_idx].data_ready    <= (enq_data_src[j] == /* Phys tag for XZR? */ 6'b0 || !enq_is_store[j]); // Placeholder check
                 lsq[free_idx].mem_issued    <= 1'b0;
                 lsq[free_idx].mem_completed <= 1'b0;
                 lsq[free_idx].address       <= 64'(enq_addr_imm[j]); // Initial address if no base reg
                // ... find next free_idx ...
                // ...
            end
        end

        // (Operand Wakeup/Address Calculation - unchanged logic, uses 64-bit)
        // ... address <= cdb_result[j] + $signed(lsq[i].addr_imm); ...

        // (Cache Response Handling - unchanged logic, uses 64-bit)
        // ...

        // (Memory Issue Logic - ADD mem_size to output)
        integer oldest_ready_idx = -1;
        logic oldest_is_store = 0;
        // ... find oldest_ready_idx based on readiness, commit status, forwarding ...

        if (oldest_ready_idx != -1) begin
           dcache_req_valid    <= 1'b1;
           dcache_req_is_write <= lsq[oldest_ready_idx].is_store;
           dcache_req_addr     <= lsq[oldest_ready_idx].address;
           dcache_req_size     <= lsq[oldest_ready_idx].mem_size; // *** Pass mem size ***
           if (lsq[oldest_ready_idx].is_store) begin
              dcache_req_data <= lsq[oldest_ready_idx].store_data;
           end else begin
              dcache_req_data <= 64'b0;
           end
           lsq[oldest_ready_idx].mem_issued <= 1'b1;
        end
        // Handle Store-to-Load forwarding completion (unchanged logic)
        // ...
    end // End non-reset clock edge
  end // End always_ff

  // (Update valid bits view - unchanged)
  // ...

endmodule



module ArchitecturalMapTable #(
  // LEGv8 Specifics
  parameter ARCH_REG_COUNT = 32, // X0-X30, XZR(31)
  parameter PHYS_REG_COUNT = 64  // Example Physical Register File size
)(
  input CLOCK,
  input RESET,

  // From Commit Stage (e.g., ROB)
  input                             commit_valid,           // An instruction is committing
  input [$clog2(ARCH_REG_COUNT)-1:0] commit_dest_arch,     // Architectural destination register index (0-31)
  input [$clog2(PHYS_REG_COUNT)-1:0] commit_dest_phys,     // Physical register holding the committed result
  input                             commit_has_dest,        // Does the committing instr write an arch reg?

  // Flush Signal
  input                             flush_valid,

  // Output: Current Committed Mapping
  output logic [$clog2(PHYS_REG_COUNT)-1:0] amt_map [ARCH_REG_COUNT-1:0]
);

  localparam PHYS_REG_BITS = $clog2(PHYS_REG_COUNT);
  localparam ZERO_REG_IDX  = ARCH_REG_COUNT - 1; // Index for XZR (31)

  // Internal register array storing the committed architectural-to-physical mappings
  reg [PHYS_REG_BITS-1:0] amt_map_reg [ARCH_REG_COUNT-1:0];

  integer i;

  always_ff @(posedge CLOCK or posedge RESET) begin
    if (RESET || flush_valid) begin
      // Initialize or restore the committed state
      for (i = 0; i < ARCH_REG_COUNT; i = i + 1) begin
        // Arch reg i maps to phys reg i initially
        amt_map_reg[i] <= PHYS_REG_BITS'(i);
      end
      // Ensure XZR maps to a specific physical register (e.g., phys reg 31 or 0)
      // Let's assume initial mapping maps X31 -> p31. Depends on PRF design.
      // If phys reg 0 is special, maybe map XZR there:
      // amt_map_reg[ZERO_REG_IDX] <= PHYS_REG_BITS'(0);
    end else if (commit_valid && commit_has_dest) begin
      // Update the mapping upon instruction commit
      // *** Crucially, DO NOT update the mapping for the Zero Register (XZR/X31) ***
      if (commit_dest_arch != ZERO_REG_IDX) begin
          amt_map_reg[commit_dest_arch] <= commit_dest_phys;
      end
    end
  end

  // Combinational assignment of the internal state to the output port
  assign amt_map = amt_map_reg;

endmodule























	      
























module IC (
  input [63:0] PC_in1,
  input [63:0] PC_in2,
  input clk, 
  output reg [31:0] instruction_out1,
  output reg [31:0] instruction_out2
);

  reg [7:0] Data[0:63];

  initial begin
    // LDUR x0, [x2, #3] 
    Data[0] = 8'hf8; Data[1] = 8'h40; Data[2] = 8'h30; Data[3] = 8'h40;

    // ADD x6, x4, x5 or 8b050086
    Data[4] = 8'h8b; Data[5] = 8'h05; Data[6] = 8'h00; Data[7] = 8'h86;

    // ORR x10, x1, x9 or  aa09002a
    Data[8] = 8'haa; Data[9] = 8'h09; Data[10] = 8'h00; Data[11] = 8'h2a;

    // AND x11, x9, x0 or 8a00012b
    Data[12] = 8'h8a; Data[13] = 8'h00; Data[14] = 8'h01; Data[15] = 8'h2b;

    // SUB x12 x0 x6 or cb06000c
    Data[16] = 8'hcb; Data[17] = 8'h06; Data[18] = 8'h00; Data[19] = 8'h0c;

    // STUR x9, [x3, #6] or f8006069
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

  always @(posedge clk) begin
  instruction_out1[7:0]    <= Data[PC_in1];
  instruction_out1[15:8]   <= Data[PC_in1 + 1];
  instruction_out1[23:16]  <= Data[PC_in1 + 2];
  instruction_out1[31:24]  <= Data[PC_in1 + 3];

  instruction_out2[7:0]    <= Data[PC_in2];
  instruction_out2[15:8]   <= Data[PC_in2 + 1];
  instruction_out2[23:16]  <= Data[PC_in2 + 2];
  instruction_out2[31:24]  <= Data[PC_in2 + 3];
end

endmodule


module Data_Memory (
  input clk,
  input [6:0] inputAddress1,  // 7 bits for 128 entries
  input [63:0] inputData1,
  input CONTROL_MemWrite1,
  input CONTROL_MemRead1,

  input [6:0] inputAddress2,
  input [63:0] inputData2,
  input CONTROL_MemWrite2,
  input CONTROL_MemRead2,

  output reg [63:0] outputData1,
  output reg [63:0] outputData2
);
  reg [63:0] Data[0:127];
  integer i;

  initial begin
    for (i = 0; i < 128; i = i + 1)
      Data[i] = i * 5;
  end

  always @(posedge clk) begin
    // Handle port 1
    if (CONTROL_MemWrite1)
      Data[inputAddress1] <= inputData1;
    if (CONTROL_MemRead1)
      outputData1 <= Data[inputAddress1];
    else
      outputData1 <= 64'hxxxxxxxx;

    // Handle port 2
    if (CONTROL_MemWrite2)
      Data[inputAddress2] <= inputData2;
    if (CONTROL_MemRead2)
      outputData2 <= Data[inputAddress2];
    else
      outputData2 <= 64'hxxxxxxxx;
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


module ARM_Control (
  input [31:0] instruction,  // Expanded to 32-bit to handle all instruction formats
  output reg [1:0] control_aluop,
  output reg control_alusrc,
  output reg control_isZeroBranch,
  output reg control_isUnconBranch,
  output reg control_memRead,
  output reg control_memwrite,
  output reg control_regwrite,
  output reg control_mem2reg,
  output reg control_isSVC,      // New: For supervisor calls
  output reg control_isWFI       // New: For wait-for-interrupt
);

  // Extract opcode fields
  wire [10:0] opcode = instruction[31:21];  // Main opcode field
  wire [7:0] cb_opcode = instruction[31:24]; // CB format
  wire [5:0] b_opcode = instruction[31:26];  // B format
  wire [10:0] sys_opcode = instruction[31:21]; // System instructions

  always @(*) begin
    // Default control signals
    control_mem2reg = 1'bx;
    control_memRead = 1'b0;
    control_memwrite = 1'b0;
    control_alusrc = 1'b0;
    control_aluop = 2'b00;
    control_isZeroBranch = 1'b0;
    control_isUnconBranch = 1'b0;
    control_regwrite = 1'b0;
    control_isSVC = 1'b0;
    control_isWFI = 1'b0;

    // Instruction Decoding
    casez (opcode)
      // Data Processing - Register
      11'b10001011000 : begin // ADD
        control_aluop = 2'b10;
        control_regwrite = 1'b1;
      end
      
      11'b11001011000 : begin // SUB
        control_aluop = 2'b10;
        control_regwrite = 1'b1;
      end
      
      11'b10001010000 : begin // AND
        control_aluop = 2'b11;
        control_regwrite = 1'b1;
      end
      
      11'b10101010000 : begin // ORR
        control_aluop = 2'b11;
        control_regwrite = 1'b1;
      end
      
      11'b11001010000 : begin // EOR
        control_aluop = 2'b11;
        control_regwrite = 1'b1;
      end
      
      11'b11010011011 : begin // LSL
        control_aluop = 2'b11;
        control_regwrite = 1'b1;
      end
      
      11'b11010011010 : begin // LSR
        control_aluop = 2'b11;
        control_regwrite = 1'b1;
      end

      // Load/Store Instructions
      11'b11111000010 : begin // LDUR
        control_mem2reg = 1'b1;
        control_memRead = 1'b1;
        control_alusrc = 1'b1;
        control_regwrite = 1'b1;
      end
      
      11'b11111000000 : begin // STUR
        control_memwrite = 1'b1;
        control_alusrc = 1'b1;
      end
      
      11'b11111000011 : begin // LDURH
        control_mem2reg = 1'b1;
        control_memRead = 1'b1;
        control_alusrc = 1'b1;
        control_regwrite = 1'b1;
      end
      
      11'b11111000100 : begin // STURH
        control_memwrite = 1'b1;
        control_alusrc = 1'b1;
      end
      
      11'b11111000001 : begin // LDURB
        control_mem2reg = 1'b1;
        control_memRead = 1'b1;
        control_alusrc = 1'b1;
        control_regwrite = 1'b1;
      end
      
      11'b11111000001 : begin // STURB
        control_memwrite = 1'b1;
        control_alusrc = 1'b1;
      end

      // Branch Instructions
      11'b000101????? : begin // B
        control_isUnconBranch = 1'b1;
      end
      
      11'b100101????? : begin // BL
        control_isUnconBranch = 1'b1;
        control_regwrite = 1'b1;  // Write to LR
      end
      
      11'b10110100??? : begin // CBZ
        control_isZeroBranch = 1'b1;
      end
      
      11'b10110101??? : begin // CBNZ
        control_isZeroBranch = 1'b1;
      end
      
      11'b11010110010 : begin // RET (Special form of BR)
        control_isUnconBranch = 1'b1;
      end

      // System Instructions
      11'b11010100000 : begin // SVC
        control_isSVC = 1'b1;
      end
      
      11'b11010101011 : begin // WFI
        control_isWFI = 1'b1;
      end
      
      11'b00000000000 : begin // NOP
        // All controls remain default
      end

      default: begin
        // Undefined instruction - could add trap handling here
        control_aluop = 2'bxx;
        control_alusrc = 1'bx;
        control_regwrite = 1'bx;
      end
    endcase
  end
endmodule
