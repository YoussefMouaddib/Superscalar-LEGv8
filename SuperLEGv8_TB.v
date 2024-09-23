`timescale 1ns / 1ps

module SuperLEGv8_TB;

  /* CPU Signals */
  reg RESET;
  reg CLOCK;
  
  /* Instruction Memory */
  wire [63:0] PC_wire;
  wire [31:0] IC_wire;

  /* Data Memory */
  wire [63:0] mem_address;
  wire [63:0] mem_data_in;
  wire control_memwrite;
  wire control_memread;
  wire [63:0] mem_data_out;

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
  ARM_CPU core (RESET, CLOCK, IC_wire, mem_data_out, PC_wire, mem_address, mem_data_in, control_memwrite, control_memread,
                 read_reg1_1, read_reg2_1, reg_data1_1, reg_data2_1, write_reg1_1, write_data1_1, regwrite1_1,
                 read_reg1_2, read_reg2_2, reg_data1_2, reg_data2_2, write_reg1_2, write_data1_2, regwrite1_2);
  
  /* Instantiate the Instruction Cache */
  IC Instruction_Cache (PC_wire, IC_wire);
  
  /* Instantiate the Data Memory */
  Data_Memory RAM (mem_address, mem_data_in, control_memwrite, control_memread, mem_data_out);

  /* Instantiate the Register File */
  Registers reg_file (CLOCK, read_reg1_1, read_reg2_1, read_reg1_2, read_reg2_2, write_reg1_1, write_reg1_2, write_data1_1, write_data1_2, regwrite1_1, regwrite1_2, reg_data1_1, reg_data2_1, reg_data1_2, reg_data2_2);

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

