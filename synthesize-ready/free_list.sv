module free_list #(
    parameter int PHYS_REGS = core_pkg::PREGS,
    parameter int FREE_PORTS = 2  // Support multiple frees per cycle from commit
)(
    input  logic         clk,
    input  logic         reset,

    // Allocate a new physical register
    input  logic         alloc_en,
    output logic [5:0]   alloc_phys,
    output logic         alloc_valid,  // high if allocation succeeded

    // Release physical registers back to free list (MODIFIED for multiple ports)
    input  logic [FREE_PORTS-1:0]     free_en,      // Multiple free enables
    input  logic [5:0]                free_phys[FREE_PORTS-1:0]  // Multiple tags
);

    // internal bitmask: 1 = free, 0 = allocated
    logic [PHYS_REGS-1:0] free_mask;
    logic [PHYS_REGS-1:0] updated_mask;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize: Physical regs 0-31 correspond to architectural regs (not free)
            // Physical regs 32-47 are available for renaming (free)
            for (int i = 0; i < core_pkg::ARCH_REGS; i++) begin
                free_mask[i] <= 1'b0;  // Arch regs not in free pool initially
            end
            for (int i = core_pkg::ARCH_REGS; i < PHYS_REGS; i++) begin
                free_mask[i] <= 1'b1;  // Rename regs are free
            end
            alloc_phys <= '0;
            alloc_valid <= 1'b0;
        end else begin
            // Create temporary updated free_mask
            updated_mask = free_mask;
            
            // Apply all frees FIRST (combinational update)
            for (int j = 0; j < FREE_PORTS; j++) begin
                if (free_en[j]) begin
                    updated_mask[free_phys[j]] = 1'b1;
                end
            end
                
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
