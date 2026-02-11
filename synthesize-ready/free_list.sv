`timescale 1 ns/ 1 ps
import core_pkg::*;

module free_list #(
    parameter int PHYS_REGS = core_pkg::PREGS,
    parameter int ALLOC_PORTS = 2,
    parameter int FREE_PORTS = 2
)(
    input  logic         clk,
    input  logic         reset,

    // Allocate ports (multi-port allocation)
    input  logic [ALLOC_PORTS-1:0]     alloc_en,
    output logic [ALLOC_PORTS-1:0][5:0]                 alloc_phys,
    output logic [ALLOC_PORTS-1:0]     alloc_valid,

    // Free ports (multi-port release)
    input  logic [FREE_PORTS-1:0]      free_en,
    input  logic [FREE_PORTS-1:0][5:0]                 free_phys
);

    // Internal bitmask: 1 = free, 0 = allocated
    logic [PHYS_REGS-1:0] free_mask;
    logic [PHYS_REGS-1:0] updated_mask;

    always_ff @(posedge clk or posedge reset) begin
        automatic int alloc_count;
        automatic int search_start;
        
        if (reset) begin
            // Physical regs 0-31 map to architectural regs (not in free pool)
            // Physical regs 32-47 are available for renaming
            for (int i = 0; i < core_pkg::ARCH_REGS; i++) begin
                free_mask[i] <= 1'b0;
            end
            for (int i = core_pkg::ARCH_REGS; i < PHYS_REGS; i++) begin
                free_mask[i] <= 1'b1;
            end
            
            for (int i = 0; i < ALLOC_PORTS; i++) begin
                alloc_phys[i] <= '0;
                alloc_valid[i] <= 1'b0;
            end
        end else begin
            // Start with current free mask
            updated_mask = free_mask;
            
            // ============================================================
            // Step 1: Apply all frees FIRST
            // ============================================================
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en[j]) begin
                    updated_mask[free_phys[j]] = 1'b1;
                end
            end
            
            // ============================================================
            // Step 2: Perform allocations sequentially
            // ============================================================
            alloc_count = 0;
            search_start = 0;
            
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                alloc_valid[a] <= 1'b0;
                alloc_phys[a] <= '0;
                
                if (alloc_en[a]) begin
                    // Search for next free register starting from search_start
                    for (int i = 0; i < PHYS_REGS; i++) begin
                        if (updated_mask[i]) begin
                            alloc_phys[a] <= 6'(i);
                            alloc_valid[a] <= 1'b1;
                            updated_mask[i] = 1'b0;  // Mark as allocated
                            search_start = i + 1;
                            break;
                        end
                    end
                end
            end
            
            // Update actual free_mask
            free_mask <= updated_mask;
        end
    end
endmodule
