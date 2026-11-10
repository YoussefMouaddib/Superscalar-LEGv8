`timescale 1ns/1ps
import core_pkg::*;

module rename_stage #(
    parameter int FETCH_W = 2,
    parameter int ARCH_REGS = 32,
    parameter int PHYS_REGS = 64,
    parameter int NUM_CHECKPOINTS = 8
)(
    input  logic clk,
    input  logic reset,

    // From Decode
    input  logic [FETCH_W-1:0]       dec_valid,
    input  logic [FETCH_W-1:0][5:0]  dec_opcode,
    input  logic [FETCH_W-1:0][4:0]  dec_rs1,
    input  logic [FETCH_W-1:0][4:0]  dec_rs2,
    input  logic [FETCH_W-1:0][4:0]  dec_rd,
    input  logic [FETCH_W-1:0][31:0] dec_imm,
    input  logic [FETCH_W-1:0][31:0] dec_pc,
    input  logic [FETCH_W-1:0]       dec_rs1_valid,
    input  logic [FETCH_W-1:0]       dec_rs2_valid,
    input  logic [FETCH_W-1:0]       dec_rd_valid,
    input  logic [FETCH_W-1:0]       dec_is_alu,
    input  logic [FETCH_W-1:0]       dec_is_load,
    input  logic [FETCH_W-1:0]       dec_is_store,
    input  logic [FETCH_W-1:0]       dec_is_branch,
    input  logic [FETCH_W-1:0]       dec_is_cas,
    input  logic [FETCH_W-1:0][5:0]  dec_alu_func,

    // Backpressure
    output logic rename_ready,

    // To issue / dispatch
    output logic [FETCH_W-1:0]       rename_valid,
    output logic [FETCH_W-1:0][5:0]  rename_opcode,
    output logic [FETCH_W-1:0][5:0]  rename_prs1,
    output logic [FETCH_W-1:0][5:0]  rename_prs2,
    output logic [FETCH_W-1:0][5:0]  rename_prd,
    output logic [FETCH_W-1:0][31:0] rename_imm,
    output logic [FETCH_W-1:0][31:0] rename_pc,
    output logic [FETCH_W-1:0]       rename_rs1_valid,
    output logic [FETCH_W-1:0]       rename_rs2_valid,
    output logic [FETCH_W-1:0]       rename_rd_valid,
    output logic [FETCH_W-1:0]       rename_is_alu,
    output logic [FETCH_W-1:0]       rename_is_load,
    output logic [FETCH_W-1:0]       rename_is_store,
    output logic [FETCH_W-1:0]       rename_is_branch,
    output logic [FETCH_W-1:0]       rename_is_cas,
    output logic [FETCH_W-1:0][5:0]  rename_alu_func,

    output logic [FETCH_W-1:0][4:0] rename_arch_rs1,
    output logic [FETCH_W-1:0][4:0] rename_arch_rs2,
    output logic [FETCH_W-1:0][4:0] rename_arch_rd,

    // Checkpoint ID carried with each renamed branch
    output logic [FETCH_W-1:0][$clog2(NUM_CHECKPOINTS)-1:0]
                                                rename_checkpoint_id,

    // Commit interface
    input  logic [FETCH_W-1:0]       commit_en,
    input  logic [FETCH_W-1:0][4:0]  commit_arch_rd,
    input  logic [FETCH_W-1:0][5:0]  commit_phys_rd,
    input  logic [FETCH_W-1:0][5:0]  commit_old_phys_rd,

    // Recovery
    input  logic flush_pipeline,
    input  logic [$clog2(NUM_CHECKPOINTS)-1:0] restore_checkpoint_id,

    // Correct branch resolution (mispredict is indicated by flush_pipeline)
    input  logic branch_resolve_valid,
    input  logic [$clog2(NUM_CHECKPOINTS)-1:0] branch_resolve_id
);

    localparam int CP_W = $clog2(NUM_CHECKPOINTS);

    logic [FETCH_W-1:0] alloc_en;
    logic [FETCH_W-1:0][5:0] alloc_phys;
    logic [FETCH_W-1:0] alloc_valid;

    logic [FETCH_W-1:0] commit_en_r;
    logic [FETCH_W-1:0][4:0] commit_arch_rd_r;
    logic [FETCH_W-1:0][5:0] commit_phys_rd_r;
    logic [FETCH_W-1:0][5:0] commit_old_phys_rd_r;

    logic [FETCH_W-1:0] rename_en;
    logic [FETCH_W-1:0][4:0] rename_arch_rd_wire;
    logic [FETCH_W-1:0][5:0] rename_new_phys_rd;

    logic [FETCH_W-1:0][5:0] phys_rs1;
    logic [FETCH_W-1:0][5:0] phys_rs2;

    logic [FETCH_W-1:0] take_checkpoint;
    logic [FETCH_W-1:0][CP_W-1:0] checkpoint_id_wire;

    logic [NUM_CHECKPOINTS-1:0] checkpoint_active;
    logic [NUM_CHECKPOINTS-1:0][CP_W-1:0] checkpoint_parent;
    logic [NUM_CHECKPOINTS-1:0][31:0] checkpoint_age;
    logic [31:0] next_checkpoint_age;

    logic [FETCH_W-1:0] checkpoint_create;
    logic [FETCH_W-1:0][CP_W-1:0] checkpoint_create_id;

    logic [NUM_CHECKPOINTS-1:0] active_next;
    logic [NUM_CHECKPOINTS-1:0][CP_W-1:0] parent_next;
    logic [NUM_CHECKPOINTS-1:0][31:0] age_next;
    logic [31:0] age_counter_next;

    // ------------------------------------------------------------
    // Commit pipeline registers. Kept as a separate stage, as in
    // your original design.
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_pipeline) begin
            commit_en_r          <= '0;
            commit_arch_rd_r     <= '0;
            commit_phys_rd_r     <= '0;
            commit_old_phys_rd_r <= '0;
        end else begin
            commit_en_r          <= commit_en;
            commit_arch_rd_r     <= commit_arch_rd;
            commit_phys_rd_r     <= commit_phys_rd;
            commit_old_phys_rd_r <= commit_old_phys_rd;
        end
    end

    // Only instructions that actually write a nonzero architectural
    // destination consume a physical register.
    always_comb begin
        alloc_en = '0;
        rename_en = '0;
        rename_ready = 1'b1;

        for (int i = 0; i < FETCH_W; i++) begin
            alloc_en[i] = dec_valid[i] && dec_rd_valid[i] &&
                          (dec_rd[i] != 5'd0) && !flush_pipeline;

            rename_en[i] = alloc_en[i];

            rename_arch_rd_wire[i] = dec_rd[i];
            rename_new_phys_rd[i] = alloc_phys[i];
        end
    end

    // ------------------------------------------------------------
    // Checkpoint allocation.
    //
    // Select distinct inactive slots in lane order. The second
    // branch's parent is the first branch when both are in this
    // rename group.
    // ------------------------------------------------------------
    always_comb begin : checkpoint_allocate
        logic [NUM_CHECKPOINTS-1:0] used;
        logic found;
        logic [CP_W-1:0] selected;
        logic [CP_W-1:0] youngest_id;
        logic [31:0] youngest_age;
        logic have_parent;

        used = checkpoint_active;
        checkpoint_create = '0;
        checkpoint_create_id = '0;
        checkpoint_id_wire = '0;

        // A correctly resolved checkpoint can be reused on a later
        // cycle. Do not reuse it in the same cycle as resolution.
        for (int lane = 0; lane < FETCH_W; lane++) begin
            if (dec_valid[lane] && dec_is_branch[lane] &&
                !flush_pipeline) begin

                found = 1'b0;
                selected = '0;

                for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
                    if (!used[cp] && !found) begin
                        selected = CP_W'(cp);
                        found = 1'b1;
                    end
                end

                if (found) begin
                    checkpoint_create[lane] = 1'b1;
                    checkpoint_create_id[lane] = selected;
                    checkpoint_id_wire[lane] = selected;
                    used[selected] = 1'b1;
                end
            end
        end

        // Non-branch lanes carry zero. The allocator below records
        // parentage in program order using the age of active slots.
        // (The branch ID itself is independent for each lane.)
    end

    // ------------------------------------------------------------
    // Parent/age bookkeeping.
    //
    // Parent links form the speculation ancestry tree. A correct
    // resolution removes a node and reparents its direct children.
    // A mispredict removes the selected node and all descendants.
    // ------------------------------------------------------------
    always_comb begin : checkpoint_bookkeeping
        logic [NUM_CHECKPOINTS-1:0] used;
        logic [CP_W-1:0] chosen_parent;
        logic have_parent;
        logic [31:0] best_age;
        logic [CP_W-1:0] walk;
        logic is_descendant;

        active_next = checkpoint_active;
        parent_next = checkpoint_parent;
        age_next = checkpoint_age;
        age_counter_next = next_checkpoint_age;

        if (flush_pipeline) begin
            for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
                walk = CP_W'(cp);
                is_descendant = 1'b0;

                // Walk toward the root, bounded to avoid a malformed
                // parent chain causing a combinational infinite loop.
                for (int depth = 0; depth < NUM_CHECKPOINTS; depth++) begin
                    if (walk == restore_checkpoint_id)
                        is_descendant = 1'b1;
                    else
                        walk = checkpoint_parent[walk];
                end

                if (is_descendant)
                    active_next[cp] = 1'b0;
            end
        end else begin
            // Correctly resolved branch: release its slot, and
            // reparent its direct children to its own parent.
            if (branch_resolve_valid &&
                checkpoint_active[branch_resolve_id]) begin

                active_next[branch_resolve_id] = 1'b0;

                for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
                    if (checkpoint_active[cp] &&
                        checkpoint_parent[cp] == branch_resolve_id) begin
                        parent_next[cp] =
                            checkpoint_parent[branch_resolve_id];
                    end
                end
            end

            // Create new checkpoints in lane order.
            used = active_next;

            for (int lane = 0; lane < FETCH_W; lane++) begin
                if (checkpoint_create[lane]) begin
                    chosen_parent = '0;
                    have_parent = 1'b0;
                    best_age = '0;

                    for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
                        if (used[cp] &&
                            (!have_parent || age_next[cp] > best_age)) begin
                            chosen_parent = CP_W'(cp);
                            best_age = age_next[cp];
                            have_parent = 1'b1;
                        end
                    end

                    active_next[checkpoint_create_id[lane]] = 1'b1;
                    parent_next[checkpoint_create_id[lane]] =
                        have_parent ? chosen_parent : '0;
                    age_next[checkpoint_create_id[lane]] =
                        age_counter_next;

                    age_counter_next = age_counter_next + 1'b1;
                    used[checkpoint_create_id[lane]] = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            checkpoint_active <= '0;
            checkpoint_parent <= '0;
            checkpoint_age <= '0;
            next_checkpoint_age <= '0;
        end else begin
            checkpoint_active <= active_next;
            checkpoint_parent <= parent_next;
            checkpoint_age <= age_next;
            next_checkpoint_age <= age_counter_next;
        end
    end

    // ------------------------------------------------------------
    // Free list
    // ------------------------------------------------------------
    free_list #(
        .PHYS_REGS(PHYS_REGS),
        .ALLOC_PORTS(FETCH_W),
        .FREE_PORTS(FETCH_W),
        .NUM_CHECKPOINTS(NUM_CHECKPOINTS)
    ) free_list_inst (
        .clk(clk),
        .reset(reset),

        .flush_pipeline(flush_pipeline),
        .restore_en(flush_pipeline),
        .restore_id(restore_checkpoint_id),

        .checkpoint_en(checkpoint_create),
        .checkpoint_id(checkpoint_create_id),

        .alloc_en(alloc_en),
        .alloc_phys(alloc_phys),
        .alloc_valid(alloc_valid),

        .free_en(commit_en_r),
        .free_phys(commit_old_phys_rd_r)
    );

    // ------------------------------------------------------------
    // Rename table
    // ------------------------------------------------------------
    rename_table #(
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS),
        .LOOKUP_PORTS(FETCH_W),
        .RENAME_PORTS(FETCH_W),
        .COMMIT_PORTS(FETCH_W),
        .NUM_CHECKPOINTS(NUM_CHECKPOINTS)
    ) rename_table_inst (
        .clk(clk),
        .reset(reset),

        .arch_rs1(dec_rs1),
        .arch_rs2(dec_rs2),
        .phys_rs1(phys_rs1),
        .phys_rs2(phys_rs2),

        .rename_en(rename_en),
        .arch_rd(rename_arch_rd_wire),
        .new_phys_rd(rename_new_phys_rd),

        .commit_en(commit_en_r),
        .commit_arch_rd(commit_arch_rd_r),
        .commit_phys_rd(commit_phys_rd_r),
        .commit_old_phys_rd(commit_old_phys_rd_r),

        .checkpoint_en(checkpoint_create),
        .checkpoint_id(checkpoint_create_id),

        .flush_pipeline(flush_pipeline),
        .restore_id(restore_checkpoint_id)
    );

    // ------------------------------------------------------------
    // Decode -> Rename pipeline registers.
    // Preserves the original register stage and allocation-output
    // timing. Same-cycle older-lane destination bypass is retained.
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin : rename_pipeline
        logic bypassed_rs1;
        logic bypassed_rs2;
        logic [5:0] bypass_tag_rs1;
        logic [5:0] bypass_tag_rs2;

        if (reset) begin
            rename_valid          <= '0;
            rename_opcode         <= '0;
            rename_prs1           <= '0;
            rename_prs2           <= '0;
            rename_prd            <= '0;
            rename_imm            <= '0;
            rename_pc             <= '0;
            rename_rs1_valid      <= '0;
            rename_rs2_valid      <= '0;
            rename_rd_valid       <= '0;
            rename_is_alu         <= '0;
            rename_is_load        <= '0;
            rename_is_store       <= '0;
            rename_is_branch      <= '0;
            rename_is_cas         <= '0;
            rename_alu_func       <= '0;
            rename_arch_rs1       <= '0;
            rename_arch_rs2       <= '0;
            rename_arch_rd        <= '0;
            rename_checkpoint_id  <= '0;
        end else if (flush_pipeline) begin
            rename_valid <= '0;
        end else begin
            for (int i = 0; i < FETCH_W; i++) begin
                rename_valid[i]     <= dec_valid[i];
                rename_opcode[i]    <= dec_opcode[i];
                rename_imm[i]       <= dec_imm[i];
                rename_pc[i]        <= dec_pc[i];
                rename_alu_func[i]  <= dec_alu_func[i];

                rename_is_alu[i]    <= dec_is_alu[i];
                rename_is_load[i]   <= dec_is_load[i];
                rename_is_store[i]  <= dec_is_store[i];
                rename_is_branch[i] <= dec_is_branch[i];
                rename_is_cas[i]    <= dec_is_cas[i];

                rename_rs1_valid[i] <= dec_rs1_valid[i];
                rename_rs2_valid[i] <= dec_rs2_valid[i];

                rename_arch_rs1[i] <= dec_rs1[i];
                rename_arch_rs2[i] <= dec_rs2[i];
                rename_arch_rd[i]  <= dec_rd[i];

                rename_checkpoint_id[i] <=
                    checkpoint_create[i] ? checkpoint_create_id[i] : '0;

                if (dec_rd[i] == 5'd0 || !dec_rd_valid[i]) begin
                    rename_prd[i] <= 6'd0;
                    rename_rd_valid[i] <= 1'b0;
                end else if (alloc_valid[i]) begin
                    rename_prd[i] <= alloc_phys[i];
                    rename_rd_valid[i] <= 1'b1;
                end else begin
                    rename_prd[i] <= 6'd0;
                    rename_rd_valid[i] <= 1'b0;
                end

                bypassed_rs1 = 1'b0;
                bypass_tag_rs1 = '0;

                if (dec_rs1_valid[i] && dec_rs1[i] != 5'd0) begin
                    for (int j = 0; j < i; j++) begin
                        if (dec_valid[j] && dec_rd_valid[j] &&
                            dec_rd[j] != 5'd0 &&
                            dec_rd[j] == dec_rs1[i]) begin
                            bypassed_rs1 = 1'b1;
                            bypass_tag_rs1 = alloc_phys[j];
                        end
                    end

                    rename_prs1[i] <= bypassed_rs1 ?
                                      bypass_tag_rs1 : phys_rs1[i];
                end else begin
                    rename_prs1[i] <= 6'd0;
                end

                bypassed_rs2 = 1'b0;
                bypass_tag_rs2 = '0;

                if (dec_rs2_valid[i] && dec_rs2[i] != 5'd0) begin
                    for (int j = 0; j < i; j++) begin
                        if (dec_valid[j] && dec_rd_valid[j] &&
                            dec_rd[j] != 5'd0 &&
                            dec_rd[j] == dec_rs2[i]) begin
                            bypassed_rs2 = 1'b1;
                            bypass_tag_rs2 = alloc_phys[j];
                        end
                    end

                    rename_prs2[i] <= bypassed_rs2 ?
                                      bypass_tag_rs2 : phys_rs2[i];
                end else begin
                    rename_prs2[i] <= 6'd0;
                end
            end
        end
    end

    // No partial dispatch if the free list cannot satisfy all
    // destination allocations requested by this decode group.
    always_comb begin
        rename_ready = 1'b1;

        for (int i = 0; i < FETCH_W; i++) begin
            if (alloc_en[i] && !alloc_valid[i])
                rename_ready = 1'b0;
        end
    end

endmodule
