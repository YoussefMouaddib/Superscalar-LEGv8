`timescale 1ns/1ps
import core_pkg::*;

module reservation_station #(
    parameter int RS_ENTRIES  = 16,  // REDUCED from 32
    parameter int ISSUE_W     = 2,
    parameter int CDB_W       = 2,
    parameter int PHYS_W      = 6
)(
    input  logic                     clk,
    input  logic                     reset,
    
    input  logic                     flush_pipeline,

    // Allocation interface
    input  logic [ISSUE_W-1:0]       alloc_en,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_dst_tag,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_src1_tag,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_src2_tag,
    input  logic [ISSUE_W-1:0][31:0] alloc_src1_val,
    input  logic [ISSUE_W-1:0][31:0] alloc_src2_val,
    input  logic [ISSUE_W-1:0]       alloc_src1_ready,
    input  logic [ISSUE_W-1:0]       alloc_src2_ready,
    input  logic [ISSUE_W-1:0][11:0]  alloc_op,
    input  logic [ISSUE_W-1:0][5:0]  alloc_rob_tag,
    input  logic [ISSUE_W-1:0][31:0] alloc_pc,
    input  logic [ISSUE_W-1:0][31:0] alloc_imm,

    // CDB broadcast
    input  logic [CDB_W-1:0]         cdb_valid,
    input  logic [CDB_W-1:0][PHYS_W-1:0] cdb_tag,
    input  logic [CDB_W-1:0][31:0]   cdb_value,

    // Issue outputs (2-cycle latency)
    output logic [ISSUE_W-1:0]       issue_valid,
    output logic [ISSUE_W-1:0][11:0]  issue_op,
    output logic [ISSUE_W-1:0][PHYS_W-1:0] issue_dst_tag,
    output logic [ISSUE_W-1:0][31:0] issue_src1_val,
    output logic [ISSUE_W-1:0][31:0] issue_src2_val,
    output logic [ISSUE_W-1:0][5:0]  issue_rob_tag,
    output logic [ISSUE_W-1:0][31:0] issue_pc,
    output logic [ISSUE_W-1:0][31:0] issue_imm
);

    typedef struct packed {
        logic valid;
        logic [PHYS_W-1:0] dst_tag;
        logic [PHYS_W-1:0] src1_tag;
        logic [PHYS_W-1:0] src2_tag;
        logic [31:0] src1_val;
        logic [31:0] src2_val;
        logic src1_ready;
        logic src2_ready;
        logic [11:0] opcode;
        logic [5:0] rob_tag;
        logic [4:0] age;
        logic [31:0] pc;      
        logic [31:0] imm;
    } rs_entry_t;

    rs_entry_t rs_mem [0:RS_ENTRIES-1];

    // =========================================================================
    // PIPELINE STAGE 1: Ready Mask + Age Encoding (Cycle N)
    // =========================================================================
    // Instead of 32→1 tree, we do 16→2 groups, then 2→1 final select
    
    typedef struct packed {
        logic valid;
        logic [3:0] idx;  // 4 bits for 16 entries
        logic [4:0] age;
        logic [11:0] opcode;
        logic [PHYS_W-1:0] dst_tag;
        logic [31:0] src1_val;
        logic [31:0] src2_val;
        logic [5:0] rob_tag;
        logic [31:0] pc;
        logic [31:0] imm;
    } select_stage1_t;
    
    select_stage1_t stage1_candidates [ISSUE_W];
    logic stage1_valid;
    
    // Stage 1: Find oldest ready in EACH HALF (parallel 8-way comparisons)
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [RS_ENTRIES-1:0] ready_mask;
        automatic int i, p;
        
        if (reset || flush_pipeline) begin
            for (p = 0; p < ISSUE_W; p++) begin
                stage1_candidates[p].valid <= 1'b0;
                stage1_candidates[p].age <= '0;
                stage1_candidates[p].idx <= '0;
            end
            stage1_valid <= 1'b0;
            
        end else begin
            // Build ready mask (cheap - just AND gates)
            for (i = 0; i < RS_ENTRIES; i++) begin
                ready_mask[i] = rs_mem[i].valid && rs_mem[i].src1_ready && rs_mem[i].src2_ready;
            end
            
            // Port 0: Search entries [0:7] (8-way comparison)
            stage1_candidates[0].valid <= 1'b0;
            stage1_candidates[0].age <= '0;
            for (i = 0; i < 8; i++) begin
                if (ready_mask[i]) begin
                    if (!stage1_candidates[0].valid || rs_mem[i].age > stage1_candidates[0].age) begin
                        stage1_candidates[0].valid <= 1'b1;
                        stage1_candidates[0].idx <= i[3:0];
                        stage1_candidates[0].age <= rs_mem[i].age;
                        stage1_candidates[0].opcode <= rs_mem[i].opcode;
                        stage1_candidates[0].dst_tag <= rs_mem[i].dst_tag;
                        stage1_candidates[0].src1_val <= rs_mem[i].src1_val;
                        stage1_candidates[0].src2_val <= rs_mem[i].src2_val;
                        stage1_candidates[0].rob_tag <= rs_mem[i].rob_tag;
                        stage1_candidates[0].pc <= rs_mem[i].pc;
                        stage1_candidates[0].imm <= rs_mem[i].imm;
                    end
                end
            end
            
            // Port 1: Search entries [8:15] (8-way comparison, parallel with port 0)
            stage1_candidates[1].valid <= 1'b0;
            stage1_candidates[1].age <= '0;
            for (i = 8; i < RS_ENTRIES; i++) begin
                if (ready_mask[i]) begin
                    if (!stage1_candidates[1].valid || rs_mem[i].age > stage1_candidates[1].age) begin
                        stage1_candidates[1].valid <= 1'b1;
                        stage1_candidates[1].idx <= i[3:0];
                        stage1_candidates[1].age <= rs_mem[i].age;
                        stage1_candidates[1].opcode <= rs_mem[i].opcode;
                        stage1_candidates[1].dst_tag <= rs_mem[i].dst_tag;
                        stage1_candidates[1].src1_val <= rs_mem[i].src1_val;
                        stage1_candidates[1].src2_val <= rs_mem[i].src2_val;
                        stage1_candidates[1].rob_tag <= rs_mem[i].rob_tag;
                        stage1_candidates[1].pc <= rs_mem[i].pc;
                        stage1_candidates[1].imm <= rs_mem[i].imm;
                    end
                end
            end
            
            stage1_valid <= 1'b1;
        end
    end
    
    // =========================================================================
    // PIPELINE STAGE 2: Final Selection + Issue (Cycle N+1)
    // =========================================================================
    // Compare the 2 candidates from stage 1, pick oldest, then pick second-oldest
    
    always_ff @(posedge clk or posedge reset) begin
        automatic select_stage1_t winner, runner_up;
        automatic logic both_valid;
        
        if (reset || flush_pipeline) begin
            issue_valid <= '0;
            issue_op <= '0;
            issue_dst_tag <= '0;
            issue_src1_val <= '0;
            issue_src2_val <= '0;
            issue_rob_tag <= '0;
            issue_pc <= '0;
            issue_imm <= '0;
            
        end else if (stage1_valid) begin
            both_valid = stage1_candidates[0].valid && stage1_candidates[1].valid;
            
            // Determine winner (oldest) and runner-up
            if (both_valid) begin
                if (stage1_candidates[0].age > stage1_candidates[1].age) begin
                    winner = stage1_candidates[0];
                    runner_up = stage1_candidates[1];
                end else begin
                    winner = stage1_candidates[1];
                    runner_up = stage1_candidates[0];
                end
            end else if (stage1_candidates[0].valid) begin
                winner = stage1_candidates[0];
                runner_up.valid = 1'b0;
            end else if (stage1_candidates[1].valid) begin
                winner = stage1_candidates[1];
                runner_up.valid = 1'b0;
            end else begin
                winner.valid = 1'b0;
                runner_up.valid = 1'b0;
            end
            
            // Issue port 0: Winner
            issue_valid[0] <= winner.valid;
            if (winner.valid) begin
                issue_op[0] <= winner.opcode;
                issue_dst_tag[0] <= winner.dst_tag;
                issue_src1_val[0] <= winner.src1_val;
                issue_src2_val[0] <= winner.src2_val;
                issue_rob_tag[0] <= winner.rob_tag;
                issue_pc[0] <= winner.pc;
                issue_imm[0] <= winner.imm;
            end
            
            // Issue port 1: Runner-up
            issue_valid[1] <= runner_up.valid;
            if (runner_up.valid) begin
                issue_op[1] <= runner_up.opcode;
                issue_dst_tag[1] <= runner_up.dst_tag;
                issue_src1_val[1] <= runner_up.src1_val;
                issue_src2_val[1] <= runner_up.src2_val;
                issue_rob_tag[1] <= runner_up.rob_tag;
                issue_pc[1] <= runner_up.pc;
                issue_imm[1] <= runner_up.imm;
            end
            
        end else begin
            issue_valid <= '0;
        end
    end
    
    // =========================================================================
    // RS Entry Management (runs every cycle, parallel with selection)
    // =========================================================================
    
    // Allocation signals
    logic [RS_ENTRIES-1:0] free_mask;
    logic [RS_ENTRIES-1:0] mask_after_port0;
    logic [ISSUE_W-1:0][3:0] alloc_slot_idx;  // 4 bits for 16 entries
    logic [ISSUE_W-1:0] alloc_slot_valid;
    
    // Combinational allocation priority encoder
    always_comb begin
        automatic int i, a;
        
        // Build free mask
        free_mask = '0;
        for (i = 0; i < RS_ENTRIES; i++) begin
            if (!rs_mem[i].valid) begin
                free_mask[i] = 1'b1;
            end
        end
        
        // Port 0: Find first free
        alloc_slot_valid[0] = 1'b0;
        alloc_slot_idx[0] = '0;
        if (alloc_en[0]) begin
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (free_mask[i] && !alloc_slot_valid[0]) begin
                    alloc_slot_idx[0] = i[3:0];
                    alloc_slot_valid[0] = 1'b1;
                end
            end
        end
        
        // Mask for port 1 (exclude port 0's allocation)
        mask_after_port0 = free_mask;
        if (alloc_en[0] && alloc_slot_valid[0]) begin
            mask_after_port0[alloc_slot_idx[0]] = 1'b0;
        end
        
        // Port 1: Find first free after port 0
        alloc_slot_valid[1] = 1'b0;
        alloc_slot_idx[1] = '0;
        if (alloc_en[1]) begin
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (mask_after_port0[i] && !alloc_slot_valid[1]) begin
                    alloc_slot_idx[1] = i[3:0];
                    alloc_slot_valid[1] = 1'b1;
                end
            end
        end
    end
    
    // Sequential: Allocate, Clear, Wakeup, Age
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [RS_ENTRIES-1:0] clear_mask;
        automatic int i, a, b;
        
        if (reset) begin
            for (i = 0; i < RS_ENTRIES; i++) begin
                rs_mem[i].valid <= 1'b0;
                rs_mem[i].src1_ready <= 1'b0;
                rs_mem[i].src2_ready <= 1'b0;
                rs_mem[i].age <= '0;
            end
            
        end else if (flush_pipeline) begin
            for (i = 0; i < RS_ENTRIES; i++) begin
                rs_mem[i].valid <= 1'b0;
                rs_mem[i].age <= '0;
            end
            
        end else begin
            // Clear issued entries (2-cycle delay due to pipeline)
            clear_mask = '0;
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (rs_mem[i].valid) begin
                    // Check if this ROB tag was issued 2 cycles ago
                    if (issue_valid[0] && rs_mem[i].rob_tag == issue_rob_tag[0]) begin
                        clear_mask[i] = 1'b1;
                    end
                    if (issue_valid[1] && rs_mem[i].rob_tag == issue_rob_tag[1]) begin
                        clear_mask[i] = 1'b1;
                    end
                end
            end
            
            // Apply clears
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (clear_mask[i]) begin
                    rs_mem[i].valid <= 1'b0;
                    rs_mem[i].age <= '0;
                end
            end
            
            // Allocate new entries
            for (a = 0; a < ISSUE_W; a++) begin
                if (alloc_en[a] && alloc_slot_valid[a]) begin
                    automatic int slot = alloc_slot_idx[a];
                    rs_mem[slot].valid <= 1'b1;
                    rs_mem[slot].dst_tag <= alloc_dst_tag[a];
                    rs_mem[slot].src1_tag <= alloc_src1_tag[a];
                    rs_mem[slot].src2_tag <= alloc_src2_tag[a];
                    rs_mem[slot].src1_val <= alloc_src1_val[a];
                    rs_mem[slot].src2_val <= alloc_src2_val[a];
                    rs_mem[slot].src1_ready <= alloc_src1_ready[a];
                    rs_mem[slot].src2_ready <= alloc_src2_ready[a];
                    rs_mem[slot].opcode <= alloc_op[a];
                    rs_mem[slot].rob_tag <= alloc_rob_tag[a];
                    rs_mem[slot].age <= 5'd0;
                    rs_mem[slot].pc <= alloc_pc[a];
                    rs_mem[slot].imm <= alloc_imm[a];
                end
            end
            
            // CDB wakeup + age increment
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (rs_mem[i].valid && !clear_mask[i]) begin
                    // Wakeup src1
                    if (!rs_mem[i].src1_ready) begin
                        for (b = 0; b < CDB_W; b++) begin
                            if (cdb_valid[b] && rs_mem[i].src1_tag == cdb_tag[b]) begin
                                rs_mem[i].src1_val <= cdb_value[b];
                                rs_mem[i].src1_ready <= 1'b1;
                            end
                        end
                    end
                    
                    // Wakeup src2
                    if (!rs_mem[i].src2_ready) begin
                        for (b = 0; b < CDB_W; b++) begin
                            if (cdb_valid[b] && rs_mem[i].src2_tag == cdb_tag[b]) begin
                                rs_mem[i].src2_val <= cdb_value[b];
                                rs_mem[i].src2_ready <= 1'b1;
                            end
                        end
                    end
                    
                    // Increment age
                    rs_mem[i].age <= rs_mem[i].age + 1'b1;
                end
            end
        end
    end

endmodule
