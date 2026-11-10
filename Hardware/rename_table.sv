`timescale 1ns/1ps
import core_pkg::*;

module rename_table #(
    parameter int ARCH_REGS      = 32,
    parameter int PHYS_REGS      = 64,
    parameter int LOOKUP_PORTS   = 2,
    parameter int RENAME_PORTS   = 2,
    parameter int COMMIT_PORTS   = 2,
    parameter int NUM_CHECKPOINTS = 8
)(
    input  logic clk,
    input  logic reset,

    // Lookup ports
    input  logic [LOOKUP_PORTS-1:0][4:0] arch_rs1,
    input  logic [LOOKUP_PORTS-1:0][4:0] arch_rs2,
    output logic [LOOKUP_PORTS-1:0][5:0] phys_rs1,
    output logic [LOOKUP_PORTS-1:0][5:0] phys_rs2,

    // Speculative rename ports
    input  logic [RENAME_PORTS-1:0]      rename_en,
    input  logic [RENAME_PORTS-1:0][4:0] arch_rd,
    input  logic [RENAME_PORTS-1:0][5:0] new_phys_rd,

    // Commit ports
    input  logic [COMMIT_PORTS-1:0]      commit_en,
    input  logic [COMMIT_PORTS-1:0][4:0] commit_arch_rd,
    input  logic [COMMIT_PORTS-1:0][5:0] commit_phys_rd,
    input  logic [COMMIT_PORTS-1:0][5:0] commit_old_phys_rd,

    // One checkpoint request per rename lane
    input  logic [RENAME_PORTS-1:0] checkpoint_en,
    input  logic [RENAME_PORTS-1:0][$clog2(NUM_CHECKPOINTS)-1:0]
                                                   checkpoint_id,

    // Recovery
    input  logic flush_pipeline,
    input  logic [$clog2(NUM_CHECKPOINTS)-1:0] restore_id
);

    localparam int CP_W = $clog2(NUM_CHECKPOINTS);

    logic [5:0] map_table [ARCH_REGS-1:0];
    logic [5:0] committed_table [ARCH_REGS-1:0];

    logic [5:0] committed_table_next [ARCH_REGS-1:0];

    logic [5:0] checkpoint_maps
        [NUM_CHECKPOINTS-1:0][ARCH_REGS-1:0];

    logic [5:0] checkpoint_maps_next
        [NUM_CHECKPOINTS-1:0][ARCH_REGS-1:0];

    logic [5:0] map_after_commits [ARCH_REGS-1:0];
    logic [5:0] map_work [ARCH_REGS-1:0];

    // ------------------------------------------------------------
    // Commit next-state and checkpoint maintenance.
    //
    // An older instruction committing after a checkpoint was
    // created must update that checkpoint if its mapping still
    // refers to the old physical register.
    // ------------------------------------------------------------
    always_comb begin
        for (int a = 0; a < ARCH_REGS; a++) begin
            committed_table_next[a] = committed_table[a];
            map_after_commits[a]    = map_table[a];
        end

        for (int c = 0; c < COMMIT_PORTS; c++) begin
            if (commit_en[c] && commit_arch_rd[c] != 5'd0) begin
                committed_table_next[commit_arch_rd[c]] =
                    commit_phys_rd[c];

                if (map_after_commits[commit_arch_rd[c]] ==
                    commit_old_phys_rd[c]) begin
                    map_after_commits[commit_arch_rd[c]] =
                        commit_phys_rd[c];
                end
            end
        end

        // Start every saved checkpoint from its prior contents,
        // then advance mappings affected by older commits.
        for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
            for (int a = 0; a < ARCH_REGS; a++) begin
                checkpoint_maps_next[cp][a] =
                    checkpoint_maps[cp][a];
            end

            for (int c = 0; c < COMMIT_PORTS; c++) begin
                if (commit_en[c] && commit_arch_rd[c] != 5'd0 &&
                    checkpoint_maps_next[cp][commit_arch_rd[c]] ==
                    commit_old_phys_rd[c]) begin

                    checkpoint_maps_next[cp][commit_arch_rd[c]] =
                        commit_phys_rd[c];
                end
            end
        end

        // Construct checkpoint snapshots in program order.
        // Lane 0's checkpoint includes lane 0's rename.
        // Lane 1's checkpoint includes lane 0 and lane 1.
        for (int a = 0; a < ARCH_REGS; a++) begin
            map_work[a] = map_after_commits[a];
        end

        for (int lane = 0; lane < RENAME_PORTS; lane++) begin
            if (rename_en[lane] && arch_rd[lane] != 5'd0) begin
                map_work[arch_rd[lane]] = new_phys_rd[lane];
            end

            if (checkpoint_en[lane]) begin
                for (int a = 0; a < ARCH_REGS; a++) begin
                    checkpoint_maps_next[checkpoint_id[lane]][a] =
                        map_work[a];
                end
            end
        end

        // Multiport reads with same-cycle older-lane forwarding.
        for (int lane = 0; lane < LOOKUP_PORTS; lane++) begin
            phys_rs1[lane] =
                (arch_rs1[lane] == 5'd0) ? 6'd0 :
                map_table[arch_rs1[lane]];

            phys_rs2[lane] =
                (arch_rs2[lane] == 5'd0) ? 6'd0 :
                map_table[arch_rs2[lane]];

            for (int older = 0; older < RENAME_PORTS; older++) begin
                if (older < lane && rename_en[older] &&
                    arch_rd[older] != 5'd0) begin

                    if (arch_rs1[lane] == arch_rd[older])
                        phys_rs1[lane] = new_phys_rd[older];

                    if (arch_rs2[lane] == arch_rd[older])
                        phys_rs2[lane] = new_phys_rd[older];
                end
            end
        end
    end

    // ------------------------------------------------------------
    // State
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int a = 0; a < ARCH_REGS; a++) begin
                map_table[a]       <= 6'(a);
                committed_table[a] <= 6'(a);
            end

            for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
                for (int a = 0; a < ARCH_REGS; a++) begin
                    checkpoint_maps[cp][a] <= 6'(a);
                end
            end
        end else begin
            committed_table <= committed_table_next;
            checkpoint_maps <= checkpoint_maps_next;

            if (flush_pipeline) begin
                for (int a = 0; a < ARCH_REGS; a++) begin
                    map_table[a] <= checkpoint_maps_next[restore_id][a];
                end
            end else begin
                for (int lane = 0; lane < RENAME_PORTS; lane++) begin
                    if (rename_en[lane] && arch_rd[lane] != 5'd0) begin
                        map_table[arch_rd[lane]] <= new_phys_rd[lane];
                    end
                end
            end
        end
    end

endmodule
