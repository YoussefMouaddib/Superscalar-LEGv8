`timescale 1ns/1ps
import core_pkg::*;

module rob #(
  parameter int ROB_SIZE = core_pkg::ROB_ENTRIES
)(
  input  logic                    clk,
  input  logic                    reset,

  // ---------- Allocation (from rename/dispatch)
  input  logic [core_pkg::ISSUE_WIDTH-1:0] alloc_en,
  input  logic [1:0][4:0]                        alloc_arch_rd,
  input  core_pkg::preg_tag_t [1:0]               alloc_phys_rd,
  
  // Instruction metadata
  input  logic [core_pkg::ISSUE_WIDTH-1:0]  alloc_is_store,
  input  logic [core_pkg::ISSUE_WIDTH-1:0]  alloc_is_load,
  input  logic [core_pkg::ISSUE_WIDTH-1:0]  alloc_is_branch,
  input  logic [1:0][31:0]                        alloc_pc ,
  
  output logic                              alloc_ok,
  output logic [1:0][$clog2(ROB_SIZE)-1:0]       alloc_idx  ,

  // ---------- Wakeup / Mark ready
  input  logic                    mark_ready_en,
  input  logic [$clog2(ROB_SIZE)-1:0] mark_ready_idx,
  input  logic                    mark_ready_val,
  input  logic                    mark_exception,

  input  logic                    mark_ready_en1,
  input  logic [$clog2(ROB_SIZE)-1:0] mark_ready_idx1,
  input  logic                    mark_ready_val1,
  input  logic                    mark_exception1,
  
  // NEW: Branch outcome update (from branch execution)
  input  logic                    branch_outcome_en,
  input  logic [$clog2(ROB_SIZE)-1:0] branch_outcome_idx,
  input  logic                    branch_outcome_taken,
  input  logic [31:0]             branch_outcome_target,
  input  logic                    branch_outcome_is_call,
  input  logic                    branch_outcome_is_return,

  // ---------- Commit outputs
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_valid,
  output logic [1:0][4:0]                      commit_arch_rd ,
  output core_pkg::preg_tag_t [1:0]            commit_phys_rd ,
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_exception,
  
  // ADDED: ROB index output for each commit slot
  output logic [1:0][$clog2(ROB_SIZE)-1:0]     commit_rob_idx ,
  
  // Commit metadata
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_is_store,
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_is_load,
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_is_branch,
  output logic [1:0][31:0]                      commit_pc ,
  
  // NEW: Branch outcome for predictor update
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_branch_taken,
  output logic [1:0][31:0]                      commit_branch_target ,
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_branch_is_call,
  output logic [core_pkg::ISSUE_WIDTH-1:0] commit_branch_is_return,

  // ---------- Status / control
  output logic                    rob_full,
  output logic                    rob_almost_full,
  input  logic                    flush_en,
  input  logic [$clog2(ROB_SIZE)-1:0] flush_ptr
);

  localparam int IDX_BITS = $clog2(ROB_SIZE);
  localparam int ISSUE_W = core_pkg::ISSUE_WIDTH;

  // ROB entry definition - ENHANCED with branch outcome
  typedef struct packed {
    logic                   valid;
    logic                   ready;
    logic [4:0]             arch_rd;
    core_pkg::preg_tag_t    phys_rd;
    logic                   exception;
    logic                   is_store;
    logic                   is_load;
    logic                   is_branch;
    logic [31:0]            pc;
    // NEW: Branch outcome fields
    logic                   branch_taken;
    logic [31:0]            branch_target;
    logic                   branch_is_call;
    logic                   branch_is_return;
  } rob_entry_t;

  rob_entry_t rob_mem [0:ROB_SIZE-1];
  logic [IDX_BITS-1:0] head;
  logic [IDX_BITS-1:0] tail;
  integer              occupancy;

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
        rob_mem[i].branch_taken <= 1'b0;
        rob_mem[i].branch_target <= '0;
        rob_mem[i].branch_is_call <= 1'b0;
        rob_mem[i].branch_is_return <= 1'b0;
      end
    end else begin
      automatic int alloc_count;
      automatic int free_slots;
      automatic int reqs;
      automatic int cur_tail;
      automatic int commit_slots;
      automatic int look_idx;
      automatic int k, j;
      
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
        // ---------- Process mark_ready
        if (mark_ready_en) begin
          if (rob_mem[mark_ready_idx].valid) begin
            if (mark_ready_val) rob_mem[mark_ready_idx].ready <= 1'b1;
            if (mark_exception)  rob_mem[mark_ready_idx].exception <= 1'b1;
          end
        end
        // ---------- Process mark_ready PORT 1 - ADD THIS
        if (mark_ready_en1) begin
          if (rob_mem[mark_ready_idx1].valid) begin
            if (mark_ready_val1) rob_mem[mark_ready_idx1].ready <= 1'b1;
            if (mark_exception1)  rob_mem[mark_ready_idx1].exception <= 1'b1;
          end
        end
        
        // ---------- NEW: Process branch outcome
        if (branch_outcome_en) begin
          if (rob_mem[branch_outcome_idx].valid) begin
            rob_mem[branch_outcome_idx].branch_taken <= branch_outcome_taken;
            rob_mem[branch_outcome_idx].branch_target <= branch_outcome_target;
            rob_mem[branch_outcome_idx].branch_is_call <= branch_outcome_is_call;
            rob_mem[branch_outcome_idx].branch_is_return <= branch_outcome_is_return;
          end
        end

        // ---------- Allocation
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
                rob_mem[cur_tail].is_store  <= alloc_is_store[k];
                rob_mem[cur_tail].is_load   <= alloc_is_load[k];
                rob_mem[cur_tail].is_branch <= alloc_is_branch[k];
                rob_mem[cur_tail].pc        <= alloc_pc[k];
                // Initialize branch fields (will be updated by branch_ex)
                rob_mem[cur_tail].branch_taken <= 1'b0;
                rob_mem[cur_tail].branch_target <= '0;
                rob_mem[cur_tail].branch_is_call <= 1'b0;
                rob_mem[cur_tail].branch_is_return <= 1'b0;
                
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

        // ---------- Commit
        for (j = 0; j < ISSUE_W; j++) begin
          commit_valid[j] <= 1'b0;
          commit_arch_rd[j] <= '0;
          commit_phys_rd[j] <= '0;
          commit_exception[j] <= 1'b0;
          commit_is_store[j] <= 1'b0;
          commit_is_load[j] <= 1'b0;
          commit_is_branch[j] <= 1'b0;
          commit_pc[j] <= '0;
          commit_branch_taken[j] <= 1'b0;
          commit_branch_target[j] <= '0;
          commit_branch_is_call[j] <= 1'b0;
          commit_branch_is_return[j] <= 1'b0;
          commit_rob_idx[j] <= '0;  // ADDED: Initialize ROB index output
        end

        commit_slots = 0;
        look_idx = head;
        for (j = 0; j < ISSUE_W; j++) begin
          if (occupancy > 0) begin
            if (rob_mem[look_idx].valid && rob_mem[look_idx].ready) begin
              commit_valid[j] <= 1'b1;
              commit_arch_rd[j] <= rob_mem[look_idx].arch_rd;
              commit_phys_rd[j] <= rob_mem[look_idx].phys_rd;
              commit_exception[j] <= rob_mem[look_idx].exception;
              commit_is_store[j] <= rob_mem[look_idx].is_store;
              commit_is_load[j] <= rob_mem[look_idx].is_load;
              commit_is_branch[j] <= rob_mem[look_idx].is_branch;
              commit_pc[j] <= rob_mem[look_idx].pc;
              // NEW: Pass branch outcome to commit
              commit_branch_taken[j] <= rob_mem[look_idx].branch_taken;
              commit_branch_target[j] <= rob_mem[look_idx].branch_target;
              commit_branch_is_call[j] <= rob_mem[look_idx].branch_is_call;
              commit_branch_is_return[j] <= rob_mem[look_idx].branch_is_return;
              
              // ADDED: Output actual ROB index
              commit_rob_idx[j] <= look_idx[$clog2(ROB_SIZE)-1:0];
              
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

      end
    end
  end

  always_comb begin
    rob_full = (occupancy >= ROB_SIZE);
    rob_almost_full = (ROB_SIZE - occupancy) < core_pkg::ISSUE_WIDTH;
  end

endmodule
