`timescale 1ns/1ps
import core_pkg::*;

//Notes: 
//Branch predictor updates: The signals bp_update_taken, bp_update_target, bp_update_is_call, and bp_update_is_return are currently placeholders. These need to come from the ROB (which needs to store them from branch execution). We can add these in a follow-up fix if needed.
//LSU ROB index: Currently using commit slot index as a placeholder. Ideally, ROB should output the actual ROB index for each commit slot.
//Exception vector: Using a fixed address 0x0000_0100 instead of CSR-based vector. This is fine for a simple academic design.

module commit_stage #(
    parameter int COMMIT_W = core_pkg::ISSUE_WIDTH,
    parameter int XLEN = core_pkg::XLEN,
    parameter int ARCH_REGS = core_pkg::ARCH_REGS,
    parameter int PHYS_W = core_pkg::LOG2_PREGS,
    parameter int ROB_ENTRIES = core_pkg::ROB_ENTRIES
)(
    input  logic                clk,
    input  logic                reset,
    
    // ============================================================
    // From ROB (now with metadata)
    // ============================================================
    input  logic [COMMIT_W-1:0]         rob_commit_valid,
    input  logic [4:0]                  rob_commit_arch_rd[COMMIT_W-1:0],
    input  logic [PHYS_W-1:0]           rob_commit_phys_rd[COMMIT_W-1:0],
    input  logic [COMMIT_W-1:0]         rob_commit_exception,
    // NEW: Metadata from ROB
    input  logic [COMMIT_W-1:0]         rob_commit_is_store,
    input  logic [COMMIT_W-1:0]         rob_commit_is_load,
    input  logic [COMMIT_W-1:0]         rob_commit_is_branch,
    input  logic [31:0]                 rob_commit_pc[COMMIT_W-1:0],
    
    // ============================================================
    // To Architectural Register File (ARF)
    // ============================================================
    output logic [COMMIT_W-1:0]         arf_wen,
    output logic [4:0]                  arf_waddr[COMMIT_W-1:0],
    output logic [XLEN-1:0]             arf_wdata[COMMIT_W-1:0],
    
    // ============================================================
    // From Physical Register File (PRF) - Read committed values
    // ============================================================
    output logic [PHYS_W-1:0]           prf_commit_rtag[COMMIT_W-1:0],
    input  logic [XLEN-1:0]             prf_commit_rdata[COMMIT_W-1:0],
    
    // ============================================================
    // To Free List - Release old physical registers
    // ============================================================
    output logic [COMMIT_W-1:0]         freelist_free_en,
    output logic [PHYS_W-1:0]           freelist_free_phys[COMMIT_W-1:0],
    
    // ============================================================
    // To Rename Stage - Update committed RAT
    // ============================================================
    output logic [COMMIT_W-1:0]         rename_commit_en,
    output logic [4:0]                  rename_commit_arch_rd[COMMIT_W-1:0],
    output logic [PHYS_W-1:0]           rename_commit_phys_rd[COMMIT_W-1:0],
    
    // ============================================================
    // Exception/Flush Control
    // ============================================================
    output logic                        exception_valid,
    output logic [4:0]                  exception_cause,
    output logic [XLEN-1:0]             exception_pc,
    output logic [XLEN-1:0]             exception_tval,
    
    output logic                        flush_pipeline,
    output logic [XLEN-1:0]             flush_pc,
    
    // ============================================================
    // To LSU - Commit stores (FIXED)
    // ============================================================
    output logic [COMMIT_W-1:0]         lsu_commit_en,
    output logic [COMMIT_W-1:0]         lsu_commit_is_store,
    output logic [$clog2(ROB_ENTRIES)-1:0] lsu_commit_rob_idx[COMMIT_W-1:0],
    
    // ============================================================
    // To Branch Predictor - Update on branch commit (NEW)
    // ============================================================
    output logic                        bp_update_en,
    output logic [XLEN-1:0]             bp_update_pc,
    output logic                        bp_update_taken,
    output logic [XLEN-1:0]             bp_update_target,
    output logic                        bp_update_is_branch,
    output logic                        bp_update_is_call,
    output logic                        bp_update_is_return,
    
    // ============================================================
    // Performance Counters
    // ============================================================
    output logic [63:0]                 perf_insns_committed,
    output logic [63:0]                 perf_cycles,
    output logic [63:0]                 perf_exceptions
);

    // ============================================================
    // Committed Architectural Register Mapping Table
    // ============================================================
    logic [PHYS_W-1:0] committed_rat [0:ARCH_REGS-1];
    
    // ============================================================
    // Exception Detection and Prioritization
    // ============================================================
    logic exception_detected;
    logic [COMMIT_W-1:0] exception_vector;
    int exception_slot;
    
    always_comb begin
        exception_detected = 1'b0;
        exception_vector = rob_commit_exception & rob_commit_valid;
        exception_slot = -1;
        
        // Find first exception (in program order)
        for (int i = 0; i < COMMIT_W; i++) begin
            if (exception_vector[i]) begin
                exception_detected = 1'b1;
                exception_slot = i;
                break;
            end
        end
    end
    
    // ============================================================
    // Commit Logic (Sequential)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize committed RAT to identity mapping
            for (int i = 0; i < ARCH_REGS; i++) begin
                committed_rat[i] <= PHYS_W'(i);
            end
            
            // Initialize outputs
            arf_wen <= '0;
            freelist_free_en <= '0;
            rename_commit_en <= '0;
            exception_valid <= 1'b0;
            flush_pipeline <= 1'b0;
            lsu_commit_en <= '0;
            bp_update_en <= 1'b0;
            
            // Initialize performance counters
            perf_insns_committed <= '0;
            perf_cycles <= '0;
            perf_exceptions <= '0;
            
        end else begin
            // Default outputs
            arf_wen <= '0;
            freelist_free_en <= '0;
            rename_commit_en <= '0;
            exception_valid <= 1'b0;
            flush_pipeline <= 1'b0;
            lsu_commit_en <= '0;
            lsu_commit_is_store <= '0;
            bp_update_en <= 1'b0;
            
            // Increment cycle counter
            perf_cycles <= perf_cycles + 1'b1;
            
            // ============================================================
            // Exception Handling (Highest Priority)
            // ============================================================
            if (exception_detected) begin
                // Signal exception
                exception_valid <= 1'b1;
                exception_cause <= 5'd3;  // Example: illegal instruction
                exception_pc <= rob_commit_pc[exception_slot];
                exception_tval <= '0;
                
                // Flush pipeline - restart from exception handler
                // In a real implementation, this would come from CSR mtvec
                flush_pipeline <= 1'b1;
                flush_pc <= 32'h0000_0100;  // Simple fixed exception vector
                
                // Count exception
                perf_exceptions <= perf_exceptions + 1'b1;
                
                // Don't commit any instructions this cycle
                
            end else begin
                // ============================================================
                // Normal Commit Path
                // ============================================================
                automatic int commit_count = 0;
                automatic int branch_commit_idx = -1;
                
                for (int i = 0; i < COMMIT_W; i++) begin
                    if (rob_commit_valid[i]) begin
                        // ============================================================
                        // Update Architectural Register File (ARF)
                        // ============================================================
                        if (rob_commit_arch_rd[i] != 5'd0) begin  // Don't write to x0
                            arf_wen[i] <= 1'b1;
                            arf_waddr[i] <= rob_commit_arch_rd[i];
                            arf_wdata[i] <= prf_commit_rdata[i];
                        end
                        
                        // ============================================================
                        // Free Old Physical Register
                        // ============================================================
                        if (rob_commit_arch_rd[i] != 5'd0) begin
                            // Free the OLD physical register that was previously mapped
                            // to this architectural register (it's been superseded)
                            freelist_free_en[i] <= 1'b1;
                            freelist_free_phys[i] <= committed_rat[rob_commit_arch_rd[i]];
                            
                            // Update committed RAT with new mapping
                            committed_rat[rob_commit_arch_rd[i]] <= rob_commit_phys_rd[i];
                        end
                        
                        // ============================================================
                        // Update Rename Stage Committed RAT
                        // ============================================================
                        rename_commit_en[i] <= 1'b1;
                        rename_commit_arch_rd[i] <= rob_commit_arch_rd[i];
                        rename_commit_phys_rd[i] <= rob_commit_phys_rd[i];
                        
                        // ============================================================
                        // LSU Commit Signal (for stores)
                        // ============================================================
                        if (rob_commit_is_store[i]) begin
                            lsu_commit_en[i] <= 1'b1;
                            lsu_commit_is_store[i] <= 1'b1;
                            // ROB index calculation (head + i)
                            // Note: This is simplified - ideally ROB should provide the actual index
                            lsu_commit_rob_idx[i] <= i;  // Placeholder
                        end
                        
                        // ============================================================
                        // Branch Predictor Update (only commit one branch per cycle)
                        // ============================================================
                        if (rob_commit_is_branch[i] && branch_commit_idx == -1) begin
                            branch_commit_idx = i;
                        end
                        
                        commit_count++;
                    end
                end
                
                // ============================================================
                // Branch Predictor Update (outside the loop)
                // ============================================================
                if (branch_commit_idx != -1) begin
                    bp_update_en <= 1'b1;
                    bp_update_pc <= rob_commit_pc[branch_commit_idx];
                    // Note: We need branch outcome and target from somewhere
                    // For now, this is a placeholder - needs integration with branch_ex
                    bp_update_taken <= 1'b0;      // Placeholder
                    bp_update_target <= '0;       // Placeholder
                    bp_update_is_branch <= 1'b1;
                    bp_update_is_call <= 1'b0;    // Placeholder
                    bp_update_is_return <= 1'b0;  // Placeholder
                end
                
                // Update instruction commit counter
                perf_insns_committed <= perf_insns_committed + commit_count;
            end
        end
    end
    
    // ============================================================
    // PRF Read Tags (Combinational)
    // ============================================================
    always_comb begin
        for (int i = 0; i < COMMIT_W; i++) begin
            prf_commit_rtag[i] = rob_commit_phys_rd[i];
        end
    end

endmodule
