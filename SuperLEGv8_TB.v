`timescale 1ns / 1ps

module SuperLEGv8_TB;

  /* CPU Signals */
  reg RESET;
  reg CLOCK;
  
  /* Instruction Cache */
  wire [63:0] PC_wire1, PC_wire2;
  wire [31:0] IC_wire1, IC_Wire2;

  /* Data Memory */
  wire [63:0] mem_address1, mem_address2;
  wire [63:0] mem_data_in1, mem_data_in2;
  wire control_memwrite;
  wire control_memread;
  wire [63:0] mem_data_out1, mem_data_out2;

  /* Register File Signals for Instruction 1 */
  wire [4:0] read_reg1_1;         // First source register for instruction 1
  wire [4:0] read_reg2_1;         // Second source register for instruction 1
  wire [63:0] reg_data1_1;        // Data from first source register (instruction 1)
  wire [63:0] reg_data2_1;        // Data from second source register (instruction 1)
  wire [4:0] write_reg1_1;        // Destination register for instruction 1
  wire [63:0] write_data1_1;      // Data to write back (instruction 1)
  wire regwrite1_1;                // Write enable signal for instruction 1

  /* Register File Signals for Instruction 2 */
  wire [4:0] read_reg1_2;         // First source register for instruction 2
  wire [4:0] read_reg2_2;         // Second source register for instruction 2
  wire [63:0] reg_data1_2;        // Data from first source register (instruction 2)
  wire [63:0] reg_data2_2;        // Data from second source register (instruction 2)
  wire [4:0] write_reg1_2;        // Destination register for instruction 2
  wire [63:0] write_data1_2;      // Data to write back (instruction 2)
  wire regwrite1_2;                // Write enable signal for instruction 2

  /* Instantiate the ARM CPU */
  ARM_CPU core (
    .RESET(RESET),
    .CLOCK(CLOCK),

    // Instruction inputs
    .IC1(IC_wire1),    // First instruction
    .IC2(IC_wire2),    // Second instruction 

    // Data memory inputs
    .mem_data_in1(mem_data_out1), // Data for first instruction
    .mem_data_in2(mem_data_out2), // Data for second instruction

    // Program counter outputs
    .PC1(PC_wire1), // PC output for the first instruction
    .PC2(PC_wire2),

    // Register file interface for instruction 1
    .read_reg1_1(read_reg1_1),
    .read_reg2_1(read_reg2_1),
    .reg_data1_1(reg_data1_1),
    .reg_data2_1(reg_data2_1),
    .write_reg1_1(write_reg1_1),
    .write_data1_1(write_data1_1),
    .regwrite1_1(regwrite1_1),

    // Register file interface for instruction 2
    .read_reg1_2(read_reg1_2),
    .read_reg2_2(read_reg2_2),
    .reg_data1_2(reg_data1_2),
    .reg_data2_2(reg_data2_2),
    .write_reg1_2(write_reg1_2),
    .write_data1_2(write_data1_2),
    .regwrite1_2(regwrite1_2),

    // Memory interface for both instruction streams
    .mem_address_out1(mem_address1),    // Update to your memory addressing if needed
    .mem_address_out2(mem_address2),    // Update to your memory addressing if needed
    .mem_data_out1(mem_data_in1),       // Data to write to memory for first instruction
    .mem_data_out2(mem_data_in2),       // Data to write to memory for second instruction
    .control_memwrite_out1(control_memwrite1), // Memory write control for first instruction
    .control_memwrite_out2(control_memwrite2), // Memory write control for second instruction
    .control_memread_out1(control_memread1),   // Memory read control for first instruction
    .control_memread_out2(control_memread2)    // Memory read control for second instruction
);
  /* Instantiate the Instruction Cache */
 IC Instruction_Cache (
  .address1(PC_wire1),
  .instruction_out1(IC_wire1),
  .instruction_out2(IC_wire2)
);

  /* Instantiate the Data Memory */
  Data_Memory RAM (
    .inputAddress1(mem_address1),
    .inputData1(mem_data_in1),
    .CONTROL_MemWrite1(control_memwrite1),
    .CONTROL_MemRead1(control_memread1),
  
    .inputAddress2(mem_address2),
    .inputData2(mem_data_in2),
    .CONTROL_MemWrite2(control_memwrite2),
    .CONTROL_MemRead2(control_memread2),

    .outputData1(mem_data_out1),
    .outputData2(mem_data_out2)
                  );

  /* Instantiate the Register File */
  Registers Register_file (CLOCK, 
      read_reg1_1, 
      read_reg2_1, 
      read_reg1_2, 
      read_reg2_2, 
      write_reg1_1, 
      write_reg1_2, 
      write_data1_1, 
      write_data1_2, 
      regwrite1_1,
      regwrite1_2, 
      reg_data1_1, 
      reg_data2_1,
      reg_data1_2, 
      reg_data2_2);

  /* Setup the clock */
  initial begin
    CLOCK = 1'b0;
    RESET = 1'b1;
    #30 $finish;
  end
  
  /* Toggle the clock */
  always begin
    #1 CLOCK = ~CLOCK; RESET = 1'b0;
  end
  
endmodule

