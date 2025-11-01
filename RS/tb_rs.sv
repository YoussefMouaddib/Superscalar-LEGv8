// Updated testbench for zero-latency reservation station
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

  // CDB broadcast (NOW COMBINATIONAL - zero latency)
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
  //  CDB Generation (ZERO LATENCY - combinational)
  // ============================================================
  always_comb begin
    cdb_valid = '0;
    cdb_tag = '0;
    cdb_value = '0;
    
    // CDB broadcasts results in the SAME cycle as issue
    for (int i = 0; i < ISSUE_W; i++) begin
      if (issue_valid[i]) begin
        cdb_valid[i] = 1'b1;
        cdb_tag[i] = issue_dst_tag[i];
        
        // Calculate result based on opcode (simplified)
        case (issue_op[i])
          8'h01: cdb_value[i] = issue_src1_val[i] + issue_src2_val[i]; // ADD
          8'h02: cdb_value[i] = issue_src1_val[i] - issue_src2_val[i]; // SUB
          8'h03: cdb_value[i] = issue_src1_val[i] & issue_src2_val[i]; // AND
          8'h04: cdb_value[i] = issue_src1_val[i] | issue_src2_val[i]; // OR
          8'h05: cdb_value[i] = issue_src1_val[i] ^ issue_src2_val[i]; // XOR
          default: cdb_value[i] = issue_src1_val[i];
        endcase
      end
    end
  end

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
      default: return "UNK  ";
    endcase
  endfunction

  function string ready_str(input logic ready);
    return ready ? "READY" : "WAIT ";
  endfunction

  // ============================================================
  //  Monitoring Task
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
    $display("Alloc_en: %b", alloc_en);
    for (i = 0; i < ISSUE_W; i++) begin
      if (alloc_en[i]) begin
        $display("  Port[%0d]: %s p%0d = p%0d %s p%0d | ROB=%0d", 
                 i, opcode_str(alloc_op[i]),
                 alloc_dst_tag[i], alloc_src1_tag[i], 
                 opcode_str(alloc_op[i]), alloc_src2_tag[i],
                 alloc_rob_tag[i]);
      end
    end
    
    // CDB Outputs (from execution units - SAME CYCLE)
    $display("\n📡 CDB BROADCAST (zero latency)");
    $display("valid=%b", cdb_valid);
    for (i = 0; i < CDB_W; i++) begin
      if (cdb_valid[i]) begin
        $display("  CDB[%0d]: p%0d = %0d", i, cdb_tag[i], cdb_value[i]);
      end
    end

    // RS State
    $display("\n💾 RESERVATION STATION STATE");
    $display("Entry | V | Rdy1 Rdy2 | Tag1  Tag2  | Val1      Val2      | Operation");
    for (i = 0; i < RS_ENTRIES; i++) begin
      if (dut.rs_mem[i].valid) begin
        $display("  %2d  | %b |  %b     %b   | p%-3d  p%-3d | %-9d %-9d | %s → p%-2d",
                 i, dut.rs_mem[i].valid,
                 dut.rs_mem[i].src1_ready, dut.rs_mem[i].src2_ready,
                 dut.rs_mem[i].src1_tag, dut.rs_mem[i].src2_tag,
                 dut.rs_mem[i].src1_val, dut.rs_mem[i].src2_val,
                 opcode_str(dut.rs_mem[i].opcode), dut.rs_mem[i].dst_tag);
      end
    end

    // Outputs
    $display("\n📤 OUTPUTS");
    $display("Issue_valid: %b", issue_valid);
    for (i = 0; i < ISSUE_W; i++) begin
      if (issue_valid[i]) begin
        $display("  Issue[%0d]: %s (src1=%0d, src2=%0d) → p%0d",
                 i, opcode_str(issue_op[i]),
                 issue_src1_val[i], issue_src2_val[i], issue_dst_tag[i]);
      end
    end

    // Dependency Analysis
    $display("\n🔗 DEPENDENCY ANALYSIS");
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

    $display("════════════════════════════════════════════════════════════════");
  endtask

  // ============================================================
  //  Test Sequence with ZERO LATENCY Timing
  // ============================================================
  initial begin
    automatic int i;
    automatic int valid_count;
    
    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║  ZERO-LATENCY RESERVATION STATION TESTBENCH                ║");
    $display("╚══════════════════════════════════════════════════════════════╝");
    
    $display("\n📋 TEST INSTRUCTION SEQUENCE:");
    $display("I0: ADD  p10 = p1(5) + p2(3)     [ROB0] - both ready");
    $display("I1: SUB  p11 = p10(?) + p3(7)    [ROB1] - depends on I0");
    $display("I2: AND  p12 = p4(2) + p5(6)     [ROB2] - independent");
    
    // Initialize
    cycle = 0;
    reset = 1;
    alloc_en = '0;
    
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
    end

    // Reset Cycle
    @(posedge clk);
    cycle++;
    reset = 0;
    print_cycle_state();

    // ==================== CYCLE 1 ====================
    @(posedge clk);
    cycle++;
    $display("\n🎯 CYCLE 1: ALLOCATE I0 and I1 - I0 SHOULD ISSUE IMMEDIATELY");
    
    alloc_en = 2'b11;
    
    // Port 0: I0 (ready)
    alloc_op[0] = 8'h01; // ADD
    alloc_dst_tag[0] = 6'd10;
    alloc_src1_tag[0] = 6'd1;
    alloc_src2_tag[0] = 6'd2;
    alloc_src1_val[0] = 64'd5;
    alloc_src2_val[0] = 64'd3;
    alloc_src1_ready[0] = 1'b1;
    alloc_src2_ready[0] = 1'b1;
    alloc_rob_tag[0] = 6'd0;

    // Port 1: I1 (waits for p10)
    alloc_op[1] = 8'h02; // SUB
    alloc_dst_tag[1] = 6'd11;
    alloc_src1_tag[1] = 6'd10; // Depends on I0
    alloc_src2_tag[1] = 6'd3;
    alloc_src1_val[1] = 64'd0;
    alloc_src2_val[1] = 64'd7;
    alloc_src1_ready[1] = 1'b0;
    alloc_src2_ready[1] = 1'b1;
    alloc_rob_tag[1] = 6'd1;
    
    #9; // Wait for combinational logic
    print_cycle_state();

    // ==================== CYCLE 2 ====================
    @(posedge clk);
    cycle++;
    $display("\n🎯 CYCLE 2: I1 SHOULD WAKE UP AND ISSUE (sees p10 from CDB)");
    
    // Allocate independent I2
    alloc_en = 2'b01;
    alloc_op[0] = 8'h03; // AND
    alloc_dst_tag[0] = 6'd12;
    alloc_src1_tag[0] = 6'd4;
    alloc_src2_tag[0] = 6'd5;
    alloc_src1_val[0] = 64'd2;
    alloc_src2_val[0] = 64'd6;
    alloc_src1_ready[0] = 1'b1;
    alloc_src2_ready[0] = 1'b1;
    alloc_rob_tag[0] = 6'd2;
    
    #9;
    print_cycle_state();

    // ==================== CYCLE 3 ====================
    @(posedge clk);
    cycle++;
    $display("\n🎯 CYCLE 3: I2 SHOULD ISSUE (independent), I1 COMPLETES");
    
    alloc_en = '0;
    
    #9;
    print_cycle_state();

    // Final check
    @(posedge clk);
    valid_count = 0;
    for (i = 0; i < RS_ENTRIES; i++) begin
      if (dut.rs_mem[i].valid) valid_count++;
    end
    
    if (valid_count == 0) begin
      $display("✅ SUCCESS: Zero-latency wakeup working correctly!");
    end else begin
      $display("❌ FAILURE: %0d entries still valid", valid_count);
    end
    
    #100;
    $finish;
  end

  initial begin
    #10000;
    $display("❌ ERROR: Simulation timeout!");
    $finish;
  end

endmodule
