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
    logic [PHYS_REGS-1:0] updated_mask;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_mask <= {PHYS_REGS{1'b1}};
            alloc_phys <= '0;
            alloc_valid <= 1'b0;
        end else begin
            // Create temporary updated free_mask
            updated_mask = free_mask;
            
            // Apply free FIRST (combinational update)
            if (free_en)
                updated_mask[free_phys] = 1'b1;
                
            // Then allocation searches updated mask
            alloc_valid <= 1'b0;
            alloc_phys <= '0;
            
            if (alloc_en) begin
                for (int i = 0; i < PHYS_REGS; i++) begin
                    if (updated_mask[i]) begin
                        alloc_phys <= i;
                        alloc_valid <= 1'b1;
                        updated_mask[i] = 1'b0;  // Mark allocated
                        break;
                    end
                end
            end
            
            // Update actual free_mask with both operations
            free_mask <= updated_mask;
        end
    end

endmodule
