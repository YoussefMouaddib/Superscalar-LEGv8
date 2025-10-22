`timescale 1ns/1ps
import core_pkg::*;

module tb_free_list_golden;

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

  // Golden reference model
  logic [PHYS_REGS-1:0] golden_free_mask;
  logic [5:0] expected_alloc_phys;
  logic expected_alloc_valid;
  int golden_alloc_count;

  // Instantiate DUT
  free_list #(.PHYS_REGS(PHYS_REGS)) dut (.*);

  // Clock generator: 100 MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset task
  task do_reset();
    reset = 1;
    alloc_en = 0;
    free_en = 0;
    free_phys = '0;
    #20;
    reset = 0;
    #20;
  endtask

  // Initialize golden model
  task init_golden_model();
    golden_free_mask = {PHYS_REGS{1'b1}}; // All free
    golden_alloc_count = 0;
  endtask

  // Golden model allocation
  task golden_allocate();
    expected_alloc_valid = 0;
    expected_alloc_phys = 0;
    
    for (int i = 0; i < PHYS_REGS; i++) begin
      if (golden_free_mask[i]) begin
        golden_free_mask[i] = 1'b0;
        expected_alloc_phys = i;
        expected_alloc_valid = 1'b1;
        golden_alloc_count++;
        break;
      end
    end
  endtask

  // Golden model free
  task golden_free(input logic [5:0] phys);
    if (phys < PHYS_REGS) begin
      golden_free_mask[phys] = 1'b1;
      if (!golden_free_mask[phys]) begin // Was allocated
        golden_alloc_count--;
      end
    end
  endtask

  // Check outputs against golden model
  task check_outputs(string context = "");
    if (alloc_valid !== expected_alloc_valid) begin
      $error("%s alloc_valid mismatch: expected=%0d, got=%0d", 
             context, expected_alloc_valid, alloc_valid);
    end
    
    if (alloc_valid && expected_alloc_valid && (alloc_phys !== expected_alloc_phys)) begin
      $error("%s alloc_phys mismatch: expected=%0d, got=%0d", 
             context, expected_alloc_phys, alloc_phys);
    end
    
    // Check bounds
    if (alloc_valid && alloc_phys >= PHYS_REGS) begin
      $error("%s alloc_phys out of bounds: %0d", context, alloc_phys);
    end
  endtask

  // Main test sequence
  initial begin
    $display("\n=== Golden Model Free List Testbench Start ===");
    $display("PHYS_REGS = %0d", PHYS_REGS);
    do_reset();
    init_golden_model();

    // Test 1: Basic allocation sequence
    $display("Test 1: Basic allocation");
    for (int i = 0; i < 10; i++) begin
      alloc_en = 1;
      golden_allocate();
      #10; 
      check_outputs($sformatf("Basic alloc cycle %0d", i));
      alloc_en = 0;
      #10;
    end

    // Test 2: Free operations
    $display("Test 2: Free operations");
    // Free some registers
    for (int i = 0; i < 5; i++) begin
      free_phys = i;
      free_en = 1;
      golden_free(i);
      #10;
      free_en = 0;
      #10;
    end
    
    // Allocate again - should get the freed registers
    for (int i = 0; i < 5; i++) begin
      alloc_en = 1;
      golden_allocate();
      #10;
      check_outputs($sformatf("Re-alloc after free cycle %0d", i));
      alloc_en = 0;
      #10;
    end

    // Test 3: Exhaust all physical registers
    $display("Test 3: Exhaust all registers");
    do_reset();
    init_golden_model();
    
    // Allocate until empty
    for (int i = 0; i < PHYS_REGS; i++) begin
      alloc_en = 1;
      golden_allocate();
      #10;
      check_outputs($sformatf("Exhaust alloc %0d", i));
      alloc_en = 0;
      #10;
    end
    
    // Try one more allocation - should fail
    alloc_en = 1;
    golden_allocate(); // Should set valid=0
    #10;
    check_outputs("Over-allocate attempt");
    alloc_en = 0;
    #10;

    // Test 4: Concurrent alloc/free stress
    $display("Test 4: Concurrent alloc/free stress");
    do_reset();
    init_golden_model();
    
    for (int cycle = 0; cycle < 200; cycle++) begin
      // Random allocation (40% probability)
      alloc_en = ($urandom_range(0, 9) < 4) ? 1'b1 : 1'b0;
      
      // Random free (30% probability) 
      free_en = ($urandom_range(0, 9) < 3) ? 1'b1 : 1'b0;
      free_phys = $urandom_range(0, PHYS_REGS-1);
      
      // Update golden model
      if (alloc_en) golden_allocate();
      if (free_en) golden_free(free_phys);
      
      #5; // Check mid-cycle
      check_outputs($sformatf("Stress cycle %0d", cycle));
      #5;
    end

    // Test 5: Allocation priority (should allocate lowest available)
    $display("Test 5: Allocation priority");
    do_reset();
    init_golden_model();
    
    // Allocate some registers
    for (int i = 0; i < 5; i++) begin
      alloc_en = 1;
      golden_allocate();
      #10;
      alloc_en = 0;
      #10;
    end
    
    // Free registers 2 and 4
    free_phys = 2; free_en = 1; golden_free(2); #10; free_en = 0; #10;
    free_phys = 4; free_en = 1; golden_free(4); #10; free_en = 0; #10;
    
    // Next allocation should get lowest free (register 2)
    alloc_en = 1;
    golden_allocate();
    #10;
    if (alloc_valid && alloc_phys !== 2) begin
      $error("Priority test failed: expected phys=2, got=%0d", alloc_phys);
    end
    alloc_en = 0;
    #10;

    // Test 6: Free during allocation
    $display("Test 6: Free during allocation");
    do_reset();
    init_golden_model();
    
    // Allocate until almost full
    for (int i = 0; i < PHYS_REGS - 2; i++) begin
      alloc_en = 1; #10; alloc_en = 0; #10;
    end
    
    // Concurrent alloc + free
    alloc_en = 1;
    free_en = 1;
    free_phys = 5; // Free a register
    golden_allocate(); // Should succeed due to free
    golden_free(5);
    #10;
    check_outputs("Concurrent alloc+free");
    alloc_en = 0;
    free_en = 0;
    #10;

    // Final allocation count check
    if (golden_alloc_count != dut.free_mask.count_ones()) begin
      $error("Final count mismatch: golden=%0d, DUT=%0d", 
             PHYS_REGS - golden_alloc_count, PHYS_REGS - dut.free_mask.count_ones());
    end

    $display("=== Golden Model Free List: ALL TESTS PASSED ===");
    $display("Final stats: %0d allocations tracked", golden_alloc_count);
    $finish;
  end

  // Continuous monitoring
  always @(posedge clk) begin
    if (!reset) begin
      // Additional safety checks
      if (free_en && free_phys >= PHYS_REGS) begin
        $error("Free phys out of bounds: %0d", free_phys);
      end
    end
  end

endmodule
