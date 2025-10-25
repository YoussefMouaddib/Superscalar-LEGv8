// issue_queue.sv
// Reservation Station / Issue Queue for minimal OoO core
// - 2 alloc/cycle, 16 entries (IQ_ENTRIES from core_pkg), 2 issue ports
// - 2 identical ALU issue ports + 1 branch port
// - Oldest-first selection based on allocation cycle stamp
// - Wakeup by CDB broadcasts (phys_tag, value, valid) up to ISSUE_WIDTH broadcasts
`timescale 1ns/1ps
import core_pkg::*;

module issue_queue #(
  parameter int ENTRIES    = core_pkg::IQ_ENTRIES,
  parameter int ISSUE_W    = core_pkg::ISSUE_WIDTH, // typically 2
  parameter int TAG_W      = $clog2(core_pkg::PREGS)
)(
  input  logic                     clk,
  input  logic                     reset,

  // --------------------
  // Allocation (from rename/dispatch) - up to ISSUE_W allocs/cycle
  input  logic [ISSUE_W-1:0]                   alloc_en,
  input  logic [3:0]                            alloc_opcode [ISSUE_W-1:0], // small opcode field
  input  logic [TAG_W-1:0]                      alloc_src1_tag [ISSUE_W-1:0],
  input  logic [TAG_W-1:0]                      alloc_src2_tag [ISSUE_W-1:0],
  input  logic [31:0]                           alloc_src1_val [ISSUE_W-1:0], // forwarded in dispatch if available
  input  logic [31:0]                           alloc_src2_val [ISSUE_W-1:0],
  input  core_pkg::preg_tag_t                   alloc_dst_phys [ISSUE_W-1:0],
  input  logic [4:0]                            alloc_dst_rob  [ISSUE_W-1:0],
  input  logic [1:0]                            alloc_fu_type  [ISSUE_W-1:0], // 0=ALU,1=BR
  output logic                                  alloc_ok, // all requested allocs succeeded

  // --------------------
  // Wakeup/CDB broadcasts (support up to ISSUE_W broadcasts per cycle)
  input  logic [ISSUE_W-1:0]                    cdb_valid,
  input  logic [TAG_W-1:0]                      cdb_tag   [ISSUE_W-1:0],
  input  logic [31:0]                           cdb_value [ISSUE_W-1:0],

  // --------------------
  // Issue outputs (ALU ports 0..1)
  output logic [ISSUE_W-1:0]                    issue_valid, 
  output logic [3:0]                            issue_opcode [ISSUE_W-1:0],
  output logic [31:0]                           issue_src1_val [ISSUE_W-1:0],
  output logic [31:0]                           issue_src2_val [ISSUE_W-1:0],
  output core_pkg::preg_tag_t                   issue_dst_phys [ISSUE_W-1:0],
  output logic [4:0]                            issue_dst_rob [ISSUE_W-1:0],

  // --------------------
  // Branch issue port (separate)
  output logic                                  br_valid,
  output logic [3:0]                            br_opcode,
  output logic [31:0]                           br_src1_val,
  output logic [31:0]                           br_src2_val,
  output core_pkg::preg_tag_t                   br_dst_phys,
  output logic [4:0]                            br_dst_rob,

  // --------------------
  // Commit from ROB clears RS entries (one or more commits per cycle)
  input  logic [ISSUE_W-1:0]                    commit_valid,
  input  logic [$clog2(core_pkg::ROB_ENTRIES)-1:0] commit_idx [ISSUE_W-1:0], // ROB index corresponding to RS entries (if used)
  input  logic                                  commit_clear_all, // global flush clear

  // status
  output logic [$clog2(ENTRIES+1)-1:0]           free_count
);

  // Internal definitions
  localparam int TAG_BITS = TAG_W;
  localparam int AGE_W = 32; // cycle stamp width

  typedef struct packed {
    logic                   used;        // entry allocated
    logic                   issued;      // already issued (prevent reissue)
    logic                   src1_ready;
    logic                   src2_ready;
    logic [TAG_BITS-1:0]    src1_tag;
    logic [TAG_BITS-1:0]    src2_tag;
    logic [31:0]            src1_val;
    logic [31:0]            src2_val;
    logic [3:0]             opcode;
    core_pkg::preg_tag_t    dst_phys;
    logic [4:0]             dst_rob;
    logic [1:0]             fu_type;     // 0=ALU,1=BR
    logic                   exception;
    logic [AGE_W-1:0]       alloc_stamp; // for oldest-first
  } rs_entry_t;

  rs_entry_t rs_mem [0:ENTRIES-1];

  // cycle counter for stamps
  logic [AGE_W-1:0] cycle_cnt;

  // book-keeping
  integer i;
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      cycle_cnt <= '0;
      for (i = 0; i < ENTRIES; i = i + 1) begin
        rs_mem[i].used <= 1'b0;
        rs_mem[i].issued <= 1'b0;
        rs_mem[i].src1_ready <= 1'b0;
        rs_mem[i].src2_ready <= 1'b0;
        rs_mem[i].src1_tag <= '0;
        rs_mem[i].src2_tag <= '0;
        rs_mem[i].src1_val <= '0;
        rs_mem[i].src2_val <= '0;
        rs_mem[i].opcode <= '0;
        rs_mem[i].dst_phys <= '0;
        rs_mem[i].dst_rob <= '0;
        rs_mem[i].fu_type <= 2'b00;
        rs_mem[i].exception <= 1'b0;
        rs_mem[i].alloc_stamp <= '0;
      end
    end else begin
      cycle_cnt <= cycle_cnt + 1;

      // -------------------------
      // Apply CDB wakeups first (registered implicitly by evaluating current cdb inputs)
      // For each broadcast, scan entries and update ready/value if tag matches and not yet ready.
      for (int b = 0; b < ISSUE_W; b = b + 1) begin
        if (cdb_valid[b]) begin
          for (i = 0; i < ENTRIES; i = i + 1) begin
            if (rs_mem[i].used && !rs_mem[i].issued) begin
              if (!rs_mem[i].src1_ready && (rs_mem[i].src1_tag == cdb_tag[b])) begin
                rs_mem[i].src1_ready <= 1'b1;
                rs_mem[i].src1_val <= cdb_value[b];
              end
              if (!rs_mem[i].src2_ready && (rs_mem[i].src2_tag == cdb_tag[b])) begin
                rs_mem[i].src2_ready <= 1'b1;
                rs_mem[i].src2_val <= cdb_value[b];
              end
            end
          end
        end
      end

      // -------------------------
      // Apply commits/clears from ROB: commit_valid provides ROB indices;
      // we assume some external mapping informs which RS entry corresponds to commit_idx.
      // Simpler: commit_clear_all clears used entries matching commit indices via dst_rob match.
      if (commit_clear_all) begin
        for (i = 0; i < ENTRIES; i = i + 1) begin
          rs_mem[i].used <= 1'b0;
          rs_mem[i].issued <= 1'b0;
        end
      end else begin
        for (int c = 0; c < ISSUE_W; c = c + 1) begin
          if (commit_valid[c]) begin
            // clear entries matching committed ROB index
            for (i = 0; i < ENTRIES; i = i + 1) begin
              if (rs_mem[i].used && (rs_mem[i].dst_rob == commit_idx[c])) begin
                rs_mem[i].used <= 1'b0;
                rs_mem[i].issued <= 1'b0;
              end
            end
          end
        end
      end

      // -------------------------
      // Allocation: allocate up to ISSUE_W entries this cycle. Find first free slots.
      int alloc_done = 0;
      for (int a = 0; a < ISSUE_W; a = a + 1) begin
        if (alloc_en[a]) begin
          int found = -1;
          for (i = 0; i < ENTRIES; i = i + 1) begin
            if (!rs_mem[i].used) begin
              found = i;
              break;
            end
          end
          if (found != -1) begin
            // fill entry
            rs_mem[found].used       <= 1'b1;
            rs_mem[found].issued     <= 1'b0;
            rs_mem[found].src1_ready <= (alloc_src1_tag[a] == '0) ? 1'b1 : 1'b0; // zero register shortcut
            rs_mem[found].src2_ready <= (alloc_src2_tag[a] == '0) ? 1'b1 : 1'b0;
            rs_mem[found].src1_tag   <= alloc_src1_tag[a];
            rs_mem[found].src2_tag   <= alloc_src2_tag[a];
            rs_mem[found].src1_val   <= alloc_src1_val[a];
            rs_mem[found].src2_val   <= alloc_src2_val[a];
            rs_mem[found].opcode     <= alloc_opcode[a];
            rs_mem[found].dst_phys   <= alloc_dst_phys[a];
            rs_mem[found].dst_rob    <= alloc_dst_rob[a];
            rs_mem[found].fu_type    <= alloc_fu_type[a];
            rs_mem[found].exception  <= 1'b0;
            rs_mem[found].alloc_stamp<= cycle_cnt;
            alloc_done = alloc_done + 1;
          end
        end
      end

      // set alloc_ok = 1 if we allocated all requested entries; simple check performed below (combinational)
    end
  end

  // -------------------------
  // Combinational selection logic (oldest-first)
  // Build candidate lists, then choose oldest for ALU ports and branch port.
  function automatic int choose_oldest(input bit [ENTRIES-1:0] mask);
    int best;
    logic [AGE_W-1:0] best_stamp;
    begin
      best = -1;
      best_stamp = {AGE_W{1'b1}};
      for (int j = 0; j < ENTRIES; j = j + 1) begin
        if (mask[j]) begin
          if (rs_mem[j].alloc_stamp < best_stamp) begin
            best_stamp = rs_mem[j].alloc_stamp;
            best = j;
          end
        end
      end
      choose_oldest = best;
    end
  endfunction

  // Build ready masks
  bit [ENTRIES-1:0] alu_ready_mask;
  bit [ENTRIES-1:0] br_ready_mask;
  always_comb begin
    alu_ready_mask = '0;
    br_ready_mask  = '0;
    for (int j = 0; j < ENTRIES; j = j + 1) begin
      if (rs_mem[j].used && !rs_mem[j].issued) begin
        if (rs_mem[j].src1_ready && rs_mem[j].src2_ready) begin
          if (rs_mem[j].fu_type == 2'b00) alu_ready_mask[j] = 1'b1;
          else if (rs_mem[j].fu_type == 2'b01) br_ready_mask[j]  = 1'b1;
        end
      end
    end

    // choose two oldest ALU entries (no duplicate)
    int first_alu = choose_oldest(alu_ready_mask);
    int second_alu = -1;
    if (first_alu != -1) begin
      // mask out first and choose next
      alu_ready_mask[first_alu] = 1'b0;
      second_alu = choose_oldest(alu_ready_mask);
    end

    // choose branch oldest
    int br_idx = choose_oldest(br_ready_mask);

    // default outputs
    for (int p = 0; p < ISSUE_W; p = p + 1) begin
      issue_valid[p] = 1'b0;
      issue_opcode[p] = '0;
      issue_src1_val[p] = '0;
      issue_src2_val[p] = '0;
      issue_dst_phys[p] = '0;
      issue_dst_rob[p] = '0;
    end
    br_valid = 1'b0;
    br_opcode = '0; br_src1_val = '0; br_src2_val = '0; br_dst_phys = '0; br_dst_rob = '0;

    if (first_alu != -1) begin
      issue_valid[0] = 1'b1;
      issue_opcode[0] = rs_mem[first_alu].opcode;
      issue_src1_val[0] = rs_mem[first_alu].src1_val;
      issue_src2_val[0] = rs_mem[first_alu].src2_val;
      issue_dst_phys[0] = rs_mem[first_alu].dst_phys;
      issue_dst_rob[0]  = rs_mem[first_alu].dst_rob;
    end
    if (second_alu != -1) begin
      issue_valid[1] = 1'b1;
      issue_opcode[1] = rs_mem[second_alu].opcode;
      issue_src1_val[1] = rs_mem[second_alu].src1_val;
      issue_src2_val[1] = rs_mem[second_alu].src2_val;
      issue_dst_phys[1] = rs_mem[second_alu].dst_phys;
      issue_dst_rob[1]  = rs_mem[second_alu].dst_rob;
    end
    if (br_idx != -1) begin
      br_valid = 1'b1;
      br_opcode = rs_mem[br_idx].opcode;
      br_src1_val = rs_mem[br_idx].src1_val;
      br_src2_val = rs_mem[br_idx].src2_val;
      br_dst_phys = rs_mem[br_idx].dst_phys;
      br_dst_rob  = rs_mem[br_idx].dst_rob;
    end
  end

  // -------------------------
  // Post-issue: mark entries as issued (prevent reissue) on next clock edge
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      // cleared above
    end else begin
      // mark issued for ALU outputs (find matching entries by matching dst_rob and dst_phys)
      for (int p = 0; p < ISSUE_W; p = p + 1) begin
        if (issue_valid[p]) begin
          for (i = 0; i < ENTRIES; i = i + 1) begin
            if (rs_mem[i].used && !rs_mem[i].issued) begin
              if ((rs_mem[i].dst_rob == issue_dst_rob[p]) && (rs_mem[i].dst_phys == issue_dst_phys[p]) && (rs_mem[i].opcode == issue_opcode[p])) begin
                rs_mem[i].issued <= 1'b1;
              end
            end
          end
        end
      end

      // branch issued marking
      if (br_valid) begin
        for (i = 0; i < ENTRIES; i = i + 1) begin
          if (rs_mem[i].used && !rs_mem[i].issued && (rs_mem[i].dst_rob == br_dst_rob) && (rs_mem[i].dst_phys == br_dst_phys) && (rs_mem[i].opcode == br_opcode)) begin
            rs_mem[i].issued <= 1'b1;
          end
        end
      end
    end
  end

  // -------------------------
  // compute free_count (combinational)
  always_comb begin
    int cnt = 0;
    for (int j = 0; j < ENTRIES; j = j + 1) if (!rs_mem[j].used) cnt = cnt + 1;
    free_count = cnt;
    // alloc_ok logic: true if at least as many free slots as requested
    int reqs = 0; for (int k = 0; k < ISSUE_W; k = k + 1) reqs += (alloc_en[k] ? 1 : 0);
    alloc_ok = (cnt >= reqs);
  end

endmodule
