`timescale 1ns/1ps
import core_pkg::*;

module rob #(
  parameter int ROB_SIZE = core_pkg::ROB_ENTRIES
)(
  input  logic                    clk,
  input  logic                    reset,

  // ---------- Allocation (from rename/dispatch)
  input  logic [core_pkg::ISSUE_WIDTH-1:0] alloc_en,
  input  logic [4:0]                        alloc_arch_rd [core_pkg::ISSUE_WIDTH],
  input  core_pkg::preg_tag_t               alloc_phys_rd [core_pkg::ISSUE_WIDTH],
  
  // NEW: Instruction metadata for commit stage
  input  logic [core_pkg::ISSUE_WIDTH-1:0]  alloc_is_store,
  input  logic [core_pkg::ISSUE_WIDTH-1:0]  alloc_is_load,
  input  logic [core_pkg::ISSUE_WIDTH-1:0]  alloc_is_branch,
  input  logic [31:0]                        alloc_pc [core_pkg::ISSUE_WIDTH],
  
  output logic                              alloc_ok,
  output logic [$clog2(ROB_SIZE)-1:0]       alloc_idx  [core_pkg::ISSUE_WIDTH],

  // ---------- Wakeup / Mark ready (from execution result / CDB)
  input  logic                    mark_ready_en,
  input  logic [$clog2(ROB_SIZE)-1:0] mark_ready_idx,
  input  logic                    mark_ready_val,
  input  logic                    mark_exception,

  // ---------- Commit outputs (to architectural state & freelist)
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_valid,
  output logic [4:0]                      commit_arch_rd [core_pkg::ISSUE_WIDTH],
  output core_pkg::preg_tag_t             commit_phys_rd [core_pkg::ISSUE_WIDTH],
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_exception,
  
  // NEW: Commit metadata outputs
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_is_store,
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_is_load,
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_is_branch,
  output logic [31:0]                      commit_pc [core_pkg::ISSUE_WIDTH],

  // ---------- Status / control
  output logic                    rob_full,
  output logic                    rob_almost_full,
  input  logic                    flush_en,
  input  logic [$clog2(ROB_SIZE)-1:0] flush_ptr
);

  // local sizes
  localparam int IDX_BITS = $clog2(ROB_SIZE);
  localparam int ISSUE_W = core_pkg::ISSUE_WIDTH;

  // ROB entry definition - ENHANCED with instruction metadata
  typedef struct packed {
    logic                   valid;
    logic                   ready;
    logic [4:0]             arch_rd;
    core_pkg::preg_tag_t    phys_rd;
    logic                   exception;
    // NEW FIELDS:
    logic                   is_store;
    logic                   is_load;
    logic                   is_branch;
    logic [31:0]            pc;
  } rob_entry_t;

  // storage array
  rob_entry_t rob_mem [0:ROB_SIZE-1];

  // head = commit pointer, tail = next allocate pointer
  logic [IDX_BITS-1:0] head;
  logic [IDX_BITS-1:0] tail;
  integer              occupancy;

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
        rob_mem[i].is_store  <= 1'b0;
        rob_mem[i].is_load   <= 1'b0;
        rob_mem[i].is_branch <= 1'b0;
        rob_mem[i].pc        <= '0;
      end
    end else begin
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
        for (int i = 0; i < ROB_SIZE; i++) begin
          rob_mem[i].valid     <= 1'b0;
          rob_mem[i].ready     <= 1'b0;
          rob_mem[i].exception <= 1'b0;
        end
      end else begin
        // ---------- Process mark_ready (wakeup from execution)
        if (mark_ready_en) begin
          if (rob_mem[mark_ready_idx].valid) begin
            if (mark_ready_val) rob_mem[mark_ready_idx].ready <= 1'b1;
            if (mark_exception)  rob_mem[mark_ready_idx].exception <= 1'b1;
          end
        end

        // ---------- Allocation (up to ISSUE_WIDTH entries)
        alloc_count = 0;
        alloc_ok <= 1'b0;
        for (k = 0; k < ISSUE_W; k++) alloc_idx[k] <= '0;

        if (alloc_en != 0) begin
          free_slots = ROB_SIZE - occupancy;
          reqs = 0;
          for (k = 0; k < ISSUE_W; k++) if (alloc_en[k]) reqs++;
          
          if (reqs <= free_slots) begin
            cur_tail = tail;
            for (k = 0; k < ISSUE_W; k++) begin
              if (alloc_en[k]) begin
                rob_mem[cur_tail].valid     <= 1'b1;
                rob_mem[cur_tail].ready     <= 1'b0;
                rob_mem[cur_tail].arch_rd   <= alloc_arch_rd[k];
                rob_mem[cur_tail].phys_rd   <= alloc_phys_rd[k];
                rob_mem[cur_tail].exception <= 1'b0;
                // NEW: Store instruction metadata
                rob_mem[cur_tail].is_store  <= alloc_is_store[k];
                rob_mem[cur_tail].is_load   <= alloc_is_load[k];
                rob_mem[cur_tail].is_branch <= alloc_is_branch[k];
                rob_mem[cur_tail].pc        <= alloc_pc[k];
                
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
            alloc_ok <= 1'b0;
          end
        end

        // ---------- Commit (up to ISSUE_WIDTH entries)
        for (j = 0; j < ISSUE_W; j++) begin
          commit_valid[j] <= 1'b0;
          commit_arch_rd[j] <= '0;
          commit_phys_rd[j] <= '0;
          commit_exception[j] <= 1'b0;
          commit_is_store[j] <= 1'b0;
          commit_is_load[j] <= 1'b0;
          commit_is_branch[j] <= 1'b0;
          commit_pc[j] <= '0;
        end

        commit_slots = 0;
        look_idx = head;
        for (j = 0; j < ISSUE_W; j++) begin
          if (occupancy > 0) begin
            if (rob_mem[look_idx].valid && rob_mem[look_idx].ready) begin
              // Produce commit j
              commit_valid[j] <= 1'b1;
              commit_arch_rd[j] <= rob_mem[look_idx].arch_rd;
              commit_phys_rd[j] <= rob_mem[look_idx].phys_rd;
              commit_exception[j] <= rob_mem[look_idx].exception;
              // NEW: Pass instruction metadata to commit stage
              commit_is_store[j] <= rob_mem[look_idx].is_store;
              commit_is_load[j] <= rob_mem[look_idx].is_load;
              commit_is_branch[j] <= rob_mem[look_idx].is_branch;
              commit_pc[j] <= rob_mem[look_idx].pc;
              
              // Mark entry invalid (committed)
              rob_mem[look_idx].valid <= 1'b0;
              rob_mem[look_idx].ready <= 1'b0;
              rob_mem[look_idx].exception <= 1'b0;
              look_idx = (look_idx + 1) % ROB_SIZE;
              commit_slots++;
            end else begin
              break;
            end
          end else begin
            break;
          end
        end
        
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
    rob_almost_full = (ROB_SIZE - occupancy) < core_pkg::ISSUE_WIDTH;
  end

endmodule
