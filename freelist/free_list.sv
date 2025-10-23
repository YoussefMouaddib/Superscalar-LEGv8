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
    
    // Pipeline registers
    logic alloc_en_ff;
    logic free_en_ff;
    logic [5:0] free_phys_ff;

    // Stage 1: Register inputs
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            alloc_en_ff <= 1'b0;
            free_en_ff <= 1'b0;
            free_phys_ff <= '0;
        end else begin
            alloc_en_ff <= alloc_en;
            free_en_ff <= free_en;
            free_phys_ff <= free_phys;
        end
    end

    // Stage 2: Update free mask and handle allocation
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_mask <= {PHYS_REGS{1'b1}};
            alloc_phys <= '0;
            alloc_valid <= 1'b0;
        end else begin
            // Update free mask based on previous cycle's free operation
            if (free_en_ff) begin
                free_mask[free_phys_ff] <= 1'b1;
            end
            
            // Handle allocation using current free_mask
            alloc_valid <= 1'b0;
            alloc_phys <= '0;
            
            if (alloc_en_ff) begin
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
