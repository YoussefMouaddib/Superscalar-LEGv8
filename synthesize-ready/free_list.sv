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
    logic [5:0] alloc_ptr;
    
    // ============================================================
    // COMBINATIONAL - Parallel allocation (RENAME REGISTERS ONLY)
    // ============================================================
    
    logic [PHYS_REGS-1:0] temp_mask;
    logic [PHYS_REGS-1:0] mask_after_port0;
    logic [5:0] start_ptr;
    
    always_comb begin
        // Apply frees to create temporary mask
        temp_mask = free_mask;
        for (int j = 0; j < FREE_PORTS; j++) begin
            if (free_en[j]) begin
                temp_mask[free_phys[j]] = 1'b1;
            end
        end
    end
    
    always_comb begin
        // Port 0 allocation
        if (alloc_en[0]) begin
            alloc_valid[0] = 1'b0;
            alloc_phys[0] = '0;
            
            // Search only rename registers
            for (int i = 0; i < RENAME_REGS; i++) begin
                automatic int idx;
                idx = RENAME_START + ((alloc_ptr - RENAME_START + i) % RENAME_REGS);
                if (temp_mask[idx] && !alloc_valid[0]) begin
                    alloc_phys[0] = idx[5:0];
                    alloc_valid[0] = 1'b1;
                end
            end
        end else begin
            alloc_valid[0] = 1'b0;
            alloc_phys[0] = '0;
        end
    end
    
    always_comb begin
        // Create mask for port 1 (remove port 0's allocation)
        mask_after_port0 = temp_mask;
        if (alloc_en[0] && alloc_valid[0]) begin
            mask_after_port0[alloc_phys[0]] = 1'b0;
        end
    end
    
    always_comb begin
        // Port 1 allocation
        if (alloc_en[1]) begin
            alloc_valid[1] = 1'b0;
            alloc_phys[1] = '0;
            
            // Calculate start pointer for port 1
            if (alloc_en[0] && alloc_valid[0]) begin
                start_ptr = (alloc_phys[0] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
            end else begin
                start_ptr = alloc_ptr;
            end
            
            for (int i = 0; i < RENAME_REGS; i++) begin
                automatic int idx;
                idx = RENAME_START + ((start_ptr - RENAME_START + i) % RENAME_REGS);
                if (mask_after_port0[idx] && !alloc_valid[1]) begin
                    alloc_phys[1] = idx[5:0];
                    alloc_valid[1] = 1'b1;
                end
            end
        end else begin
            alloc_valid[1] = 1'b0;
            alloc_phys[1] = '0;
        end
    end
    
    // ============================================================
    // SEQUENTIAL Update
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // Only registers 32-63 are free
            for (int i = 0; i < PHYS_REGS; i++) begin
                if (i >= RENAME_START) begin
                    free_mask[i] <= 1'b1;
                end else begin
                    free_mask[i] <= 1'b0;
                end
            end
            alloc_ptr <= RENAME_START;
        end else begin
            // Apply frees and allocations
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en[j]) begin
                    free_mask[free_phys[j]] <= 1'b1;
                end
            end
            
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                if (alloc_en[a] && alloc_valid[a]) begin
                    free_mask[alloc_phys[a]] <= 1'b0;
                end
            end
            
            // Update pointer to next register after last allocation
            if (alloc_en[1] && alloc_valid[1]) begin
                alloc_ptr <= (alloc_phys[1] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
            end else if (alloc_en[0] && alloc_valid[0]) begin
                alloc_ptr <= (alloc_phys[0] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
            end
        end
    end
    
endmodule
