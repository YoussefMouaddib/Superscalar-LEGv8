`timescale 1ns/1ps
import core_pkg::*;

module tb_free_list_simple;

  localparam int PHYS_REGS = core_pkg::PREGS;
  
  // Clock / reset
  logic clk;
  logic reset;

  // DUT I/O
  logic        alloc_en;
  logic [5:0]  alloc_phys;
  logic        alloc_valid;
  logic        free_en;
  logic [5:0]  free_phys;

  // Instantiate DUT
  free_list #(.PHYS_REGS(PHYS_REGS)) dut (.*);

  // Clock generator: 100 MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Main test sequence
  initial begin
    $display("=== Simple Free List Test ===");
    
    // Initialize
    reset = 1;
    alloc_en = 0;
    free_en = 0;
    free_phys = '0;
    #20;
    reset = 0;
    #5;

    $display("Cycle 1: alloc_en = 1");
    alloc_en = 1;
    #10; // Wait for clock edge + propagation
    $display("  Output: alloc_phys = %0d, alloc_valid = %0d", alloc_phys, alloc_valid);
    
    $display("Cycle 2: alloc_en = 1");
    alloc_en = 1; 
    #10;
    $display("  Output: alloc_phys = %0d, alloc_valid = %0d", alloc_phys, alloc_valid);
    
    $display("Cycle 3: free_en = 1, free_phys = 1");
    alloc_en = 0;
    free_en = 1;
    free_phys = 1;
    #10;
    $display("  Output: alloc_phys = %0d, alloc_valid = %0d", alloc_phys, alloc_valid);

    $display("Cycle 2: alloc_en = 1");
    alloc_en = 1; 
    #10;
    $display("  Output: alloc_phys = %0d, alloc_valid = %0d", alloc_phys, alloc_valid);
    
    
    $display("Cycle 4: alloc_en = 1, free_en = 1, free_phys = 0");
    alloc_en = 1;
    free_en = 1;
    free_phys = 1;
    #10;
    $display("  Output: alloc_phys = %0d, alloc_valid = %0d", alloc_phys, alloc_valid);
    
    $display("=== Test Complete ===");
    $finish;
  end

endmodule
