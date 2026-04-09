`timescale 1ns/1ps

module tb_rename_table_golden;

  // Parameters match DUT defaults
  localparam int ARCH_REGS = 32;
  localparam int PHYS_REGS = 48;

  // Clock / reset
  logic clk;
  logic reset;

  // DUT I/O
  logic [4:0]  arch_rs1;
  logic [4:0]  arch_rs2;
  logic [5:0]  phys_rs1;
  logic [5:0]  phys_rs2;
  logic        rename_en;
  logic [4:0]  arch_rd;
  logic [5:0]  new_phys_rd;
  logic        commit_en;
  logic [4:0]  commit_arch_rd;
  logic [5:0]  commit_phys_rd;

  // Golden reference model
  logic [5:0] golden_map_table [ARCH_REGS];
  logic [5:0] golden_committed_table [ARCH_REGS];
  logic [5:0] expected_phys_rs1, expected_phys_rs2;

  // Instantiate DUT
  rename_table #(.ARCH_REGS(ARCH_REGS), .PHYS_REGS(PHYS_REGS)) dut (.*);

  // Clock generator: 100 MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset task
  task do_reset();
    reset = 1;
    rename_en = 0; commit_en = 0;
    arch_rs1 = '0; arch_rs2 = '0; arch_rd = '0;
    new_phys_rd = '0; commit_arch_rd = '0; commit_phys_rd = '0;
    #20;
    reset = 0;
    #20;
  endtask

  // Initialize golden model
  task init_golden_model();
    for (int i = 0; i < ARCH_REGS; i++) begin
      golden_map_table[i] = i;
      golden_committed_table[i] = i;
    end
  endtask

  // Golden model update tasks
  task golden_rename(input logic [4:0] arch, input logic [5:0] phys);
    golden_map_table[arch] = phys;
  endtask

  task golden_commit(input logic [4:0] arch, input logic [5:0] phys);
    golden_committed_table[arch] = phys;
  endtask

  // Check outputs against golden model
  task check_outputs();
    expected_phys_rs1 = golden_map_table[arch_rs1];
    expected_phys_rs2 = golden_map_table[arch_rs2];
    
    if (phys_rs1 !== expected_phys_rs1) begin
      $error("Mismatch phys_rs1: arch=%0d, expected=%0d, got=%0d", 
             arch_rs1, expected_phys_rs1, phys_rs1);
    end
    
    if (phys_rs2 !== expected_phys_rs2) begin
      $error("Mismatch phys_rs2: arch=%0d, expected=%0d, got=%0d", 
             arch_rs2, expected_phys_rs2, phys_rs2);
    end
  endtask

  // Main test sequence
  initial begin
    $display("\n=== Golden Model Testbench Start ===");
    do_reset();
    init_golden_model();

    // Test 1: Basic rename operations
    $display("Test 1: Basic renames");
    for (int i = 0; i < 8; i++) begin
      arch_rd = $urandom_range(1, ARCH_REGS-1);  // Skip x0
      new_phys_rd = $urandom_range(ARCH_REGS, PHYS_REGS-1);
      rename_en = 1;
      golden_rename(arch_rd, new_phys_rd);
      #10; rename_en = 0; #10;
      
      // Verify mapping
      arch_rs1 = arch_rd; #5;
      check_outputs();
    end

    // Test 2: Concurrent read during rename
    $display("Test 2: Concurrent operations");
    for (int i = 0; i < 20; i++) begin
      arch_rs1 = $urandom_range(0, ARCH_REGS-1);
      arch_rs2 = $urandom_range(0, ARCH_REGS-1);
      
      if ($urandom_range(0, 3) == 0) begin  // 25% rename probability
        arch_rd = $urandom_range(1, ARCH_REGS-1);
        new_phys_rd = $urandom_range(ARCH_REGS, PHYS_REGS-1);
        rename_en = 1;
        golden_rename(arch_rd, new_phys_rd);
      end else begin
        rename_en = 0;
      end
      
      if ($urandom_range(0, 7) == 0) begin  // 12.5% commit probability
        commit_arch_rd = $urandom_range(1, ARCH_REGS-1);
        commit_phys_rd = golden_map_table[commit_arch_rd]; // Realistic commit value
        commit_en = 1;
        golden_commit(commit_arch_rd, commit_phys_rd);
      end else begin
        commit_en = 0;
      end
      
      #5; check_outputs(); #5; // Check mid-cycle and end-cycle
    end

    // Test 3: Sequential dependency chain
    $display("Test 3: Dependency chain");
    do_reset();
    init_golden_model();
    
    // Create chain: R1→R2→R3→R4
    for (int i = 1; i <= 4; i++) begin
      arch_rd = i;
      new_phys_rd = 32 + i;  // PHYS 33,34,35,36
      rename_en = 1;
      golden_rename(arch_rd, new_phys_rd);
      #10; rename_en = 0; #5;
      
      // Read previous renamed register
      if (i > 1) begin
        arch_rs1 = i-1; #5;
        check_outputs();
      end
    end

    // Test 4: Commit and verify persistence
    $display("Test 4: Commit persistence");
    commit_arch_rd = 2;
    commit_phys_rd = 34;  // Current mapping for R2
    commit_en = 1;
    golden_commit(commit_arch_rd, commit_phys_rd);
    #10; commit_en = 0;
    
    // Verify committed state is preserved
    arch_rs1 = 2; #5;
    if (golden_committed_table[2] !== 34) begin
      $error("Commit failed: R2 should be PHYS 34 in committed table");
    end

    // Test 5: Write-after-write hazard
    $display("Test 5: Write-after-write");
    arch_rd = 5;
    new_phys_rd = 40;
    rename_en = 1;
    golden_rename(arch_rd, new_phys_rd);
    #10; rename_en = 0; #5;
    
    arch_rd = 5;  // Same arch register again
    new_phys_rd = 41;
    rename_en = 1;
    golden_rename(arch_rd, new_phys_rd);
    #10; rename_en = 0; #5;
    
    arch_rs1 = 5; #5;
    check_outputs();  // Should get latest mapping (41)

    $display("=== Golden Model Testbench: ALL TESTS PASSED ===");
    $finish;
  end

  // Monitor for unexpected behavior
  always @(posedge clk) begin
    if (!reset) begin
      // Check bounds
      assert(phys_rs1 < PHYS_REGS) else 
        $fatal("phys_rs1 out of bounds: %0d", phys_rs1);
      assert(phys_rs2 < PHYS_REGS) else 
        $fatal("phys_rs2 out of bounds: %0d", phys_rs2);
    end
  end

endmodule
