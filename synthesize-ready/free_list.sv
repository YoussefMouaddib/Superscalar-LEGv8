module free_list #(
    parameter int PHYS_REGS = 64,
    parameter int RENAME_START = 32,
    parameter int RENAME_REGS = 32,
    parameter int ALLOC_PORTS = 2,
    parameter int FREE_PORTS = 2
)(
    input  logic         clk,
    input  logic         reset,
    
    input  logic [ALLOC_PORTS-1:0]     alloc_en,
    output logic [ALLOC_PORTS-1:0][5:0] alloc_phys,
    output logic [ALLOC_PORTS-1:0]     alloc_valid,
    
    input  logic [FREE_PORTS-1:0]      free_en,
    input  logic [FREE_PORTS-1:0][5:0] free_phys
);
    
    logic [PHYS_REGS-1:0] free_mask;
    
    // Pipeline registers for free operations (freeing can be slow)
    logic [FREE_PORTS-1:0]      free_en_r;
    logic [FREE_PORTS-1:0][5:0] free_phys_r;
    
    // Combinational allocation results
    logic [ALLOC_PORTS-1:0][5:0] alloc_phys_comb;
    logic [ALLOC_PORTS-1:0]     alloc_valid_comb;
    
    // Register free inputs (1 cycle delay — fine, freeing isn't critical)
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_en_r <= '0;
            free_phys_r <= '0;
        end else begin
            free_en_r <= free_en;
            free_phys_r <= free_phys;
        end
    end
    
    // ============================================================
    // COMBINATIONAL ALLOCATION — NO ROUND-ROBIN, JUST FIRST FREE
    // ============================================================
    logic [PHYS_REGS-1:0] temp_mask;
    
    always_comb begin
        // Start with current free_mask
        temp_mask = free_mask;
        
        // Apply pending frees (from registered inputs)
        for (int j = 0; j < FREE_PORTS; j++) begin
            if (free_en_r[j]) begin
                temp_mask[free_phys_r[j]] = 1'b1;
            end
        end
    end
    
    // Port 0 allocation: find first free register starting from RENAME_START
    always_comb begin
        if (alloc_en[0]) begin
            alloc_valid_comb[0] = 1'b0;
            alloc_phys_comb[0] = '0;
            
            for (int i = RENAME_START; i < PHYS_REGS; i++) begin
                if (temp_mask[i] && !alloc_valid_comb[0]) begin
                    alloc_phys_comb[0] = i[5:0];
                    alloc_valid_comb[0] = 1'b1;
                end
            end
        end else begin
            alloc_valid_comb[0] = 1'b0;
            alloc_phys_comb[0] = '0;
        end
    end
    
    // Port 1 allocation: find second free register (after removing port 0's allocation)
    logic [PHYS_REGS-1:0] mask_after_port0;
    
    always_comb begin
        mask_after_port0 = temp_mask;
        if (alloc_en[0] && alloc_valid_comb[0]) begin
            mask_after_port0[alloc_phys_comb[0]] = 1'b0;
        end
    end
    
    always_comb begin
        if (alloc_en[1]) begin
            alloc_valid_comb[1] = 1'b0;
            alloc_phys_comb[1] = '0;
            
            for (int i = RENAME_START; i < PHYS_REGS; i++) begin
                if (mask_after_port0[i] && !alloc_valid_comb[1]) begin
                    alloc_phys_comb[1] = i[5:0];
                    alloc_valid_comb[1] = 1'b1;
                end
            end
        end else begin
            alloc_valid_comb[1] = 1'b0;
            alloc_phys_comb[1] = '0;
        end
    end
    
    // ============================================================
    // SEQUENTIAL UPDATE (free_mask and outputs)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize: only rename registers (RENAME_START to PHYS_REGS-1) are free
            for (int i = 0; i < PHYS_REGS; i++) begin
                free_mask[i] <= (i >= RENAME_START) ? 1'b1 : 1'b0;
            end
            alloc_phys <= '0;
            alloc_valid <= '0;
            
        end else begin
            // Update free_mask: apply frees (from registered inputs)
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en_r[j]) begin
                    free_mask[free_phys_r[j]] <= 1'b1;
                end
            end
            
            // Update free_mask: apply allocations (from combinational results)
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                if (alloc_en[a] && alloc_valid_comb[a]) begin
                    free_mask[alloc_phys_comb[a]] <= 1'b0;
                end
            end
            
            // Register outputs (1 cycle delay for allocation)
            alloc_phys <= alloc_phys_comb;
            alloc_valid <= alloc_valid_comb;
        end
    end

endmodule
