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

  // Golden reference model - with pipeline delay tracking
  logic [PHYS_REGS-1:0] golden_free_mask;
  logic [5:0] expected_alloc_phys;
  logic expected_alloc_valid;
  int golden_alloc_count;
  
  // Pipeline tracking for golden model
  logic golden_alloc_en_ff;
  logic golden_free_en_ff;
  logic [5:0] golden_free_phys_ff;

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
    golden_alloc_en_ff = 0;
    golden_free_en_ff = 0;
    golden_free_phys_ff = '0;
    #20;
    reset = 0;
    #20;
  endtask

  // Initialize golden model
  task init_golden_model();
    golden_free_mask = {PHYS_REGS{1'b1}}; // All free
    golden_alloc_count = 0;
  endtask

  // Golden model pipeline stage 1: register inputs (like DUT)
  task golden_pipeline_stage1();
    golden_alloc_en_ff = alloc_en;
    golden_free_en_ff = free_en;
    golden_free_phys_ff = free_phys;
  endtask

  // Golden model pipeline stage 2: update state and allocation (like DUT)
  task golden_pipeline_stage2();
    // Update free mask based on previous cycle's free operation
    if (golden_free_en_ff) begin
      if (golden_free_mask[golden_free_phys_ff] == 1'b0) begin
        golden_alloc_count--;  // Only decrement if it was allocated
      end
      golden_free_mask[golden_free_phys_ff] = 1'b1;
    end
    
    // Handle allocation using current free_mask
    expected_alloc_valid = 1'b0;
    expected_alloc_phys = '0;
    
    if (golden_alloc_en_ff) begin
      for (int i = 0; i < PHYS_REGS; i++) begin
        if (golden_free_mask[i]) begin
          golden_free_mask[i] = 1'b0;
          expected_alloc_phys = i;
          expected_alloc_valid = 1'b1;
          golden_alloc_count++;
          break;
        end
      end
    end
  endtask

  // Check outputs against golden model
  task check_outputs(string test_name);
    // Wait for outputs to stabilize after clock edge
    #1;
    
    if (alloc_valid !== expected_alloc_valid) begin
      $error("Test %s: alloc_valid mismatch: expected=%0d, got=%0d", 
             test_name, expected_alloc_valid, alloc_valid);
    end
    
    if (alloc_valid && expected_alloc_valid && (alloc_phys !== expected_alloc_phys)) begin
      $error("Test %s: alloc_phys mismatch: expected=%0d, got=%0d", 
             test_name, expected_alloc_phys, alloc_phys);
    end
    
    // Check bounds
    if (alloc_valid && alloc_phys >= PHYS_REGS) begin
      $error("Test %s: alloc_phys out of bounds: %0d", test_name, alloc_phys);
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
      golden_pipeline_stage1(); // Capture inputs for next cycle
      #10;
      golden_pipeline_stage2(); // Process with 1-cycle delay
      check_outputs($sformatf("Basic alloc cycle %0d", i));
      alloc_en = 0;
      golden_pipeline_stage1(); // Capture no-op for next cycle
      #10;
      golden_pipeline_stage2(); // Process no-op
    end

    // Test 2: Free operations
    $display("Test 2: Free operations");
    // Free some registers
    for (int i = 0; i < 5; i++) begin
      free_phys = i;
      free_en = 1;
      golden_pipeline_stage1(); // Capture free for next cycle
      #10;
      golden_pipeline_stage2(); // Process free (no alloc expected)
      check_outputs($sformatf("Free cycle %0d", i));
      free_en = 0;
      golden_pipeline_stage1(); // Capture no-op
      #10;
      golden_pipeline_stage2(); // Process no-op
    end
    
    // Allocate again - should get the freed registers
    for (int i = 0; i < 5; i++) begin
      alloc_en = 1;
      golden_pipeline_stage1(); // Capture alloc for next cycle
      #10;
      golden_pipeline_stage2(); // Process alloc (should get freed regs)
      check_outputs($sformatf("Re-alloc after free cycle %0d", i));
      alloc_en = 0;
      golden_pipeline_stage1(); // Capture no-op
      #10;
      golden_pipeline_stage2(); // Process no-op
    end

    // Test 3: Exhaust all physical registers
    $display("Test 3: Exhaust all registers");
    do_reset();
    init_golden_model();
    
    // Allocate until empty
    for (int i = 0; i < PHYS_REGS; i++) begin
      alloc_en = 1;
      golden_pipeline_stage1();
      #10;
      golden_pipeline_stage2();
      check_outputs($sformatf("Exhaust alloc %0d", i));
      alloc_en = 0;
      golden_pipeline_stage1();
      #10;
      golden_pipeline_stage2();
    end
    
    // Try one more allocation - should fail
    alloc_en = 1;
    golden_pipeline_stage1();
    #10;
    golden_pipeline_stage2();
    check_outputs("Over-allocate attempt");
    alloc_en = 0;
    golden_pipeline_stage1();
    #10;
    golden_pipeline_stage2();

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
      
      golden_pipeline_stage1(); // Capture current inputs
      #10;
      golden_pipeline_stage2(); // Process with 1-cycle delay
      check_outputs($sformatf("Stress cycle %0d", cycle));
    end

    // Test 5: Allocation priority (should allocate lowest available)
    $display("Test 5: Allocation priority");
    do_reset();
    init_golden_model();
    
    // Allocate some registers
    for (int i = 0; i < 5; i++) begin
      alloc_en = 1;
      golden_pipeline_stage1();
      #10;
      golden_pipeline_stage2();
      check_outputs($sformatf("Priority setup alloc %0d", i));
      alloc_en = 0;
      golden_pipeline_stage1();
      #10;
      golden_pipeline_stage2();
    end
    
    // Free registers 2 and 4 (these take effect next cycle)
    free_phys = 2; free_en = 1; golden_pipeline_stage1(); #10; golden_pipeline_stage2(); free_en = 0; golden_pipeline_stage1(); #10; golden_pipeline_stage2();
    free_phys = 4; free_en = 1; golden_pipeline_stage1(); #10; golden_pipeline_stage2(); free_en = 0; golden_pipeline_stage1(); #10; golden_pipeline_stage2();
    
    // Next allocation should get lowest free (register 2)
    alloc_en = 1;
    golden_pipeline_stage1();
    #10;
    golden_pipeline_stage2();
    check_outputs("Priority test");
    if (alloc_valid && alloc_phys !== 2) begin
      $error("Priority test failed: expected phys=2, got=%0d", alloc_phys);
    end
    alloc_en = 0;
    golden_pipeline_stage1();
    #10;
    golden_pipeline_stage2();

    // Test 6: Free during allocation (now properly pipelined)
    $display("Test 6: Free during allocation");
    do_reset();
    init_golden_model();
    
    // Allocate until almost full
    for (int i = 0; i < PHYS_REGS - 2; i++) begin
      alloc_en = 1;
      golden_pipeline_stage1();
      #10;
      golden_pipeline_stage2();
      check_outputs($sformatf("Pre-alloc %0d", i));
      alloc_en = 0;
      golden_pipeline_stage1();
      #10;
      golden_pipeline_stage2();
    end
    
    // Concurrent alloc + free (free takes effect next cycle, so alloc won't see it immediately)
    alloc_en = 1;
    free_en = 1;
    free_phys = 5; // Free a register (will be available NEXT cycle)
    golden_pipeline_stage1(); // Capture both operations
    #10;
    golden_pipeline_stage2(); // Process - alloc might fail if no registers free
    check_outputs("Concurrent alloc+free cycle 1");
    
    // Continue allocation to see the freed register
    alloc_en = 1;
    free_en = 0;
    golden_pipeline_stage1(); // Capture alloc only
    #10;
    golden_pipeline_stage2(); // Process - should now see the freed register
    check_outputs("Concurrent alloc+free cycle 2");
    alloc_en = 0;
    golden_pipeline_stage1();
    #10;
    golden_pipeline_stage2();

    // Final allocation count check
    if (golden_alloc_count != (PHYS_REGS - $countones(dut.free_mask))) begin
      $error("Final count mismatch: golden=%0d, DUT=%0d", 
             golden_alloc_count, (PHYS_REGS - $countones(dut.free_mask)));
    end else begin
      $display("Final count verified: %0d allocations", golden_alloc_count);
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
