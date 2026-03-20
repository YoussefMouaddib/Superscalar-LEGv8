module free_list #(
    parameter int PHYS_REGS = 64,
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
    
    logic [63:0] free_mask;
    logic [5:0] alloc_ptr;  // ← NEW: Round-robin pointer
    
    // ============================================================
    // COMBINATIONAL Allocation Logic (ROUND-ROBIN)
    // ============================================================
    always_comb begin
        automatic logic [63:0] temp_mask;
        automatic logic [5:0] search_ptr;
        automatic int searches;
        
        temp_mask = free_mask;
        
        // Apply frees
        for (int j = 0; j < FREE_PORTS; j++) begin
            if (free_en[j]) begin
                temp_mask[free_phys[j]] = 1'b1;
            end
        end
        
        search_ptr = alloc_ptr;  // Start searching from last allocation
        
        // Allocate each port
        for (int a = 0; a < ALLOC_PORTS; a++) begin
            alloc_valid[a] = 1'b0;
            alloc_phys[a] = '0;
            
            if (alloc_en[a]) begin
                searches = 0;
                
                // Search starting from search_ptr, wrap around
                while (searches < 32) begin  // Only search rename pool (p32-p63)
                    // Compute actual index (wrap within p32-p63)
                    automatic int idx = 32 + ((search_ptr - 32) % 32);
                    
                    if (temp_mask[idx]) begin
                        alloc_phys[a] = 6'(idx);
                        alloc_valid[a] = 1'b1;
                        temp_mask[idx] = 1'b0;
                        search_ptr = (idx + 1) % 64;  // Next search starts here
                        break;
                    end
                    
                    search_ptr = 32 + ((search_ptr - 32 + 1) % 32);
                    searches++;
                end
            end
        end
    end
    
    // ============================================================
    // SEQUENTIAL Update
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        automatic logic [63:0] updated_mask;
        automatic logic [5:0] new_alloc_ptr;
        
        if (reset) begin
            // Physical regs 0-31 NOT free, 32-63 FREE
            for (int i = 0; i < 32; i++) begin
                free_mask[i] <= 1'b0;
            end
            for (int i = 32; i < 64; i++) begin
                free_mask[i] <= 1'b1;
            end
            
            alloc_ptr <= 6'd32;  // Start at p32
            
        end else begin
            updated_mask = free_mask;
            new_alloc_ptr = alloc_ptr;
            
            // Apply frees
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en[j]) begin
                    updated_mask[free_phys[j]] = 1'b1;
                end
            end
            
            // Apply allocations
            for (int a = 0; a < ALLOC_PORTS; a++) begin
                if (alloc_en[a] && alloc_valid[a]) begin
                    updated_mask[alloc_phys[a]] = 1'b0;
                    new_alloc_ptr = (alloc_phys[a] + 1);  // Move pointer forward
                    if (new_alloc_ptr >= 64 || new_alloc_ptr < 32) begin
                        new_alloc_ptr = 32;  // Wrap to p32
                    end
                end
            end
            
            free_mask <= updated_mask;
            alloc_ptr <= new_alloc_ptr;
        end
    end
    
endmodule
