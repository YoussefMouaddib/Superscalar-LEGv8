`timescale 1ns/1ps
module tb_rename_table;

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
  logic [5:0]  old_src1;

  // Instantiate DUT
  rename_table #(.ARCH_REGS(ARCH_REGS), .PHYS_REGS(PHYS_REGS)) dut (
    .clk(clk),
    .reset(reset),
    .arch_rs1(arch_rs1),
    .arch_rs2(arch_rs2),
    .phys_rs1(phys_rs1),
    .phys_rs2(phys_rs2),
    .rename_en(rename_en),
    .arch_rd(arch_rd),
    .new_phys_rd(new_phys_rd),
    .commit_en(commit_en),
    .commit_arch_rd(commit_arch_rd),
    .commit_phys_rd(commit_phys_rd)
  );

  // clock generator: 100 MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // helper: reset pulse
  task do_reset();
    begin
      reset = 1;
      rename_en = 0; commit_en = 0;
      #20;
      reset = 0;
      #20;
    end
  endtask

  // initial tests + random stress
  initial begin
    $display("\n=== tb_rename_table start ===");
    do_reset();

    // --- 1) initial mapping check (arch i -> phys i)
    arch_rs1 = 5'd2; arch_rs2 = 5'd3;
    #10;
    assert(phys_rs1 === 6'd2 && phys_rs2 === 6'd3) else begin
      $fatal("Initial mapping wrong: phys_rs1=%0d phys_rs2=%0d", phys_rs1, phys_rs2);
    end

    // --- 2) rename operation (update mapping)
    arch_rd = 5'd2; new_phys_rd = 6'd40; rename_en = 1;
    #10; rename_en = 0; // allow write to take effect
    #5;
    arch_rs1 = 5'd2; // read renamed mapping
    #5;
    assert(phys_rs1 === 6'd40) else $fatal("Rename failed: expected 40 got %0d", phys_rs1);

    // --- 3) commit must update committed_table (we can't directly observe committed_table)
    // We'll simulate commit by writing a different mapping and then renaming again to see persistence semantics.
    commit_arch_rd = 5'd2; commit_phys_rd = 6'd40; commit_en = 1;
    #10; commit_en = 0;
    // sanity: after commit, perform another rename to a new phys and check map updates
    arch_rd = 5'd2; new_phys_rd = 6'd41; rename_en = 1;
    #10; rename_en = 0;
    #5;
    arch_rs1 = 5'd2; #5;
    assert(phys_rs1 === 6'd41) else $fatal("Post-commit rename failed: expected 41 got %0d", phys_rs1);

    // --- 4) edge: src == dst (rename destination equals one of sources)
    // read mapping before rename
    arch_rs1 = 5'd5; arch_rs2 = 5'd6;
    #5;
    old_src1 = phys_rs1;
    // rename arch_rd = 5 to new phys
    arch_rd = 5'd5; 
    new_phys_rd = 6'd30; 
    rename_en = 1;
    #10; 
    rename_en = 0; 
    #5;
    // after rename, phys_rs1 should reflect new mapping, and must not equal old_src1 if allocation different
    arch_rs1 = 5'd5; #5;
    assert(phys_rs1 !== old_src1) else $fatal("SRC=DEST alias: phys mapping did not change");

    // --- 5) repeated renames (same arch reg renamed multiple times)
    for (int i = 0; i < 4; i++) begin
      arch_rd = 5'd7;
      new_phys_rd = 6'(10 + i);
      rename_en = 1;
      #10; rename_en = 0; #5;
      arch_rs1 = 5'd7; #5;
      assert(phys_rs1 === (6'(10 + i))) else $fatal("Repeated rename failed at iter %0d", i);
    end

    // --- 6) attempt overflow aggressor (many renames across arch regs)
    // This just stresses mapping writes; rename_table doesn't allocate physs itself so it won't detect freelist exhaustion.
    for (int i = 0; i < ARCH_REGS; i++) begin
      arch_rd = i[4:0];
      new_phys_rd = (i + 8) % PHYS_REGS;
      rename_en = 1;
      #5; rename_en = 0; #5;
    end

    // --- 7) random stress: 400 cycles
    for (int cycle = 0; cycle < 400; cycle++) begin
      arch_rs1 = $urandom_range(0, ARCH_REGS-1);
      arch_rs2 = $urandom_range(0, ARCH_REGS-1);
      arch_rd  = $urandom_range(0, ARCH_REGS-1);
      new_phys_rd = $urandom_range(0, PHYS_REGS-1);
      rename_en = ($urandom_range(0,3) == 0) ? 1'b1 : 1'b0; // ~25% renames
      commit_en = ($urandom_range(0,7) == 0) ? 1'b1 : 1'b0; // ~12.5% commits
      if (commit_en) begin
        commit_arch_rd = $urandom_range(0, ARCH_REGS-1);
        commit_phys_rd = $urandom_range(0, PHYS_REGS-1);
      end
      #10;
      // basic invariant: mapping indices must be within phys range
      assert(phys_rs1 < PHYS_REGS) else $fatal("phys_rs1 out of range cycle=%0d val=%0d", cycle, phys_rs1);
      assert(phys_rs2 < PHYS_REGS) else $fatal("phys_rs2 out of range cycle=%0d val=%0d", cycle, phys_rs2);
    end

    $display("=== tb_rename_table: ALL TESTS PASSED ===");
    $finish;
  end

endmodule
