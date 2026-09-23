module free_list #(
    parameter int PHYS_REGS = 64,
    parameter int RENAME_START = 32,
    parameter int ALLOC_PORTS = 2,
    parameter int FREE_PORTS = 2,
    parameter int NUM_CHECKPOINTS = 8
)(
    input  logic         clk,
    input  logic         reset,
    
    // Flush / Recovery
    input  logic         flush_pipeline,
    input  logic         restore_en,
    input  logic [$clog2(NUM_CHECKPOINTS)-1:0] restore_id,
    
    // Branch Checkpoint Take
    input  logic         checkpoint_en,
    input  logic [$clog2(NUM_CHECKPOINTS)-1:0] checkpoint_id,

    // Allocation & Free
    input  logic [ALLOC_PORTS-1:0]      alloc_en,
    output logic [ALLOC_PORTS-1:0][5:0] alloc_phys,
    output logic [ALLOC_PORTS-1:0]      alloc_valid,
    
    input  logic [FREE_PORTS-1:0]      free_en,
    input  logic [FREE_PORTS-1:0][5:0] free_phys
);
    
    logic [PHYS_REGS-1:0] free_mask;
    logic [NUM_CHECKPOINTS-1:0][PHYS_REGS-1:0] checkpoint_masks;
    
    // Pipeline registers for free operations
    logic [FREE_PORTS-1:0]      free_en_r;
    logic [FREE_PORTS-1:0][5:0] free_phys_r;
    
    // Combinational allocation results
    logic [ALLOC_PORTS-1:0][5:0] alloc_phys_comb;
    logic [ALLOC_PORTS-1:0]      alloc_valid_comb;
    logic [PHYS_REGS-1:0]        temp_mask;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_en_r <= '0;
            free_phys_r <= '0;
        end else begin
            free_en_r <= free_en;
            free_phys_r <= free_phys;
        end
    end
    
    always_comb begin
        temp_mask = free_mask;
        for (int j = 0; j < FREE_PORTS; j++) begin
            if (free_en_r[j]) begin
                temp_mask[free_phys_r[j]] = 1'b1;
            end
        end
    end
    
    // Port 0 allocation
    always_comb begin
        alloc_valid_comb[0] = 1'b0;
        alloc_phys_comb[0] = '0;
        if (alloc_en[0]) begin
            for (int i = RENAME_START; i < PHYS_REGS; i++) begin
                if (temp_mask[i] && !alloc_valid_comb[0]) begin
                    alloc_phys_comb[0] = i[5:0];
                    alloc_valid_comb[0] = 1'b1;
                end
            end
        end
    end
    
    // Port 1 allocation
    logic [PHYS_REGS-1:0] mask_after_port0;
    always_comb begin
        mask_after_port0 = temp_mask;
        if (alloc_en[0] && alloc_valid_comb[0]) begin
            mask_after_port0[alloc_phys_comb[0]] = 1'b0;
        end
        
        alloc_valid_comb[1] = 1'b0;
        alloc_phys_comb[1] = '0;
        if (alloc_en[1]) begin
            for (int i = RENAME_START; i < PHYS_REGS; i++) begin
                if (mask_after_port0[i] && !alloc_valid_comb[1]) begin
                    alloc_phys_comb[1] = i[5:0];
                    alloc_valid_comb[1] = 1'b1;
                end
            end
        end
    end
    
    // Sequential State Update
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < PHYS_REGS; i++) begin
                free_mask[i] <= (i >= RENAME_START) ? 1'b1 : 1'b0;
            end
            checkpoint_masks <= '0;
            alloc_phys <= '0;
            alloc_valid <= '0;
        end else if (flush_pipeline && restore_en) begin
            // Restore free mask from branch snapshot on mispredict
            free_mask <= checkpoint_masks[restore_id];
            alloc_valid <= '0;
            alloc_phys <= '0;
        end else begin
            // Save checkpoint if a branch is being renamed
            if (checkpoint_en) begin
                checkpoint_masks[checkpoint_id] <= free_mask;
            end

            // Apply frees
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en_r[j]) begin
                    free_mask[free_phys_r[j]] <= 1'b1;
                end
            end
            
            // Apply allocations
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                if (alloc_en[a] && alloc_valid_comb[a]) begin
                    free_mask[alloc_phys_comb[a]] <= 1'b0;
                end
            end
            
            alloc_phys <= alloc_phys_comb;
            alloc_valid <= alloc_valid_comb;
        end
    end

endmodule
