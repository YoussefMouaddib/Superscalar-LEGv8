// Detailed testbench for reservation_station module
// Extensive debugging output for cycle-by-cycle analysis
`timescale 1ns/1ps

module tb_reservation_station;
  import core_pkg::*;

  // Parameters
  localparam int RS_ENTRIES = 16;
  localparam int ISSUE_W = 2;
  localparam int CDB_W = 2;
  localparam int PHYS_W = 6;
  localparam int CLK_PERIOD = 10;

  // DUT signals
  logic clk, reset;
  
  // Allocation interface
  logic [ISSUE_W-1:0] alloc_en;
  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_dst_tag;
  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_src1_tag;
  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_src2_tag;
  logic [ISSUE_W-1:0][63:0] alloc_src1_val;
  logic [ISSUE_W-1:0][63:0] alloc_src2_val;
  logic [ISSUE_W-1:0] alloc_src1_ready;
  logic [ISSUE_W-1:0] alloc_src2_ready;
  logic [ISSUE_W-1:0][7:0] alloc_op;
  logic [ISSUE_W-1:0][5:0] alloc_rob_tag;

  // CDB broadcast
  logic [CDB_W-1:0] cdb_valid;
  logic [CDB_W-1:0][PHYS_W-1:0] cdb_tag;
  logic [CDB_W-1:0][63:0] cdb_value;

  // Issue outputs
  logic [ISSUE_W-1:0] issue_valid;
  logic [ISSUE_W-1:0][7:0] issue_op;
  logic [ISSUE_W-1:0][PHYS_W-1:0] issue_dst_tag;
  logic [ISSUE_W-1:0][63:0] issue_src1_val;
  logic [ISSUE_W-1:0][63:0] issue_src2_val;
  logic [ISSUE_W-1:0][5:0] issue_rob_tag;

  // Cycle counter
  int cycle;

  // ============================================================
  //  DUT Instantiation
  // ============================================================
  reservation_station #(
    .RS_ENTRIES(RS_ENTRIES),
    .ISSUE_W(ISSUE_W),
    .CDB_W(CDB_W),
    .PHYS_W(PHYS_W)
  ) dut (
    .clk(clk),
    .reset(reset),
    .alloc_en(alloc_en),
    .alloc_dst_tag(alloc_dst_tag),
    .alloc_src1_tag(alloc_src1_tag),
    .alloc_src2_tag(alloc_src2_tag),
    .alloc_src1_val(alloc_src1_val),
    .alloc_src2_val(alloc_src2_val),
    .alloc_src1_ready(alloc_src1_ready),
    .alloc_src2_ready(alloc_src2_ready),
    .alloc_op(alloc_op),
    .alloc_rob_tag(alloc_rob_tag),
    .cdb_valid(cdb_valid),
    .cdb_tag(cdb_tag),
    .cdb_value(cdb_value),
    .issue_valid(issue_valid),
    .issue_op(issue_op),
    .issue_dst_tag(issue_dst_tag),
    .issue_src1_val(issue_src1_val),
    .issue_src2_val(issue_src2_val),
    .issue_rob_tag(issue_rob_tag)
  );

  // ============================================================
  //  Clock Generation
  // ============================================================
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ============================================================
  //  Helper Functions
  // ============================================================
  function string opcode_str(input logic [7:0] op);
    case(op)
      8'h01: return "ADD  ";
      8'h02: return "SUB  ";
      8'h03: return "AND  ";
      8'h04: return "OR   ";
      8'h05: return "XOR  ";
      8'h06: return "LSL  ";
      8'h07: return "LSR  ";
      8'h10: return "LDR  ";
      8'h11: return "STR  ";
      8'h20: return "B    ";
      8'h21: return "BL   ";
      8'h22: return "RET  ";
      default: return "UNK  ";
    endcase
  endfunction

  function string ready_str(input logic ready);
    return ready ? "READY" : "WAIT ";
  endfunction

  // ============================================================
  //  Monitoring Task - EXTREMELY DETAILED
  // ============================================================
  task print_cycle_state();
    automatic int i;
    automatic int free_count;
    automatic int ready_count;
    automatic int waiting_count;
    
    $display("\n════════════════════════════════════════════════════════════════");
    $display("CYCLE %0d", cycle);
    $display("════════════════════════════════════════════════════════════════");
    
    // Inputs Section
    $display("\n📥 INPUTS");
    $display("──────────");
    
    // Allocation Inputs
    $display("Alloc_en: %b", alloc_en);
    for (i = 0; i < ISSUE_W; i++) begin
      if (alloc_en[i]) begin
        $display("  Port[%0d]: %s p%0d = p%0d %s p%0d | ROB=%0d", 
                 i, opcode_str(alloc_op[i]),
                 alloc_dst_tag[i], alloc_src1_tag[i], 
                 opcode_str(alloc_op[i]), alloc_src2_tag[i],
                 alloc_rob_tag[i]);
        $display("           src1: tag=p%0d val=%-4d [%s]", 
                 alloc_src1_tag[i], alloc_src1_val[i], ready_str(alloc_src1_ready[i]));
        $display("           src2: tag=p%0d val=%-4d [%s]", 
                 alloc_src2_tag[i], alloc_src2_val[i], ready_str(alloc_src2_ready[i]));
      end else begin
        $display("  Port[%0d]: --- IDLE ---", i);
      end
    end
    
    // CDB Inputs
    $display("\nCDB_valid: %b", cdb_valid);
    for (i = 0; i < CDB_W; i++) begin
      if (cdb_valid[i]) begin
        $display("  CDB[%0d]: p%0d = %0d", i, cdb_tag[i], cdb_value[i]);
      end else begin
        $display("  CDB[%0d]: --- IDLE ---", i);
      end
    end

    // RS Memory State - COMPLETE DUMP
    $display("\n💾 RESERVATION STATION STATE (%0d entries)", RS_ENTRIES);
    $display("────────────────────────────────────────────────────────────────");
    $display("Entry | V | Rdy1 Rdy2 | Tag1  Tag2  | Val1      Val2      | Operation         | DstP | ROB  | Age");
    $display("──────┼───┼───────────┼─────────────┼─────────────────────┼───────────────────┼──────┼──────┼────");
    for (i = 0; i < RS_ENTRIES; i++) begin
      if (dut.rs_mem[i].valid) begin
        $display("  %2d  | %b |  %b     %b   | p%-3d  p%-3d | %-9d %-9d | %s → p%-2d [ROB%0d] | %0d",
                 i, dut.rs_mem[i].valid,
                 dut.rs_mem[i].src1_ready, dut.rs_mem[i].src2_ready,
                 dut.rs_mem[i].src1_tag, dut.rs_mem[i].src2_tag,
                 dut.rs_mem[i].src1_val, dut.rs_mem[i].src2_val,
                 opcode_str(dut.rs_mem[i].opcode),
                 dut.rs_mem[i].dst_tag, dut.rs_mem[i].rob_tag,
                 dut.rs_mem[i].age);
      end else begin
        $display("  %2d  | 0 |  -     -   | -     -    | -         -         | -                 | -    | -    | -", i);
      end
    end

    // Free Slot Analysis
    $display("\n🔍 FREE SLOT ANALYSIS");
    $display("────────────────────");
    free_count = 0;
    for (i = 0; i < RS_ENTRIES; i++) begin
      if (!dut.rs_mem[i].valid) free_count++;
    end
    $display("Free slots: %0d/%0d", free_count, RS_ENTRIES);
    $write("Free slot indices: ");
    for (i = 0; i < RS_ENTRIES; i++) begin
      if (!dut.rs_mem[i].valid) $write("%0d ", i);
    end
    $display("");

    // Registered CDB State (CRITICAL FOR TIMING ANALYSIS)
    $display("\n⏰ REGISTERED CDB STATE (cdb_valid_ff)");
    $display("───────────────────────────────────────");
    $display("cdb_valid_ff: %b", dut.cdb_valid_ff);
    for (i = 0; i < CDB_W; i++) begin
      if (dut.cdb_valid_ff[i]) begin
        $display("  CDB_ff[%0d]: p%0d = %0d", i, dut.cdb_tag_ff[i], dut.cdb_value_ff[i]);
      end else begin
        $display("  CDB_ff[%0d]: --- IDLE ---", i);
      end
    end

    // Outputs Section
    $display("\n📤 OUTPUTS");
    $display("──────────");
    $display("Issue_valid: %b", issue_valid);
    for (i = 0; i < ISSUE_W; i++) begin
      if (issue_valid[i]) begin
        $display("  Issue[%0d]: %s (src1=%0d, src2=%0d) → p%0d [ROB=%0d]",
                 i, opcode_str(issue_op[i]),
                 issue_src1_val[i], issue_src2_val[i],
                 issue_dst_tag[i], issue_rob_tag[i]);
      end else begin
        $display("  Issue[%0d]: --- NO ISSUE ---", i);
      end
    end

    // Dependency Analysis
    $display("\n🔗 DEPENDENCY ANALYSIS");
    $display("─────────────────────");
    ready_count = 0;
    waiting_count = 0;
    for (i = 0; i < RS_ENTRIES; i++) begin
      if (dut.rs_mem[i].valid) begin
        if (dut.rs_mem[i].src1_ready && dut.rs_mem[i].src2_ready) begin
          ready_count++;
          $display("  Entry %2d: READY for issue (age=%0d)", i, dut.rs_mem[i].age);
        end else begin
          waiting_count++;
          $display("  Entry %2d: WAITING - src1:%s src2:%s", i, 
                   ready_str(dut.rs_mem[i].src1_ready), 
                   ready_str(dut.rs_mem[i].src2_ready));
        end
      end
    end
    $display("Ready entries: %0d, Waiting entries: %0d", ready_count, waiting_count);

    $display("\n════════════════════════════════════════════════════════════════");
  endtask

  // ============================================================
  //  Test Sequence - Realistic Dependency Chain
  // ============================================================
  initial begin
    automatic int i;
    automatic int valid_count;
    
    $display("\n");
    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║  RESERVATION STATION TESTBENCH - Dependency Chain Test      ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    
    $display("\n📋 TEST INSTRUCTION SEQUENCE:");
    $display("─────────────────────────────");
    $display("I0: ADD  p10 = p1(5) + p2(3)     [ROB0] - both ready");
    $display("I1: MUL  p11 = p10(?) + p3(7)    [ROB1] - depends on I0");
    $display("I2: SUB  p12 = p11(?) + p4(2)    [ROB2] - depends on I1");  
    $display("I3: AND  p13 = p5(15) + p6(12)   [ROB3] - independent");
    $display("I4: OR   p14 = p13(?) + p7(9)    [ROB4] - depends on I3");
    
    // Initialize
    cycle = 0;
    reset = 1;
    alloc_en = '0;
    cdb_valid = '0;
    
    for (i = 0; i < ISSUE_W; i++) begin
      alloc_dst_tag[i] = '0;
      alloc_src1_tag[i] = '0;
      alloc_src2_tag[i] = '0;
      alloc_src1_val[i] = '0;
      alloc_src2_val[i] = '0;
      alloc_src1_ready[i] = '0;
      alloc_src2_ready[i] = '0;
      alloc_op[i] = '0;
      alloc_rob_tag[i] = '0;
      cdb_tag[i] = '0;
      cdb_value[i] = '0;
    end

    // Reset Cycle
    @(posedge clk);
    cycle++;
    reset = 0;
    print_cycle_state();

    // ==================== CYCLE 1 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n🎯 CYCLE 1: ALLOCATING I0 and I1");
    
    // I0: ADD p10 = p1 + p2 (both ready)
    alloc_en = 2'b11;
    
    // Port 0: I0
    alloc_op[0] = 8'h01; // ADD
    alloc_dst_tag[0] = 6'd10;
    alloc_src1_tag[0] = 6'd1;
    alloc_src2_tag[0] = 6'd2;
    alloc_src1_val[0] = 64'd5;   // p1 = 5
    alloc_src2_val[0] = 64'd3;   // p2 = 3
    alloc_src1_ready[0] = 1'b1;
    alloc_src2_ready[0] = 1'b1;
    alloc_rob_tag[0] = 6'd0;

    // Port 1: I1 - depends on I0 (p10 not ready)
    alloc_op[1] = 8'h02; // MUL (using SUB opcode as MUL)
    alloc_dst_tag[1] = 6'd11;
    alloc_src1_tag[1] = 6'd10; // Waits for p10 from I0
    alloc_src2_tag[1] = 6'd3;
    alloc_src1_val[1] = 64'd0;   // Not ready
    alloc_src2_val[1] = 64'd7;   // p3 = 7
    alloc_src1_ready[1] = 1'b0;  // p10 not ready
    alloc_src2_ready[1] = 1'b1;  // p3 ready
    alloc_rob_tag[1] = 6'd1;

    cdb_valid = '0;
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 2 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n🎯 CYCLE 2: I0 ISSUES, ALLOCATE I2 and I3");
    
    // I0 should issue (both operands ready)
    alloc_en = 2'b11;
    
    // Port 0: I2 - depends on I1 (p11 not ready)
    alloc_op[0] = 8'h02; // SUB
    alloc_dst_tag[0] = 6'd12;
    alloc_src1_tag[0] = 6'd11; // Waits for p11 from I1
    alloc_src2_tag[0] = 6'd4;
    alloc_src1_val[0] = 64'd0;   // Not ready
    alloc_src2_val[0] = 64'd2;   // p4 = 2
    alloc_src1_ready[0] = 1'b0;
    alloc_src2_ready[0] = 1'b1;
    alloc_rob_tag[0] = 6'd2;

    // Port 1: I3 - independent (both ready)
    alloc_op[1] = 8'h03; // AND
    alloc_dst_tag[1] = 6'd13;
    alloc_src1_tag[1] = 6'd5;
    alloc_src2_tag[1] = 6'd6;
    alloc_src1_val[1] = 64'd15;  // p5 = 15
    alloc_src2_val[1] = 64'd12;  // p6 = 12
    alloc_src1_ready[1] = 1'b1;
    alloc_src2_ready[1] = 1'b1;
    alloc_rob_tag[1] = 6'd3;

    // I0 completes execution, broadcasts p10=8
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd10;
    cdb_value[0] = 64'd8; // 5 + 3 = 8
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 3 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n🎯 CYCLE 3: I1 WAKES UP, I3 ISSUES, ALLOCATE I4");
    
    // I1 should wake up (p10 now available via CDB_ff)
    // I3 should issue (both ready)
    alloc_en = 2'b01;
    
    // Port 0: I4 - depends on I3 (p13 not ready)
    alloc_op[0] = 8'h04; // OR
    alloc_dst_tag[0] = 6'd14;
    alloc_src1_tag[0] = 6'd13; // Waits for p13 from I3
    alloc_src2_tag[0] = 6'd7;
    alloc_src1_val[0] = 64'd0;   // Not ready
    alloc_src2_val[0] = 64'd9;   // p7 = 9
    alloc_src1_ready[0] = 1'b0;
    alloc_src2_ready[0] = 1'b1;
    alloc_rob_tag[0] = 6'd4;

    // Port 1: no allocation
    alloc_en[1] = 1'b0;

    // I1 completes execution, broadcasts p11=56
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd11;
    cdb_value[0] = 64'd56; // 8 * 7 = 56
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 4 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n🎯 CYCLE 4: I2 WAKES UP, I1 and I3 COMPLETE");
    
    alloc_en = '0;
    
    // I3 completes execution, broadcasts p13=12
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd13;
    cdb_value[0] = 64'd12; // 15 & 12 = 12
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 5 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n🎯 CYCLE 5: I2 and I4 ISSUE, CHAIN COMPLETE");
    
    alloc_en = '0;
    
    // I2 and I4 should both issue now
    // I2 completes, broadcasts p12=54
    cdb_valid = 2'b01;
    cdb_tag[0] = 6'd12;
    cdb_value[0] = 64'd54; // 56 - 2 = 54
    
    // I4 completes, broadcasts p14=13  
    cdb_valid[1] = 1'b1;
    cdb_tag[1] = 6'd14;
    cdb_value[1] = 64'd13; // 12 | 9 = 13
    
    #1;
    print_cycle_state();

    // ==================== CYCLE 6 ====================
    @(posedge clk);
    cycle++;
    $display("\n\n🎯 CYCLE 6: FINAL STATE - ALL ENTRIES SHOULD BE CLEAR");
    
    alloc_en = '0;
    cdb_valid = '0;
    
    #1;
    print_cycle_state();

    $display("\n\n╔══════════════════════════════════════════════════════════════╗");
    $display("║  TEST COMPLETE - Verifying final state                        ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    
    // Final verification
    valid_count = 0;
    for (i = 0; i < RS_ENTRIES; i++) begin
      if (dut.rs_mem[i].valid) valid_count++;
    end
    
    if (valid_count == 0) begin
      $display("✅ SUCCESS: All entries cleared - dependency chain resolved correctly!");
    end else begin
      $display("❌ FAILURE: %0d entries still valid - possible issue with clearing", valid_count);
    end
    
    #100;
    $finish;
  end

  // Timeout
  initial begin
    #10000;
    $display("❌ ERROR: Simulation timeout!");
    $finish;
  end

endmodule
