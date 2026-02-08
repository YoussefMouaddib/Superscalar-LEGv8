`timescale 1ns/1ps
import core_pkg::*;

module commit_stage #(
    parameter int COMMIT_W = core_pkg::ISSUE_WIDTH,  // Commit width (2)
    parameter int XLEN = core_pkg::XLEN,
    parameter int ARCH_REGS = core_pkg::ARCH_REGS,
    parameter int PHYS_W = core_pkg::LOG2_PREGS,
    parameter int ROB_ENTRIES = core_pkg::ROB_ENTRIES
)(
    input  logic                clk,
    input  logic                reset,
    
    // ============================================================
    // From ROB
    // ============================================================
    input  logic [COMMIT_W-1:0]         rob_commit_valid,
    input  logic [4:0]                  rob_commit_arch_rd[COMMIT_W-1:0],
    input  logic [PHYS_W-1:0]           rob_commit_phys_rd[COMMIT_W-1:0],
    input  logic [COMMIT_W-1:0]         rob_commit_exception,
    
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
    output logic [XLEN-1:0]             exception_tval,  // Trap value (e.g., bad address)
    
    output logic                        flush_pipeline,
    output logic [XLEN-1:0]             flush_pc,
    
    // ============================================================
    // To LSU - Commit stores
    // ============================================================
    output logic                        lsu_commit_en,
    output logic                        lsu_commit_is_store,
    output logic [5:0]                  lsu_commit_rob_idx,
    
    // ============================================================
    // Performance Counters
    // ============================================================
    output logic [63:0]                 perf_insns_committed,
    output logic [63:0]                 perf_cycles,
    output logic [63:0]                 perf_exceptions,
    
    // ============================================================
    // CSR Interface (for exception handling)
    // ============================================================
    input  logic [XLEN-1:0]             csr_mepc,      // Exception PC from CSR
    input  logic [XLEN-1:0]             csr_mtvec,     // Trap vector base
    output logic                        csr_exception_en,
    output logic [XLEN-1:0]             csr_exception_pc,
    output logic [4:0]                  csr_exception_cause,
    output logic [XLEN-1:0]             csr_exception_tval
);

    // ============================================================
    // Committed Architectural Register Mapping Table
    // Tracks the committed physical register for each arch register
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
            lsu_commit_en <= 1'b0;
            
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
            lsu_commit_en <= 1'b0;
            csr_exception_en <= 1'b0;
            
            // Increment cycle counter
            perf_cycles <= perf_cycles + 1'b1;
            
            // ============================================================
            // Exception Handling (Highest Priority)
            // ============================================================
            if (exception_detected) begin
                // Signal exception
                exception_valid <= 1'b1;
                exception_cause <= 5'd3;  // Example: Illegal instruction
                exception_pc <= '0;       // Would come from ROB in full implementation
                exception_tval <= '0;
                
                // Flush pipeline
                flush_pipeline <= 1'b1;
                flush_pc <= csr_mtvec;  // Jump to exception handler
                
                // Update CSR
                csr_exception_en <= 1'b1;
                csr_exception_pc <= '0;  // PC of faulting instruction
                csr_exception_cause <= 5'd3;
                csr_exception_tval <= '0;
                
                // Count exception
                perf_exceptions <= perf_exceptions + 1'b1;
                
                // Don't commit any instructions this cycle
                
            end else begin
                // ============================================================
                // Normal Commit Path
                // ============================================================
                automatic int commit_count = 0;
                
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
                            // The old physical register that was mapped to this arch reg
                            // can now be freed (it's been superseded by the new mapping)
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
                        
                        commit_count++;
                    end
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
    
    // ============================================================
    // LSU Commit Signal Generation (Combinational)
    // ============================================================
    // Note: This is simplified - in a full implementation, you'd need
    // to track which ROB entries correspond to stores
    always_comb begin
        lsu_commit_en = 1'b0;
        lsu_commit_is_store = 1'b0;
        lsu_commit_rob_idx = '0;
        
        // Signal LSU when committing (for store completion)
        for (int i = 0; i < COMMIT_W; i++) begin
            if (rob_commit_valid[i]) begin
                // This would ideally check if instruction is a store
                // For now, LSU will filter based on ROB index matching
                lsu_commit_en = 1'b1;
                lsu_commit_is_store = 1'b1;  // Simplified
                lsu_commit_rob_idx = 6'(i);  // Would be actual ROB index
                break;
            end
        end
    end

endmodule
