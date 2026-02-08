`timescale 1ns/1ps
import core_pkg::*;

module rob #(
  parameter int ROB_SIZE = core_pkg::ROB_ENTRIES
)(
  input  logic                    clk,
  input  logic                    reset,

  // ---------- Allocation (from rename/dispatch)
  // alloc_en[i] = request to allocate an entry for the i-th packet (0..1)
  input  logic [core_pkg::ISSUE_WIDTH-1:0] alloc_en,                 // ISSUE_WIDTH==2
  input  logic [4:0]                        alloc_arch_rd [core_pkg::ISSUE_WIDTH],
  input  core_pkg::preg_tag_t               alloc_phys_rd [core_pkg::ISSUE_WIDTH],
  output logic                              alloc_ok,                // high if allocation(s) succeeded (not full)
  // optional: return allocated ROB index(s) for tracking/wakeup (index0 primary, index1 secondary)
  output logic [$clog2(ROB_SIZE)-1:0]       alloc_idx  [core_pkg::ISSUE_WIDTH],

  // ---------- Wakeup / Mark ready (from execution result / CDB)
  input  logic                    mark_ready_en,
  input  logic [$clog2(ROB_SIZE)-1:0] mark_ready_idx,
  input  logic                    mark_ready_val,   // 1 = ready (completed)
  input  logic                    mark_exception,   // 1 = exception on this entry

  // ---------- Commit outputs (to architectural state & freelist)
  // commit_valid[i] indicates commit slot i has valid commit info this cycle
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_valid,
  output logic [4:0]                      commit_arch_rd [core_pkg::ISSUE_WIDTH],
  output core_pkg::preg_tag_t             commit_phys_rd [core_pkg::ISSUE_WIDTH],
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_exception, // exception flags for commit slots

  // ---------- Status / control
  output logic                    rob_full,
  output logic                    rob_almost_full,   // e.g., near capacity
  input  logic                    flush_en,         // synchronous flush/recovery
  input  logic [$clog2(ROB_SIZE)-1:0] flush_ptr      // new head/tail pointer after flush
);

  // local sizes
  localparam int IDX_BITS = $clog2(ROB_SIZE);
  localparam int ISSUE_W = core_pkg::ISSUE_WIDTH;

  // ROB entry definition
  typedef struct packed {
    logic                   valid;
    logic                   ready;
    logic [4:0]             arch_rd;
    core_pkg::preg_tag_t    phys_rd;
    logic                   exception;
  } rob_entry_t;

  // storage array
  rob_entry_t rob_mem [0:ROB_SIZE-1];

  // head = commit pointer, tail = next allocate pointer
  logic [IDX_BITS-1:0] head;
  logic [IDX_BITS-1:0] tail;
  integer              occupancy; // number of valid entries

  // helpers for modular arithmetic
  function automatic logic [$clog2(ROB_SIZE)-1:0] incr_idx(input logic [$clog2(ROB_SIZE)-1:0] idx, input int inc);
    logic [$clog2(ROB_SIZE)-1:0] tmp;
    begin
      tmp = (idx + inc) % ROB_SIZE;
      incr_idx = tmp;
    end
  endfunction

  // Initialize / reset
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      head <= '0;
      tail <= '0;
      occupancy <= 0;
      alloc_ok <= 0;
      for (int i = 0; i < ROB_SIZE; i++) begin
        rob_mem[i].valid     <= 1'b0;
        rob_mem[i].ready     <= 1'b0;
        rob_mem[i].arch_rd   <= '0;
        rob_mem[i].phys_rd   <= '0;
        rob_mem[i].exception <= 1'b0;
      end
    end else begin
      // Declare all automatic variables at the beginning
      automatic int alloc_count;
      automatic int free_slots;
      automatic int reqs;
      automatic int cur_tail;
      automatic int commit_slots;
      automatic int look_idx;
      automatic int k, j;
      
      // ---------- Flush handling (synchronous)
      if (flush_en) begin
        head <= flush_ptr;
        tail <= flush_ptr;
        occupancy <= 0;
        // invalidate entries
        for (int i = 0; i < ROB_SIZE; i++) begin
          rob_mem[i].valid     <= 1'b0;
          rob_mem[i].ready     <= 1'b0;
          rob_mem[i].exception <= 1'b0;
        end
      end else begin
        // ---------- Process mark_ready (wakeup from execution)
        if (mark_ready_en) begin
          // only update if entry is valid
          if (rob_mem[mark_ready_idx].valid) begin
            if (mark_ready_val) rob_mem[mark_ready_idx].ready <= 1'b1;
            if (mark_exception)  rob_mem[mark_ready_idx].exception <= 1'b1;
          end
        end

        // ---------- Allocation (up to ISSUE_WIDTH entries)
        // Note: allocate entries sequentially starting at tail. If not enough space, skip allocations.
        alloc_count = 0;
        alloc_ok <= 1'b0;
        // prepare default returned indices
        for (k = 0; k < ISSUE_W; k++) alloc_idx[k] <= '0;

        if (alloc_en != 0) begin
          // compute available slots
          free_slots = ROB_SIZE - occupancy;
          // count requested allocs (popcount of alloc_en)
          reqs = 0;
          for (k = 0; k < ISSUE_W; k++) if (alloc_en[k]) reqs++;
          if (reqs <= free_slots) begin
            // perform allocations
            cur_tail = tail;
            for (k = 0; k < ISSUE_W; k++) begin
              if (alloc_en[k]) begin
                rob_mem[cur_tail].valid   <= 1'b1;
                rob_mem[cur_tail].ready   <= 1'b0;
                rob_mem[cur_tail].arch_rd <= alloc_arch_rd[k];
                rob_mem[cur_tail].phys_rd <= alloc_phys_rd[k];
                rob_mem[cur_tail].exception<= 1'b0;
                alloc_idx[k] <= cur_tail;
                cur_tail = (cur_tail + 1) % ROB_SIZE;
                alloc_count++;
              end else begin
                alloc_idx[k] <= '0;
              end
            end
            tail <= cur_tail;
            occupancy <= occupancy + alloc_count;
            alloc_ok <= 1'b1;
          end else begin
            // Not enough space: allocation fails (alloc_ok = 0)
            alloc_ok <= 1'b0;
          end
        end

        // ---------- Commit (up to ISSUE_WIDTH entries)
        // produce up to ISSUE_WIDTH commits if head entries are valid && ready
        // commit slot 0:
        for (j = 0; j < ISSUE_W; j++) begin
          commit_valid[j] <= 1'b0;
          commit_arch_rd[j] <= '0;
          commit_phys_rd[j] <= '0;
          commit_exception[j] <= 1'b0;
        end

        commit_slots = 0;
        look_idx = head;
        for (j = 0; j < ISSUE_W; j++) begin
          if (occupancy > 0) begin
            if (rob_mem[look_idx].valid && rob_mem[look_idx].ready) begin
              // produce commit j
              commit_valid[j] <= 1'b1;
              commit_arch_rd[j] <= rob_mem[look_idx].arch_rd;
              commit_phys_rd[j] <= rob_mem[look_idx].phys_rd;
              commit_exception[j] <= rob_mem[look_idx].exception;
              // mark entry invalid (committed)
              rob_mem[look_idx].valid <= 1'b0;
              rob_mem[look_idx].ready <= 1'b0;
              rob_mem[look_idx].exception <= 1'b0;
              look_idx = (look_idx + 1) % ROB_SIZE;
              commit_slots++;
            end else begin
              // cannot commit further
              break;
            end
          end else begin
            break;
          end
        end
        // advance head and occupancy by commit_slots
        if (commit_slots > 0) begin
          head <= (head + commit_slots) % ROB_SIZE;
          occupancy <= occupancy - commit_slots;
        end

      end // not flush_en
    end // not reset
  end // always_ff

  // status flags
  always_comb begin
    rob_full = (occupancy >= ROB_SIZE);
    // almost full when fewer slots than ISSUE_WIDTH
    rob_almost_full = (ROB_SIZE - occupancy) < core_pkg::ISSUE_WIDTH;
  end

endmodule
