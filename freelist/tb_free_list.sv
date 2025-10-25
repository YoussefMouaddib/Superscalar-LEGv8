`timescale 1ns/1ps
import core_pkg::*;

module tb_free_list_race_condition;

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

  // Golden model - matches DUT's combinational behavior
  task golden_update();
    // Declare as automatic to avoid static variable issues
    automatic logic [PHYS_REGS-1:0] updated_mask = golden_free_mask;
    
    // Apply free FIRST
    if (free_en) begin
      if (updated_mask[free_phys] == 1'b0) begin
        golden_alloc_count--;
      end
      updated_mask[free_phys] = 1'b1;
    end
    
    // Then allocation
    expected_alloc_valid = 1'b0;
    expected_alloc_phys = '0;
    
    if (alloc_en) begin
      for (int i = 0; i < PHYS_REGS; i++) begin
        if (updated_mask[i]) begin
          updated_mask[i] = 1'b0;
          expected_alloc_phys = i;
          expected_alloc_valid = 1'b1;
          golden_alloc_count++;
          break;
        end
      end
    end
    
    golden_free_mask = updated_mask;
  endtask

  // Check outputs against golden model
  task check_outputs(string test_context);
    #1; // Wait for outputs to stabilize
    
    if (alloc_valid !== expected_alloc_valid) begin
      $error("%s: alloc_valid mismatch: expected=%0d, got=%0d", 
             test_context, expected_alloc_valid, alloc_valid);
    end
    
    if (alloc_valid && expected_alloc_valid && (alloc_phys !== expected_alloc_phys)) begin
      $error("%s: alloc_phys mismatch: expected=%0d, got=%0d", 
             test_context, expected_alloc_phys, alloc_phys);
    end
  endtask

  // Main test sequence
  initial begin
    $display("\n=== Race Condition Test (100 cycles) ===");
    $display("PHYS_REGS = %0d", PHYS_REGS);
    do_reset();
    init_golden_model();

    for (int cycle = 0; cycle < 100; cycle++) begin
      // Declare as automatic to avoid static variable issues
      automatic int op_type = $urandom_range(0, 9);
      
      // Random operations with controlled probabilities
      case (op_type)
        0,1,2,3: begin // 40% - Allocation only
          alloc_en = 1;
          free_en = 0;
        end
        4,5,6: begin   // 30% - Free only  
          alloc_en = 0;
          free_en = 1;
          free_phys = $urandom_range(0, PHYS_REGS-1);
        end
        7: begin       // 10% - Both alloc and free (race condition test)
          alloc_en = 1;
          free_en = 1;
          free_phys = $urandom_range(0, PHYS_REGS-1);
        end
        default: begin // 20% - No operation
          alloc_en = 0;
          free_en = 0;
        end
      endcase
      
      // Update golden model and check
      golden_update();
      #10; // Wait for DUT
      check_outputs($sformatf("Cycle %0d", cycle));
      
      // Debug print for race conditions
      if (alloc_en && free_en) begin
        $display("Cycle %0d: RACE CONDITION - alloc_en=1, free_en=1, free_phys=%0d", 
                 cycle, free_phys);
        $display("  Golden: phys=%0d, valid=%0d | DUT: phys=%0d, valid=%0d",
                 expected_alloc_phys, expected_alloc_valid, alloc_phys, alloc_valid);
      end
    end

    // Final verification
    if (golden_alloc_count != (PHYS_REGS - $countones(dut.free_mask))) begin
      $error("Final count mismatch: golden=%0d, DUT=%0d", 
             golden_alloc_count, (PHYS_REGS - $countones(dut.free_mask)));
    end else begin
      $display("Final count verified: %0d allocations", golden_alloc_count);
    end

    $display("=== Race Condition Test Complete ===");
    $finish;
  end

endmodule
