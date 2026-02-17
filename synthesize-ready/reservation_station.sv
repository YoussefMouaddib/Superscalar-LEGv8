`timescale 1ns/1ps
import core_pkg::*;

module reservation_station #(
    parameter int RS_ENTRIES  = 16,
    parameter int ISSUE_W     = 2,
    parameter int CDB_W       = 2,
    parameter int PHYS_W      = 6
)(
    input  logic                     clk,
    input  logic                     reset,
    
    // NEW: Flush all speculative entries
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

    // CDB broadcast
    input  logic [CDB_W-1:0]         cdb_valid,
    input  logic [CDB_W-1:0][PHYS_W-1:0] cdb_tag,
    input  logic [CDB_W-1:0][31:0]   cdb_value,

    // Issue outputs (NOW REGISTERED)
    output logic [ISSUE_W-1:0]       issue_valid,
    output logic [ISSUE_W-1:0][11:0]  issue_op,
    output logic [ISSUE_W-1:0][PHYS_W-1:0] issue_dst_tag,
    output logic [ISSUE_W-1:0][31:0] issue_src1_val,
    output logic [ISSUE_W-1:0][31:0] issue_src2_val,
    output logic [ISSUE_W-1:0][5:0]  issue_rob_tag
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
    } rs_entry_t;

    rs_entry_t rs_mem [0:RS_ENTRIES-1];

    // Combinational issue selection signals
    logic [ISSUE_W-1:0]       issue_valid_comb;
    logic [ISSUE_W-1:0][11:0] issue_op_comb;
    logic [ISSUE_W-1:0][PHYS_W-1:0] issue_dst_tag_comb;
    logic [ISSUE_W-1:0][31:0] issue_src1_val_comb;
    logic [ISSUE_W-1:0][31:0] issue_src2_val_comb;
    logic [ISSUE_W-1:0][5:0]  issue_rob_tag_comb;
    
    // For clearing: capture what was actually issued
    logic [ISSUE_W-1:0][5:0]  issued_rob_tag_reg;

    // === Combinational Issue Selection ===
    always_comb begin
        automatic rs_entry_t oldest [ISSUE_W];
        automatic int oldest_idx [ISSUE_W];
        automatic logic [RS_ENTRIES-1:0] considered_entries;
        automatic int i, p;
        
        // Initialize
        for (p = 0; p < ISSUE_W; p++) begin
            issue_valid_comb[p] = 1'b0;
            issue_op_comb[p] = '0;
            issue_dst_tag_comb[p] = '0;
            issue_src1_val_comb[p] = '0;
            issue_src2_val_comb[p] = '0;
            issue_rob_tag_comb[p] = '0;
            oldest_idx[p] = -1;
            oldest[p].age = 0;
            oldest[p].valid = 0;
        end

        considered_entries = '0;

        // Select oldest ready entries
        for (p = 0; p < ISSUE_W; p++) begin
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (rs_mem[i].valid && rs_mem[i].src1_ready && rs_mem[i].src2_ready && 
                    !considered_entries[i]) begin
                    if (!issue_valid_comb[p] || (rs_mem[i].age > oldest[p].age)) begin
                        oldest[p] = rs_mem[i];
                        oldest_idx[p] = i;
                        issue_valid_comb[p] = 1'b1;
                    end
                end
            end
            
            if (issue_valid_comb[p] && oldest_idx[p] != -1) begin
                considered_entries[oldest_idx[p]] = 1'b1;
            end
        end

        // Assign outputs from selected entries
        for (p = 0; p < ISSUE_W; p++) begin
            if (issue_valid_comb[p]) begin
                issue_op_comb[p] = oldest[p].opcode;
                issue_dst_tag_comb[p] = oldest[p].dst_tag;
                issue_src1_val_comb[p] = oldest[p].src1_val;
                issue_src2_val_comb[p] = oldest[p].src2_val;
                issue_rob_tag_comb[p] = oldest[p].rob_tag;
            end
        end
    end

    // === Sequential Logic ===
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [RS_ENTRIES-1:0] free_slots;
        automatic logic [RS_ENTRIES-1:0] clear_mask;
        automatic int current_slot;
        automatic int i, a, b, p;
        
        if (reset) begin
            // Reset all RS entries
            for (i = 0; i < RS_ENTRIES; i++) begin
                rs_mem[i].valid <= 1'b0;
                rs_mem[i].src1_ready <= 1'b0;
                rs_mem[i].src2_ready <= 1'b0;
                rs_mem[i].age <= '0;
            end
            
            // Reset issue outputs
            issue_valid <= '0;
            issue_op <= '0;
            issue_dst_tag <= '0;
            issue_src1_val <= '0;
            issue_src2_val <= '0;
            issue_rob_tag <= '0;
            issued_rob_tag_reg <= '0;
            
        end else if (flush_pipeline) begin
            // Flush all speculative entries
            for (i = 0; i < RS_ENTRIES; i++) begin
                rs_mem[i].valid <= 1'b0;
                rs_mem[i].age <= '0;
            end
            issue_valid <= '0;
            
        end else begin
            // ============================================================
            // STEP 1: Register issue outputs (from combinational selection)
            // ============================================================
            issue_valid <= issue_valid_comb;
            issue_op <= issue_op_comb;
            issue_dst_tag <= issue_dst_tag_comb;
            issue_src1_val <= issue_src1_val_comb;
            issue_src2_val <= issue_src2_val_comb;
            issue_rob_tag <= issue_rob_tag_comb;
            
            // Capture rob tags for clearing next cycle
            for (p = 0; p < ISSUE_W; p++) begin
                if (issue_valid_comb[p]) begin
                    issued_rob_tag_reg[p] <= issue_rob_tag_comb[p];
                end
            end
            
            // ============================================================
            // STEP 2: Clear entries that were issued LAST cycle
            // ============================================================
            clear_mask = '0;
            for (p = 0; p < ISSUE_W; p++) begin
                if (issue_valid[p]) begin  // Was something issued last cycle?
                    for (i = 0; i < RS_ENTRIES; i++) begin
                        if (rs_mem[i].valid && rs_mem[i].rob_tag == issued_rob_tag_reg[p]) begin
                            clear_mask[i] = 1'b1;
                        end
                    end
                end
            end
            
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (clear_mask[i]) begin
                    rs_mem[i].valid <= 1'b0;
                    rs_mem[i].age <= '0;
                end
            end

            // ============================================================
            // STEP 3: Find free slots (include being-cleared slots)
            // ============================================================
            for (i = 0; i < RS_ENTRIES; i++) begin
                free_slots[i] = !rs_mem[i].valid || clear_mask[i];
            end

            // ============================================================
            // STEP 4: Allocate new entries
            // ============================================================
            current_slot = 0;
            for (a = 0; a < ISSUE_W; a++) begin
                if (alloc_en[a]) begin
                    // Find next free slot
                    while (current_slot < RS_ENTRIES && !free_slots[current_slot]) begin
                        current_slot++;
                    end
                    if (current_slot < RS_ENTRIES) begin
                        rs_mem[current_slot].valid <= 1'b1;
                        rs_mem[current_slot].dst_tag <= alloc_dst_tag[a];
                        rs_mem[current_slot].src1_tag <= alloc_src1_tag[a];
                        rs_mem[current_slot].src2_tag <= alloc_src2_tag[a];
                        rs_mem[current_slot].src1_val <= alloc_src1_val[a];
                        rs_mem[current_slot].src2_val <= alloc_src2_val[a];
                        rs_mem[current_slot].src1_ready <= alloc_src1_ready[a];
                        rs_mem[current_slot].src2_ready <= alloc_src2_ready[a];
                        rs_mem[current_slot].opcode <= alloc_op[a];
                        rs_mem[current_slot].rob_tag <= alloc_rob_tag[a];
                        rs_mem[current_slot].age <= 5'd0;
                        current_slot++;
                    end
                end
            end

            // ============================================================
            // STEP 5: Wakeup from CDB
            // ============================================================
            for (i = 0; i < RS_ENTRIES; i++) begin
                if (rs_mem[i].valid && !clear_mask[i]) begin
                    // Check CDB for src1
                    if (!rs_mem[i].src1_ready) begin
                        for (b = 0; b < CDB_W; b++) begin
                            if (cdb_valid[b] && (rs_mem[i].src1_tag == cdb_tag[b])) begin
                                rs_mem[i].src1_val <= cdb_value[b];
                                rs_mem[i].src1_ready <= 1'b1;
                            end
                        end
                    end
                    
                    // Check CDB for src2
                    if (!rs_mem[i].src2_ready) begin
                        for (b = 0; b < CDB_W; b++) begin
                            if (cdb_valid[b] && (rs_mem[i].src2_tag == cdb_tag[b])) begin
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
