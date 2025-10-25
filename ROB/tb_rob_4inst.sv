`timescale 1ns/1ps
import core_pkg::*;

module tb_rob_minimal;

  localparam int ROB_SIZE = core_pkg::ROB_ENTRIES;
  localparam int IDX_BITS = $clog2(ROB_SIZE);
  
  // Clock / reset
  logic clk;
  logic reset;

  // DUT I/O
  logic [ISSUE_WIDTH-1:0] alloc_en;
  logic [4:0]             alloc_arch_rd [ISSUE_WIDTH];
  preg_tag_t              alloc_phys_rd [ISSUE_WIDTH];
  logic                   alloc_ok;
  logic [IDX_BITS-1:0]    alloc_idx [ISSUE_WIDTH];

  logic                   mark_ready_en;
  logic [IDX_BITS-1:0]    mark_ready_idx;
  logic                   mark_ready_val;
  logic                   mark_exception;

  logic [ISSUE_WIDTH-1:0] commit_valid;
  logic [4:0]             commit_arch_rd [ISSUE_WIDTH];
  preg_tag_t              commit_phys_rd [ISSUE_WIDTH];
  logic [ISSUE_WIDTH-1:0] commit_exception;

  logic                   rob_full;
  logic                   rob_almost_full;
  logic                   flush_en;
  logic [IDX_BITS-1:0]    flush_ptr;

  // Store allocation indices for later use
  logic [IDX_BITS-1:0] rob_idx_inst1, rob_idx_inst2, rob_idx_inst3, rob_idx_inst4;

  // Instantiate DUT
  rob dut (.*);

  // Clock generator: 100 MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Main test sequence
  initial begin
    $display("=== Minimal ROB Test ===");
    
    // Initialize
    reset = 1;
    alloc_en = '0;
    mark_ready_en = 0;
    flush_en = 0;
    #20;
    reset = 0;
    #20;

    // Cycle 1: Issue first 2 instructions
    $display("\n--- Cycle 1: Issue Instructions 1-2 ---");
    alloc_en = 2'b11;
    alloc_arch_rd[0] = 5'd1;  // Instruction 1: writes to R1
    alloc_phys_rd[0] = 6'd10; // Uses PHYS 10
    alloc_arch_rd[1] = 5'd2;  // Instruction 2: writes to R2  
    alloc_phys_rd[1] = 6'd11; // Uses PHYS 11
    #10;
    // Store the ROB indices for later wakeup
    rob_idx_inst1 = alloc_idx[0];
    rob_idx_inst2 = alloc_idx[1];
    $display("  Instruction 1 -> ROB[%0d], Instruction 2 -> ROB[%0d]", 
             rob_idx_inst1, rob_idx_inst2);

    // Cycle 2: Issue next 2 instructions
    $display("\n--- Cycle 2: Issue Instructions 3-4 ---");
    alloc_en = 2'b11;
    alloc_arch_rd[0] = 5'd3;  // Instruction 3: writes to R3
    alloc_phys_rd[0] = 6'd12; // Uses PHYS 12
    alloc_arch_rd[1] = 5'd4;  // Instruction 4: writes to R4
    alloc_phys_rd[1] = 6'd13; // Uses PHYS 13
    #10;
    // Store the ROB indices for later wakeup
    rob_idx_inst3 = alloc_idx[0];
    rob_idx_inst4 = alloc_idx[1];
    $display("  Instruction 3 -> ROB[%0d], Instruction 4 -> ROB[%0d]",
             rob_idx_inst3, rob_idx_inst4);

    // Cycle 3: No new instructions, wait for execution
    $display("\n--- Cycle 3: Waiting for execution ---");
    alloc_en = 2'b00;
    #10;

    // Cycle 4: Instruction 1 completes execution
    $display("\n--- Cycle 4: Instruction 1 completes ---");
    mark_ready_en = 1;
    mark_ready_idx = rob_idx_inst1; // Use stored index
    mark_ready_val = 1;
    mark_exception = 0;
    #10;
    $display("  Marked ROB entry %0d ready", mark_ready_idx);
    
    // Cycle 5: Instruction 2 completes
    $display("\n--- Cycle 5: Instruction 2 completes ---");
    mark_ready_idx = rob_idx_inst2; // Use stored index
    #10;
    $display("  Marked ROB entry %0d ready", mark_ready_idx);

    // Cycle 6: Instruction 3 completes execution
    $display("\n--- Cycle 6: Instruction 3 completes ---");
    mark_ready_idx = rob_idx_inst3; // Use stored index
    #10;
    $display("  Marked ROB entry %0d ready", mark_ready_idx);

    // Cycle 7: Instruction 4 completes
    $display("\n--- Cycle 7: Instruction 4 completes ---");
    mark_ready_idx = rob_idx_inst4; // Use stored index
    #10;
    $display("  Marked ROB entry %0d ready", mark_ready_idx);

    // Cycle 8: Check final state
    $display("\n--- Cycle 8: Final state ---");
    mark_ready_en = 0;
    #10;

    $display("\n=== Test Complete ===");
    $finish;
  end

  // Enhanced monitor to print ROB state every cycle
  always @(posedge clk) begin
    if (!reset) begin
      $display("\n=== Cycle Monitor ===");
      $display("Inputs: alloc_en=%b, mark_ready_en=%b, mark_ready_idx=%0d", 
               alloc_en, mark_ready_en, mark_ready_idx);
      $display("Outputs: alloc_ok=%b, rob_full=%b, rob_almost_full=%b",
               alloc_ok, rob_full, rob_almost_full);
      $display("Alloc Indices: [0]=%0d, [1]=%0d", alloc_idx[0], alloc_idx[1]);
      $display("Commits: valid=%b, arch_rd[0]=%0d->phys_rd[0]=%0d, arch_rd[1]=%0d->phys_rd[1]=%0d",
               commit_valid, commit_arch_rd[0], commit_phys_rd[0], 
               commit_arch_rd[1], commit_phys_rd[1]);
      
      // Print ROB memory contents
      $display("ROB Memory (head=%0d, tail=%0d):", dut.head, dut.tail);
      for (int i = 0; i < 8; i++) begin // Show first 8 entries
        if (dut.rob_mem[i].valid) begin
          $display("  [%0d]: valid=%b, ready=%b, arch_rd=%0d, phys_rd=%0d, exception=%b",
                   i, dut.rob_mem[i].valid, dut.rob_mem[i].ready,
                   dut.rob_mem[i].arch_rd, dut.rob_mem[i].phys_rd, 
                   dut.rob_mem[i].exception);
        end
      end
    end
  end

endmodule
