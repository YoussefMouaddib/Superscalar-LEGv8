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

    // next allocation logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_mask <= {PHYS_REGS{1'b1}}; // all registers free
        end else begin
            if (alloc_en) begin
                for (int i = 0; i < PHYS_REGS; i++) begin
                    if (free_mask[i]) begin
                        free_mask[i] <= 1'b0; // allocate
                        alloc_phys  <= i;
                        alloc_valid <= 1'b1;
                        disable for;
                    end
                end
                // if none free
                if (!alloc_valid)
                    alloc_phys <= 0;
            end else
                alloc_valid <= 1'b0;

            if (free_en)
                free_mask[free_phys] <= 1'b1; // release
        end
    end
endmodule
