`timescale 1ns/1ps

module free_list #(
    parameter int PHYS_REGS       = 64,
    parameter int RENAME_START    = 32,
    parameter int ALLOC_PORTS     = 2,
    parameter int FREE_PORTS      = 2,
    parameter int NUM_CHECKPOINTS = 8
)(
    input  logic clk,
    input  logic reset,

    input  logic flush_pipeline,
    input  logic restore_en,
    input  logic [$clog2(NUM_CHECKPOINTS)-1:0] restore_id,

    input  logic [ALLOC_PORTS-1:0] checkpoint_en,
    input  logic [ALLOC_PORTS-1:0][$clog2(NUM_CHECKPOINTS)-1:0]
                                             checkpoint_id,

    input  logic [ALLOC_PORTS-1:0]      alloc_en,
    output logic [ALLOC_PORTS-1:0][5:0] alloc_phys,
    output logic [ALLOC_PORTS-1:0]      alloc_valid,

    input  logic [FREE_PORTS-1:0]      free_en,
    input  logic [FREE_PORTS-1:0][5:0] free_phys
);

    logic [PHYS_REGS-1:0] free_mask;
    logic [NUM_CHECKPOINTS-1:0][PHYS_REGS-1:0] checkpoint_masks;
    logic [NUM_CHECKPOINTS-1:0][PHYS_REGS-1:0] checkpoint_masks_next;

    logic [FREE_PORTS-1:0]      free_en_r;
    logic [FREE_PORTS-1:0][5:0] free_phys_r;

    logic [PHYS_REGS-1:0] mask_base;
    logic [PHYS_REGS-1:0] alloc_mask_work;
    logic [PHYS_REGS-1:0] snapshot_mask_work;
    logic [PHYS_REGS-1:0] free_mask_next;

    logic [ALLOC_PORTS-1:0][5:0] alloc_phys_comb;
    logic [ALLOC_PORTS-1:0]      alloc_valid_comb;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_en_r   <= '0;
            free_phys_r <= '0;
        end else begin
            free_en_r   <= free_en;
            free_phys_r <= free_phys;
        end
    end

    // Registered frees are visible to allocation this cycle.
    always_comb begin
        mask_base = free_mask;

        for (int f = 0; f < FREE_PORTS; f++) begin
            if (free_en_r[f] && free_phys_r[f] < PHYS_REGS)
                mask_base[free_phys_r[f]] = 1'b1;
        end
    end

    // Allocation, in lane order.
    always_comb begin
        alloc_mask_work = mask_base;
        alloc_phys_comb = '0;
        alloc_valid_comb = '0;

        for (int a = 0; a < ALLOC_PORTS; a++) begin
            if (alloc_en[a]) begin
                for (int p = RENAME_START; p < PHYS_REGS; p++) begin
                    if (alloc_mask_work[p] && !alloc_valid_comb[a]) begin
                        alloc_phys_comb[a] = 6'(p);
                        alloc_valid_comb[a] = 1'b1;
                    end
                end
            end

            if (alloc_en[a] && alloc_valid_comb[a])
                alloc_mask_work[alloc_phys_comb[a]] = 1'b0;
        end

        free_mask_next = alloc_mask_work;
    end

    // Existing snapshots receive frees from older committed
    // instructions. New snapshots are then constructed in lane order.
    always_comb begin
        checkpoint_masks_next = checkpoint_masks;
        snapshot_mask_work = mask_base;

        for (int cp = 0; cp < NUM_CHECKPOINTS; cp++) begin
            for (int f = 0; f < FREE_PORTS; f++) begin
                if (free_en_r[f] && free_phys_r[f] < PHYS_REGS)
                    checkpoint_masks_next[cp][free_phys_r[f]] = 1'b1;
            end
        end

        for (int a = 0; a < ALLOC_PORTS; a++) begin
            if (alloc_en[a] && alloc_valid_comb[a])
                snapshot_mask_work[alloc_phys_comb[a]] = 1'b0;

            if (checkpoint_en[a])
                checkpoint_masks_next[checkpoint_id[a]] =
                    snapshot_mask_work;
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_mask <= '0;
            checkpoint_masks <= '0;
            alloc_phys <= '0;
            alloc_valid <= '0;

            for (int p = 0; p < PHYS_REGS; p++)
                free_mask[p] <= (p >= RENAME_START);
        end else if (flush_pipeline && restore_en) begin
            free_mask <= checkpoint_masks[restore_id];
            checkpoint_masks <= checkpoint_masks_next;
            alloc_phys <= '0;
            alloc_valid <= '0;
        end else begin
            free_mask <= free_mask_next;
            checkpoint_masks <= checkpoint_masks_next;
            alloc_phys <= alloc_phys_comb;
            alloc_valid <= alloc_valid_comb;
        end
    end

endmodule
