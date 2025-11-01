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

    // Allocation interface
    input  logic [ISSUE_W-1:0]       alloc_en,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_dst_tag,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_src1_tag,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0] alloc_src2_tag,
    input  logic [ISSUE_W-1:0][63:0] alloc_src1_val,
    input  logic [ISSUE_W-1:0][63:0] alloc_src2_val,
    input  logic [ISSUE_W-1:0]       alloc_src1_ready,
    input  logic [ISSUE_W-1:0]       alloc_src2_ready,
    input  logic [ISSUE_W-1:0][7:0]  alloc_op,
    input  logic [ISSUE_W-1:0][5:0]  alloc_rob_tag,

    // CDB broadcast (registered)
    input  logic [CDB_W-1:0]         cdb_valid,
    input  logic [CDB_W-1:0][PHYS_W-1:0] cdb_tag,
    input  logic [CDB_W-1:0][63:0]   cdb_value,

    // Issue outputs
    output logic [ISSUE_W-1:0]       issue_valid,
    output logic [ISSUE_W-1:0][7:0]  issue_op,
    output logic [ISSUE_W-1:0][PHYS_W-1:0] issue_dst_tag,
    output logic [ISSUE_W-1:0][63:0] issue_src1_val,
    output logic [ISSUE_W-1:0][63:0] issue_src2_val,
    output logic [ISSUE_W-1:0][5:0]  issue_rob_tag
);

    typedef struct packed {
        logic valid;
        logic [PHYS_W-1:0] dst_tag;
        logic [PHYS_W-1:0] src1_tag;
        logic [PHYS_W-1:0] src2_tag;
        logic [63:0] src1_val;
        logic [63:0] src2_val;
        logic src1_ready;
        logic src2_ready;
        logic [7:0] opcode;
        logic [5:0] rob_tag;
        logic [4:0] age;  // Reduced from 8 to 5 bits (sufficient for 16 entries)
    } rs_entry_t;

    rs_entry_t rs_mem [RS_ENTRIES-1:0];

    // === Register CDB Inputs (1-cycle latency) ===
    logic [CDB_W-1:0]         cdb_valid_ff;
    logic [CDB_W-1:0][PHYS_W-1:0] cdb_tag_ff;
    logic [CDB_W-1:0][63:0]   cdb_value_ff;

    always_ff @(posedge clk) begin
        cdb_valid_ff <= cdb_valid;
        cdb_tag_ff   <= cdb_tag;
        cdb_value_ff <= cdb_value;
    end

    // === Allocation Logic ===
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < RS_ENTRIES; i++) begin
                rs_mem[i].valid <= 1'b0;
                rs_mem[i].age   <= 0;
            end
        end else begin
            // Find free slots in parallel for all allocation requests
            logic [RS_ENTRIES-1:0] free_slots;
            for (int i = 0; i < RS_ENTRIES; i++) begin
                free_slots[i] = !rs_mem[i].valid;
            end

            for (int a = 0; a < ISSUE_W; a++) begin
                if (alloc_en[a]) begin
                    automatic int found = -1;
                    // Find first free slot for this allocation port
                    for (int i = 0; i < RS_ENTRIES; i++) begin
                        if (free_slots[i] && found == -1) begin
                            found = i;
                            free_slots[i] = 1'b0; // Mark as allocated
                        end
                    end

                    if (found != -1) begin
                        rs_mem[found].valid       <= 1'b1;
                        rs_mem[found].dst_tag     <= alloc_dst_tag[a];
                        rs_mem[found].src1_tag    <= alloc_src1_tag[a];
                        rs_mem[found].src2_tag    <= alloc_src2_tag[a];
                        rs_mem[found].src1_val    <= alloc_src1_val[a];
                        rs_mem[found].src2_val    <= alloc_src2_val[a];
                        rs_mem[found].src1_ready  <= alloc_src1_ready[a];
                        rs_mem[found].src2_ready  <= alloc_src2_ready[a];
                        rs_mem[found].opcode      <= alloc_op[a];
                        rs_mem[found].rob_tag     <= alloc_rob_tag[a];
                        rs_mem[found].age         <= 5'd0;
                    end
                end
            end

            // === Age Update ===
            for (int i = 0; i < RS_ENTRIES; i++) begin
                if (rs_mem[i].valid) begin
                    rs_mem[i].age <= rs_mem[i].age + 1'b1;
                end
            end
        end
    end

    // === Operand Wakeup from CDB (Registered) ===
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (rs_mem[i].valid) begin
                for (int b = 0; b < CDB_W; b++) begin
                    if (cdb_valid_ff[b] && (rs_mem[i].src1_tag == cdb_tag_ff[b])) begin
                        rs_mem[i].src1_val   <= cdb_value_ff[b];
                        rs_mem[i].src1_ready <= 1'b1;
                    end
                    if (cdb_valid_ff[b] && (rs_mem[i].src2_tag == cdb_tag_ff[b])) begin
                        rs_mem[i].src2_val   <= cdb_value_ff[b];
                        rs_mem[i].src2_ready <= 1'b1;
                    end
                end
            end
        end
    end

    // === Issue Selection (Oldest-First with Unique Entries) ===
    always_comb begin
        // Declare all variables at the beginning
        rs_entry_t oldest [ISSUE_W];
        int oldest_idx [ISSUE_W];
        logic [RS_ENTRIES-1:0] considered_entries;
        
        // Initialize outputs
        for (int p = 0; p < ISSUE_W; p++) begin
            issue_valid[p]     = 1'b0;
            issue_op[p]        = '0;
            issue_dst_tag[p]   = '0;
            issue_src1_val[p]  = '0;
            issue_src2_val[p]  = '0;
            issue_rob_tag[p]   = '0;
            oldest_idx[p]      = -1;
            oldest[p].age      = 0;
        end

        considered_entries = '0;

        // Multi-stage selection to ensure unique entries
        for (int p = 0; p < ISSUE_W; p++) begin
            for (int i = 0; i < RS_ENTRIES; i++) begin
                if (rs_mem[i].valid && rs_mem[i].src1_ready && rs_mem[i].src2_ready && 
                    !considered_entries[i]) begin
                    if (!issue_valid[p] || (rs_mem[i].age > oldest[p].age)) begin
                        oldest[p] = rs_mem[i];
                        oldest_idx[p] = i;
                        issue_valid[p] = 1'b1;
                    end
                end
            end
            
            // Mark the selected entry as considered for subsequent ports
            if (issue_valid[p] && oldest_idx[p] != -1) begin
                considered_entries[oldest_idx[p]] = 1'b1;
            end
        end

        // Assign issue outputs
        for (int p = 0; p < ISSUE_W; p++) begin
            if (issue_valid[p]) begin
                issue_op[p]        = oldest[p].opcode;
                issue_dst_tag[p]   = oldest[p].dst_tag;
                issue_src1_val[p]  = oldest[p].src1_val;
                issue_src2_val[p]  = oldest[p].src2_val;
                issue_rob_tag[p]   = oldest[p].rob_tag;
            end
        end
    end

    // === Clear Issued Entries ===
    always_ff @(posedge clk) begin
        // Use the indices found during selection for efficient clearing
        for (int p = 0; p < ISSUE_W; p++) begin
            if (issue_valid[p]) begin
                // In a real implementation, you'd use oldest_idx[p] directly
                // For now, we'll find by rob_tag but this could be optimized
                automatic int idx = -1;
                for (int i = 0; i < RS_ENTRIES; i++) begin
                    if (rs_mem[i].valid && rs_mem[i].rob_tag == issue_rob_tag[p]) begin
                        idx = i;
                        break;
                    end
                end
                if (idx != -1) begin
                    rs_mem[idx].valid <= 1'b0;
                end
            end
        end
    end
endmodule
