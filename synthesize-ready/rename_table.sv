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
    output logic [ALLOC_PORTS-1:0][5:0] alloc_phys,
    output logic [ALLOC_PORTS-1:0]     alloc_valid,
    
    // Free ports (multi-port release)
    input  logic [FREE_PORTS-1:0]      free_en,
    input  logic [FREE_PORTS-1:0][5:0] free_phys
);

    // Internal bitmask: 1 = free, 0 = allocated
    logic [PHYS_REGS-1:0] free_mask;

    // ============================================================
    // COMBINATIONAL Allocation Logic
    // ============================================================
    always_comb begin
        automatic logic [PHYS_REGS-1:0] temp_mask;
        automatic int search_idx;
        
        // Start with current free_mask state
        temp_mask = free_mask;
        
        // Apply any frees happening this cycle (combinational forwarding)
        for (int j = 0; j < FREE_PORTS; j++) begin
            if (free_en[j]) begin
                temp_mask[free_phys[j]] = 1'b1;
            end
        end
        
        // Perform allocations sequentially from temp_mask
        for (int a = 0; a < ALLOC_PORTS; a++) begin
            alloc_valid[a] = 1'b0;
            alloc_phys[a] = '0;
            
            if (alloc_en[a]) begin
                // Search for next free register
                for (int i = 0; i < PHYS_REGS; i++) begin
                    if (temp_mask[i]) begin
                        alloc_phys[a] = 6'(i);
                        alloc_valid[a] = 1'b1;
                        temp_mask[i] = 1'b0;  // Mark as allocated in temp
                        break;
                    end
                end
            end
        end
    end

    // ============================================================
    // SEQUENTIAL Update of free_mask
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [PHYS_REGS-1:0] updated_mask;
        
        if (reset) begin
            // Physical regs 0-31 map to architectural regs (not in free pool)
            // Physical regs 32-47 are available for renaming
            for (int i = 0; i < core_pkg::ARCH_REGS; i++) begin
                free_mask[i] <= 1'b0;
            end
            for (int i = core_pkg::ARCH_REGS; i < PHYS_REGS; i++) begin
                free_mask[i] <= 1'b1;
            end
        end else begin
            updated_mask = free_mask;
            
            // Apply frees
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en[j]) begin
                    updated_mask[free_phys[j]] = 1'b1;
                end
            end
            
            // Apply allocations (mark as not free)
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                if (alloc_en[a] && alloc_valid[a]) begin
                    updated_mask[alloc_phys[a]] = 1'b0;
                end
            end
            
            free_mask <= updated_mask;
        end
    end

endmodule
