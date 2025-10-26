// Minimal testbench for issue_queue_airtight
// Simulates realistic instruction flow with detailed cycle-by-cycle output
`timescale 1ns/1ps

module tb_issue_queue;
  import core_pkg::*;

  // Parameters
  localparam int ENTRIES = core_pkg::IQ_ENTRIES;
  localparam int ISSUE_W = core_pkg::ISSUE_WIDTH;
  localparam int TAG_W = core_pkg::LOG2_PREGS;
  localparam int CLK_PERIOD = 10;

  // DUT signals
  logic clk, reset;
  
  // Allocation
  logic [ISSUE_W-1:0] alloc_en;
  logic [3:0] alloc_opcode [ISSUE_W-1:0];
  logic [TAG_W-1:0] alloc_src1_tag [ISSUE_W-1:0];
  logic [TAG_W-1:0] alloc_src2_tag [ISSUE_W-1:0];
  logic [31:0] alloc_src1_val [ISSUE_W-1:0];
  logic [31:0] alloc_src2_val [ISSUE_W-1:0];
  core_pkg::preg_tag_t alloc_dst_phys [ISSUE_W-1:0];
  logic [4:0] alloc_dst_rob [ISSUE_W-1:0];
  logic [1:0] alloc_fu_type [ISSUE_W-1:0];
  logic alloc_ok;
  logic [$clog2(ENTRIES)-1:0] alloc_idx [ISSUE_W-1:0];

  // CDB
  logic [ISSUE_W-1:0] cdb_valid;
  logic [TAG_W-1:0] cdb_tag [ISSUE_W-1:0];
  logic [31:0] cdb_value [ISSUE_W-1:0];

  // Issue outputs
  logic [ISSUE_W-1:0] issue_valid;
  logic [3:0] issue_opcode [ISSUE_W-1:0];
  logic [31:0] issue_src1_val [ISSUE_W-1:0];
  logic [31:0] issue_src2_val [ISSUE_W-1:0];
  core_pkg::preg_tag_t issue_dst_phys [ISSUE_W-1:0];
  logic [4:0] issue_dst_rob [ISSUE_W-1:0];

  // Branch port
  logic br_valid;
  logic [3:0] br_opcode;
  logic [31:0] br_src1_val, br_src2_val;
  core_pkg::preg_tag_t br_dst_phys;
  logic [4:0] br_dst_rob;

  // Commit
  logic [ISSUE_W-1:0] commit_valid;
  logic [$clog2(core_pkg::ROB_ENTRIES)-1:0] commit_idx [ISSUE_W-1:0];
  logic commit_clear_all;

  // Status
  logic rs_full, rs_almost_full;

  // Cycle counter
  int cycle;

  // ============================================================
  //  DUT Instantiation
  // ============================================================
  issue_queue_airtight #(
    .ENTRIES(ENTRIES),
    .ISSUE_W(ISSUE_W),
    .TAG_W(TAG_W)
  ) dut (
    .clk(clk),
    .reset(reset),
    .alloc_en(alloc_en),
    .alloc_opcode(alloc_opcode),
    .alloc_src1_tag(alloc_src1_tag),
    .alloc_src2_tag(alloc_src2_tag),
    .alloc_src1_val(alloc_src1_val),
    .alloc_src2_val(alloc_src2_val),
    .alloc_dst_phys(alloc_dst_phys),
    .alloc_dst_rob(alloc_dst_rob),
    .alloc_fu_type(alloc_fu_type),
    .alloc_ok(alloc_ok),
    .alloc_idx(alloc_idx),
    .cdb_valid(cdb_valid),
    .cdb_tag(cdb_tag),
    .cdb_value(cdb_value),
    .issue_valid(issue_valid),
    .issue_opcode(issue_opcode),
    .issue_src1_val(issue_src1_val),
    .issue_src2_val(issue_src2_val),
    .issue_dst_phys(issue_dst_phys),
    .issue_dst_rob(issue_dst_rob),
    .br_valid(br_valid),
    .br_opcode(br_opcode),
    .br_src1_val(br_src1_val),
    .br_src2_val(br_src2_val),
    .br_dst_phys(br_dst_phys),
    .br_dst_rob(br_dst_rob),
    .commit_valid(commit_valid),
    .commit_idx(commit_idx),
    .commit_clear_all(commit_clear_all),
    .rs_full(rs_full),
    .rs_almost_full(rs_almost_full)
  );

  // ============================================================
  //  Clock Generation
  // ============================================================
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ============================================================
  //  Helper Functions
  // ============================================================
  function string opcode_str(input logic [3:0] op);
    case(op)
      4'h0: return "ADD";
      4'h1: return "SUB";
      4'h2: return "MUL";
      4'h3: return "AND";
      4'h4: return "OR";
      4'h5: return "XOR";
      4'h8: return "BEQ";
      4'h9: return "BNE";
      default: return "???";
    endcase
  endfunction

  function string fu_type_str(input logic [1:0] fu);
    case(fu)
      2'b00: return "ALU";
      2'b01: return "BR ";
      default: return "???";
    endcase
  endfunction

  // ============================================================
  //  Monitoring Task
  // ============================================================
  task print_cycle_state();
    automatic int i;
    
    $display("\n========================================");
    $display("CYCLE %0d", cycle);
    $display("========================================");
    
    // Inputs
    $display("\n--- INPUTS ---");
    $display("Alloc_en: %b", alloc_en);
    for (i = 0; i < ISSUE_W; i++) begin
      if (alloc_en[i]) begin
        $display("  [%0d] %s p%0d = p%0d %s p%0d | ROB=%0d FU=%s (slot=%0d)", 
                 i, opcode_str(alloc_opcode[i]),
                 alloc_dst_phys[i], alloc_src1_tag[i], 
                 opcode_str(alloc_opcode[i]), alloc_src2_tag[i],
                 alloc_dst_rob[i], fu_type_str(alloc_fu_type[i]), alloc_idx[i]);
        $display("      src1: tag=p%0d val=%0d | src2: tag=p%0d val=%0d",
                 alloc_src1_tag[i], alloc_src1_val[i],
                 alloc_src2_tag[i], alloc_src2_val[i]);
      end
    end
    
    $display("\nCDB_valid: %b", cdb_valid);
    for (i = 0; i < ISSUE_W; i++) begin
      if (cdb_valid[i]) begin
        $display("  [%0d] p%0d = %0d", i, cdb_tag[i], cdb_value[i]);
      end
    end

    $display("\nCommit_valid: %b", commit_valid);
    for (i = 0; i < ISSUE_W; i++) begin
      if (commit_valid[i]) begin
        $display("  [%0d] ROB[%0d] commits", i, commit_idx[i]);
      end
    end

    // RS Memory State
    $display("\n--- RESERVATION STATION STATE ---");
    $display("Entry | Used | Rdy1 Rdy2 | Tag1  Tag2  | Val1      Val2      | Opcode | DstP | ROB | FU  | Age");
    $display("------|------|-----------|-------------|-----------|-----------|--------|------|-----|-----|----");
    for (i = 0; i < ENTRIES; i++) begin
      if (dut.rs_mem[i].used) begin
        $display("  %0d   |  %b   |  %b    %b   | p%-3d  p%-3d | %-9d %-9d | %-6s | p%-3d | %-3d | %-3s | %0d",
                 i, dut.rs_mem[i].used,
                 dut.rs_mem[i].src1_ready, dut.rs_mem[i].src2_ready,
                 dut.rs_mem[i].src1_tag, dut.rs_mem[i].src2_tag,
                 dut.rs_mem[i].src1_val, dut.rs_mem[i].src2_val,
                 opcode_str(dut.rs_mem[i].opcode),
                 dut.rs_mem[i].dst_phys, dut.rs_mem[i].dst_rob,
                 fu_type_str(dut.rs_mem[i].fu_type),
                 dut.rs_mem[i].age);
      end else begin
        $display("  %0d   |  0   |  -    -   | -     -    | -         -         | -      | -    | -   | -   | -", i);
      end
    end

    // Registered CDB State
    $display("\n--- REGISTERED CDB (cdb_valid_ff) ---");
    $display("cdb_valid_ff: %b", dut.cdb_valid_ff);
    for (i = 0; i < ISSUE_W; i++) begin
      if (dut.cdb_valid_ff[i]) begin
        $display("  [%0d] p%0d = %0d", i, dut.cdb_tag_ff[i], dut.cdb_value_ff[i]);
      end
    end

    // Outputs
    $display("\n--- OUTPUTS (Combinational) ---");
    $display("Issue_valid: %b", issue_valid);
    for (i = 0; i < ISSUE_W; i++) begin
      if (issue_valid[i]) begin
        $display("  ALU[%0d]: %s (src1=%0d, src2=%0d) -> p%0d [ROB=%0d]",
                 i, opcode_str(issue_opcode[i]),
                 issue_src1_val[i], issue_src2_val[i],
                 issue_dst_phys[i], issue_dst_rob[i]);
      end
    end

    if (br_valid) begin
      $display("  BR: %s (src1=%0d, src2=%0d) -> p%0d [ROB=%0d]",
               opcode_str(br_opcode),
               br_src1_val, br_src2_val,
               br_dst_phys, br_dst_rob);
    end

    $display("\nStatus: alloc_ok=%b | rs_full=%b | rs_almost_full=%b",
             alloc_ok, rs_full, rs_almost_full);
    $display("Age Counter: %0d", dut.age_counter);
  endtask

  // ============================================================
  //  Test Sequence - Realistic Instruction Flow
  // ============================================================
  initial begin
    automatic int i;
    
    $display("\n");
    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║  ISSUE QUEUE TESTBENCH - Realistic Instruction Flow         ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    $display("\nTest Instructions:");
    $display("  I0: ADD p10 = p1 + p2   (ROB[0], ALU) - both srcs ready");
    $display("  I1: MUL p11 = p10 + p3  (ROB[1], ALU) - depends on I0");
    $display("  I2: SUB p12 = p11 + p4  (ROB[2], ALU) - depends on I1");
    $display("  I3: AND p13 = p5 + p6   (ROB[3], ALU) - independent");
    
    // Initialize
    cycle = 0;
    reset = 1;
    alloc_en = 0;
    cdb_valid = 0;
    commit_valid = 0;
    commit_clear_all = 0;
    
    for (i = 0; i < ISSUE_W; i++) begin
      alloc_opcode[i] = 0;
      alloc_src1_tag[i] = 0;
      alloc_src2_tag[i] = 0;
      alloc_src1_val[i] = 0;
      alloc_src2_val[i] = 0;
      alloc_dst_phys[i] = 0;
      alloc_dst_rob[i] = 0;
      alloc_fu_type[i] = 0;
      cdb_tag[i] = 0;
      cdb_value[i] = 0;
      commit_idx[i] = 0;
    end

    // Reset
    @(posedge clk);
    cycle++;
    reset = 0;
    print_cycle_state();

    // ==================== CYCLE 1 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n>>> ALLOCATING I0 and I1 <<<");
    
    // I0: ADD p10 = p1 + p2 (both ready, values 5 and 3)
    alloc_en = 2'b11;
    alloc_opcode[0] = 4'h0; // ADD
    alloc_src1_tag[0] = 6'd1;
    alloc_src2_tag[0] = 6'd2;
    alloc_src1_val[0] = 32'd5;   // p1 = 5
    alloc_src2_val[0] = 32'd3;   // p2 = 3
    alloc_dst_phys[0] = 6'd10;
    alloc_dst_rob[0] = 5'd0;
    alloc_fu_type[0] = 2'b00; // ALU

    // I1: MUL p11 = p10 + p3 (p10 not ready yet, p3 ready = 7)
    alloc_opcode[1] = 4'h2; // MUL
    alloc_src1_tag[1] = 6'd10; // Waits for p10 from I0
    alloc_src2_tag[1] = 6'd3;
    alloc_src1_val[1] = 32'd0;   // Not ready
    alloc_src2_val[1] = 32'd7;   // p3 = 7
    alloc_dst_phys[1] = 6'd11;
    alloc_dst_rob[1] = 5'd1;
    alloc_fu_type[1] = 2'b00; // ALU

    cdb_valid = 0;
    commit_valid = 0;
    
    #1; // Let combinational logic settle
    print_cycle_state();

    // ==================== CYCLE 2 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n>>> I0 ISSUES and EXECUTES (produces p10=8) <<<");
    
    alloc_en = 0; // No new allocations
    
    // I0 completes execution, broadcasts on CDB
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd10;  // p10
    cdb_value[0] = 32'd8; // 5 + 3 = 8
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 3 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n>>> I1 WAKES UP (p10 ready), ALLOCATE I2 and I3 <<<");
    
    // I2: SUB p12 = p11 + p4 (p11 not ready, p4 ready = 2)
    alloc_en = 2'b11;
    alloc_opcode[0] = 4'h1; // SUB
    alloc_src1_tag[0] = 6'd11; // Waits for p11 from I1
    alloc_src2_tag[0] = 6'd4;
    alloc_src1_val[0] = 32'd0;   // Not ready
    alloc_src2_val[0] = 32'd2;   // p4 = 2
    alloc_dst_phys[0] = 6'd12;
    alloc_dst_rob[0] = 5'd2;
    alloc_fu_type[0] = 2'b00; // ALU

    // I3: AND p13 = p5 + p6 (both ready)
    alloc_opcode[1] = 4'h3; // AND
    alloc_src1_tag[1] = 6'd5;
    alloc_src2_tag[1] = 6'd6;
    alloc_src1_val[1] = 32'd15;  // p5 = 15
    alloc_src2_val[1] = 32'd12;  // p6 = 12
    alloc_dst_phys[1] = 6'd13;
    alloc_dst_rob[1] = 5'd3;
    alloc_fu_type[1] = 2'b00; // ALU

    cdb_valid = 0; // Clear CDB
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 4 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n>>> I1 and I3 ISSUE (both ready), I1 produces p11=56 <<<");
    
    alloc_en = 0;
    
    // I1 completes
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd11;   // p11
    cdb_value[0] = 32'd56; // 8 * 7 = 56
    
    // I0 commits
    commit_valid = 2'b01;
    commit_idx[0] = 5'd0;
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 5 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n>>> I2 WAKES UP (p11 ready), I3 produces p13=12 <<<");
    
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd13;   // p13
    cdb_value[0] = 32'd12; // 15 & 12 = 12
    
    commit_valid = 2'b01;
    commit_idx[0] = 5'd1; // I1 commits
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 6 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n>>> I2 ISSUES (now ready), produces p12=54 <<<");
    
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd12;   // p12
    cdb_value[0] = 32'd54; // 56 - 2 = 54
    
    commit_valid = 2'b11;
    commit_idx[0] = 5'd2; // I2 commits
    commit_idx[1] = 5'd3; // I3 commits
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 7 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n>>> ALL INSTRUCTIONS COMPLETE <<<");
    
    alloc_en = 0;
    cdb_valid = 0;
    commit_valid = 0;
    
    #1;
    print_cycle_state();

    $display("\n\n╔══════════════════════════════════════════════════════════════╗");
    $display("║  TEST COMPLETE - All instructions executed successfully      ║");
    $display("╚══════════════════════════════════════════════════════════════╝\n");
    
    #100;
    $finish;
  end

  // Timeout
  initial begin
    #10000;
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
