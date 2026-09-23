`timescale 1ns/1ps
import core_pkg::*;

module rename_table #(
    parameter int ARCH_REGS = 32,
    parameter int PHYS_REGS = 48,
    parameter int LOOKUP_PORTS = 2,
    parameter int RENAME_PORTS = 2,
    parameter int COMMIT_PORTS = 2
)(
    input  logic              clk,
    input  logic              reset,
    
    // Lookup ports (multi-port read)
    input  logic [LOOKUP_PORTS-1:0][4:0]        arch_rs1,
    input  logic [LOOKUP_PORTS-1:0][4:0]        arch_rs2,
    output logic [LOOKUP_PORTS-1:0][5:0]        phys_rs1,
    output logic [LOOKUP_PORTS-1:0][5:0]        phys_rs2,
    
    // Rename ports (multi-port speculative update)
    input  logic [RENAME_PORTS-1:0]  rename_en,
    input  logic [RENAME_PORTS-1:0][4:0]        arch_rd,
    input  logic [RENAME_PORTS-1:0][5:0]        new_phys_rd,
    
    // Commit ports (multi-port committed state update)
    input  logic [COMMIT_PORTS-1:0]  commit_en,
    input  logic [COMMIT_PORTS-1:0][4:0]        commit_arch_rd,
    input  logic [COMMIT_PORTS-1:0][5:0]        commit_phys_rd,
    
    // Flush pipeline
    input  logic              flush_pipeline
);

    logic [5:0] map_table [ARCH_REGS-1:0];          // speculative mapping
    logic [5:0] committed_table [ARCH_REGS-1:0];    // committed mapping

    // ============================================================
    // Combinational "next" committed state
    // ------------------------------------------------------------
    // This merges in-flight commits (commit_en/commit_arch_rd/
    // commit_phys_rd, whatever arrives this cycle) on top of the
    // current committed_table. Both the real committed_table
    // register AND a flush recovery (if one happens this same
    // cycle) must use THIS value, not the old registered
    // committed_table directly - otherwise a commit landing on the
    // exact same edge as a flush is invisible to the recovery copy
    // (non-blocking reads always see the pre-edge value), and the
    // recovered map_table silently reverts that architectural
    // register to a stale/older physical register.
    // ============================================================
    logic [5:0] committed_table_next [ARCH_REGS-1:0];

    always_comb begin
        for (int i = 0; i < ARCH_REGS; i++) begin
            committed_table_next[i] = committed_table[i];
        end
        for (int j = 0; j < COMMIT_PORTS; j++) begin
            if (commit_en[j] && commit_arch_rd[j] != 5'd0) begin
                committed_table_next[commit_arch_rd[j]] = commit_phys_rd[j];
            end
        end
    end

    // ============================================================
    // Multi-port Combinational Reads
    // ============================================================
    always_comb begin
        for (int i = 0; i < LOOKUP_PORTS; i++) begin
            // Default: read from map table
            phys_rs1[i] = (arch_rs1[i] == 5'd0) ? 6'd0 : map_table[arch_rs1[i]];
            phys_rs2[i] = (arch_rs2[i] == 5'd0) ? 6'd0 : map_table[arch_rs2[i]];
            
            // FORWARDING: Check if earlier rename ports are writing this register THIS cycle
            for (int j = 0; j < RENAME_PORTS; j++) begin
                if (j < i && rename_en[j] ) begin  // Earlier lane
                    if (arch_rs1[i] == arch_rd[j]) begin
                        phys_rs1[i] = new_phys_rd[j];  // Forward from earlier rename
                    end
                    if (arch_rs2[i] == arch_rd[j]) begin
                        phys_rs2[i] = new_phys_rd[j];  // Forward from earlier rename
                    end
                end
            end
        end
    end

    // ============================================================
    // Sequential Updates (Rename + Commit + Flush Recovery)
    // ------------------------------------------------------------
    // Everything that touches map_table or committed_table now
    // lives in ONE always_ff so there's no cross-block same-edge
    // read/write hazard between the commit path and flush recovery.
    // (rename_stage already forces rename_en=0 during a flush
    // cycle, so the speculative-rename loop and the flush-recovery
    // assignment below never race for map_table in practice.)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                map_table[i]       <= 6'(i);  // Initial mapping: arch -> same phys
                committed_table[i] <= 6'(i);
            end
        end else begin
            // ============================================================
            // Speculative Renames (multi-port, applied sequentially)
            // ============================================================
            for (int j = 0; j < RENAME_PORTS; j++) begin
                if (rename_en[j]) begin
                    map_table[arch_rd[j]] <= new_phys_rd[j];
                end
            end

            // ============================================================
            // Committed State Update - ALWAYS advances, flush or not.
            // Uses the merged next-state so nothing in flight is lost.
            // ============================================================
            committed_table <= committed_table_next;

            // ============================================================
            // Flush Recovery - restore map_table from the UP-TO-DATE
            // committed state (including anything committing this very
            // cycle), not the stale pre-edge committed_table.
            // ============================================================
            if (flush_pipeline) begin
                map_table <= committed_table_next;
            end
        end
    end

endmodule
