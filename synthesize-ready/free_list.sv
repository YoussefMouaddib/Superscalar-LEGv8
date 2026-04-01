module free_list #(
    parameter int PHYS_REGS = 64,
    parameter int RENAME_START = 32,  // First rename register
    parameter int RENAME_REGS = 32,    // Number of rename registers
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
    always_comb begin
        temp_mask = free_mask;
        for (int j = 0; j < FREE_PORTS; j++) begin
            if (free_en[j]) begin
                temp_mask[free_phys[j]] = 1'b1;
            end
        end
    end
    
    logic [PHYS_REGS-1:0] mask_after_port0;
    
    always_comb begin
        // Port 0 allocation (only search rename registers)
        if (alloc_en[0]) begin
            alloc_valid[0] = 1'b0;
            alloc_phys[0] = '0;
            
            // Search only RENAME_REGS slots, starting from alloc_ptr
            for (int i = 0; i < RENAME_REGS; i++) begin
                // Map i to a rename register with wrap within rename pool
                int idx = RENAME_START + ((alloc_ptr - RENAME_START + i) % RENAME_REGS);
                if (temp_mask[idx] && !alloc_valid[0]) begin
                    alloc_phys[0] = idx;
                    alloc_valid[0] = 1'b1;
                end
            end
        end else begin
            alloc_valid[0] = 1'b0;
            alloc_phys[0] = '0;
        end
        
        // Create mask for port 1
        mask_after_port0 = temp_mask;
        if (alloc_en[0] && alloc_valid[0]) begin
            mask_after_port0[alloc_phys[0]] = 1'b0;
        end
        
        // Port 1 allocation
        if (alloc_en[1]) begin
            alloc_valid[1] = 1'b0;
            alloc_phys[1] = '0;
            
            // Start pointer for port 1
            logic [5:0] start_ptr;
            if (alloc_en[0] && alloc_valid[0]) begin
                start_ptr = (alloc_phys[0] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
            end else begin
                start_ptr = alloc_ptr;
            end
            
            for (int i = 0; i < RENAME_REGS; i++) begin
                int idx = RENAME_START + ((start_ptr - RENAME_START + i) % RENAME_REGS);
                if (mask_after_port0[idx] && !alloc_valid[1]) begin
                    alloc_phys[1] = idx;
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
                free_mask[i] <= (i >= RENAME_START) ? 1'b1 : 1'b0;
            end
            alloc_ptr <= RENAME_START;
        end else begin
            logic [PHYS_REGS-1:0] new_mask = free_mask;
            
            // Apply frees
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en[j]) begin
                    new_mask[free_phys[j]] = 1'b1;
                end
            end
            
            // Apply allocations
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                if (alloc_en[a] && alloc_valid[a]) begin
                    new_mask[alloc_phys[a]] = 1'b0;
                end
            end
            
            free_mask <= new_mask;
            
            // Update pointer to next register after last allocation
            if (alloc_en[1] && alloc_valid[1]) begin
                alloc_ptr <= (alloc_phys[1] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
            end else if (alloc_en[0] && alloc_valid[0]) begin
                alloc_ptr <= (alloc_phys[0] + 1 - RENAME_START) % RENAME_REGS + RENAME_START;
            end
        end
    end
    
endmodule
