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
    
    // Pipeline registers for free operations
    logic [FREE_PORTS-1:0]      free_en_r;
    logic [FREE_PORTS-1:0][5:0] free_phys_r;
    
    // Pipeline registers for allocation results
    logic [ALLOC_PORTS-1:0][5:0] alloc_phys_comb;
    logic [ALLOC_PORTS-1:0]     alloc_valid_comb;
    logic [5:0]                 alloc_ptr_next;
    
    // Stage 1: Register free inputs
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_en_r <= '0;
            free_phys_r <= '0;
        end else begin
            free_en_r <= free_en;
            free_phys_r <= free_phys;
        end
    end
    
    // Stage 1 combinational: Apply frees and compute allocation
    logic [PHYS_REGS-1:0] temp_mask;
    logic [PHYS_REGS-1:0] mask_after_port0;
    logic [5:0] start_ptr;
    
    always_comb begin
        // Apply frees to create temporary mask
        temp_mask = free_mask;
        for (int j = 0; j < FREE_PORTS; j++) begin
            if (free_en_r[j]) begin
                temp_mask[free_phys_r[j]] = 1'b1;
            end
        end
    end
    
    always_comb begin
        // Port 0 allocation
        if (alloc_en[0]) begin
            alloc_valid_comb[0] = 1'b0;
            alloc_phys_comb[0] = '0;
            
            for (int i = 0; i < RENAME_REGS; i++) begin
                automatic int idx = RENAME_START + ((alloc_ptr - RENAME_START + i) % RENAME_REGS);
                if (temp_mask[idx] && !alloc_valid_comb[0]) begin
                    alloc_phys_comb[0] = idx[5:0];
                    alloc_valid_comb[0] = 1'b1;
                end
            end
        end else begin
            alloc_valid_comb[0] = 1'b0;
            alloc_phys_comb[0] = '0;
        end
    end
    
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
            
            if (alloc_en[0] && alloc_valid_comb[0]) begin
                start_ptr = (alloc_phys_comb[0] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
            end else begin
                start_ptr = alloc_ptr;
            end
            
            for (int i = 0; i < RENAME_REGS; i++) begin
                automatic int idx = RENAME_START + ((start_ptr - RENAME_START + i) % RENAME_REGS);
                if (mask_after_port0[idx] && !alloc_valid_comb[1]) begin
                    alloc_phys_comb[1] = idx[5:0];
                    alloc_valid_comb[1] = 1'b1;
                end
            end
        end else begin
            alloc_valid_comb[1] = 1'b0;
            alloc_phys_comb[1] = '0;
        end
    end
    
    // Compute next alloc_ptr
    always_comb begin
        if (alloc_en[1] && alloc_valid_comb[1]) begin
            alloc_ptr_next = (alloc_phys_comb[1] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
        end else if (alloc_en[0] && alloc_valid_comb[0]) begin
            alloc_ptr_next = (alloc_phys_comb[0] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
        end else begin
            alloc_ptr_next = alloc_ptr;
        end
    end
    
    // Stage 2: Register allocation results and update free_mask
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < PHYS_REGS; i++) begin
                free_mask[i] <= (i >= RENAME_START) ? 1'b1 : 1'b0;
            end
            alloc_ptr <= RENAME_START;
            alloc_phys <= '0;
            alloc_valid <= '0;
        end else begin
            // Update free_mask
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en_r[j]) begin
                    free_mask[free_phys_r[j]] <= 1'b1;
                end
            end
            
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                if (alloc_en[a] && alloc_valid_comb[a]) begin
                    free_mask[alloc_phys_comb[a]] <= 1'b0;
                end
            end
            
            // Update alloc_ptr
            alloc_ptr <= alloc_ptr_next;
            
            // Register outputs
            alloc_phys <= alloc_phys_comb;
            alloc_valid <= alloc_valid_comb;
        end
    end

endmodule
