`timescale 1ns/1ps
import core_pkg::*;

module free_list #(
    parameter int PHYS_REGS = core_pkg::PREGS
)(
    input  logic         clk,
    input  logic         reset,

    // Allocate a new physical register
    input  logic         alloc_en,
    output logic [5:0]   alloc_phys,
    output logic         alloc_valid,  // high if allocation succeeded

    // Release a physical register back to free list
    input  logic         free_en,
    input  logic [5:0]   free_phys
);

    // internal bitmask: 1 = free, 0 = allocated
    logic [PHYS_REGS-1:0] free_mask;
    
    // Single pipeline stage - combine both operations
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_mask <= {PHYS_REGS{1'b1}};
            alloc_phys <= '0;
            alloc_valid <= 1'b0;
        end else begin
            // Default outputs
            alloc_valid <= 1'b0;
            alloc_phys <= '0;
            
            // Handle free operation FIRST (using current cycle inputs)
            if (free_en) begin
                free_mask[free_phys] <= 1'b1;
            end
            
            // Handle allocation SECOND (can see freed registers)
            if (alloc_en) begin
                for (int i = 0; i < PHYS_REGS; i++) begin
                    if (free_mask[i]) begin
                        free_mask[i] <= 1'b0;
                        alloc_phys <= i;
                        alloc_valid <= 1'b1;
                        break;
                    end
                end
            end
        end
    end

endmodule
