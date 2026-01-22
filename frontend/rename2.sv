`timescale 1ns/1ps
import core_pkg::*;
module rename_stage #(
    parameter int FETCH_W = 2,
    parameter int ARCH_REGS = 32,
    parameter int PHYS_REGS = 48
)(
    input  logic                    clk,
    input  logic                    reset,
    
    // From Decode
    input  logic [FETCH_W-1:0]      dec_valid,
    input  logic [FETCH_W-1:0][5:0] dec_opcode,
    input  logic [FETCH_W-1:0][4:0] dec_rs1,
    input  logic [FETCH_W-1:0][4:0] dec_rs2,
    input  logic [FETCH_W-1:0][4:0] dec_rd,
    input  logic [FETCH_W-1:0][31:0] dec_imm,
    input  logic [FETCH_W-1:0][31:0] dec_pc,
    input  logic [FETCH_W-1:0]      dec_rs1_valid,
    input  logic [FETCH_W-1:0]      dec_rs2_valid,
    input  logic [FETCH_W-1:0]      dec_rd_valid,
    input  logic [FETCH_W-1:0]      dec_is_alu,
    input  logic [FETCH_W-1:0]      dec_is_load,
    input  logic [FETCH_W-1:0]      dec_is_store,
    input logic [FETCH_W-1:0]      dec_is_branch,
    input  logic [FETCH_W-1:0]      dec_is_cas,
    input  logic [FETCH_W-1:0][5:0] dec_alu_func,
    
    // Backpressure to decode
    output logic                    rename_ready,
    
    // To Issue Queue / Dispatch
    output logic [FETCH_W-1:0]      rename_valid,
    output logic [FETCH_W-1:0][5:0] rename_opcode,
    output logic [FETCH_W-1:0][5:0] rename_prs1,   // Physical RS1
    output logic [FETCH_W-1:0][5:0] rename_prs2,   // Physical RS2
    output logic [FETCH_W-1:0][5:0] rename_prd,    // Physical RD
    output logic [FETCH_W-1:0][31:0] rename_imm,
    output logic [FETCH_W-1:0][31:0] rename_pc,
    output logic [FETCH_W-1:0]      rename_rs1_valid,
    output logic [FETCH_W-1:0]      rename_rs2_valid,
    output logic [FETCH_W-1:0]      rename_rd_valid,
    output logic [FETCH_W-1:0]      rename_is_alu,
    output logic [FETCH_W-1:0]      rename_is_load,
    output logic [FETCH_W-1:0]      rename_is_store,
    output logic [FETCH_W-1:0]      rename_is_branch,
    output logic [FETCH_W-1:0]      rename_is_cas,
    output logic [FETCH_W-1:0][5:0] rename_alu_func,
    
    // From Commit (write-back)
    input  logic                    commit_en,
    input  logic [4:0]              commit_arch_rd,
    input  logic [5:0]              commit_phys_rd
);
    
    // ============================================================
    //  Free List for Physical Register Allocation
    // ============================================================
    logic [FETCH_W-1:0] alloc_en;
    logic [FETCH_W-1:0][5:0] alloc_phys;
    logic [FETCH_W-1:0] alloc_valid;
    
    // We need separate free lists for each lane, or one that can allocate multiple
    // For simplicity, use one free_list that can allocate up to FETCH_W registers
    // but we need to handle allocation for multiple instructions
    
    // Create allocation requests
    always_comb begin
        for (int i = 0; i < FETCH_W; i++) begin
            alloc_en[i] = dec_valid[i] && dec_rd_valid[i] && (dec_rd[i] != 5'd0);
        end
    end
    
    // Instantiate free_list for each lane
    free_list #(
        .PHYS_REGS(PHYS_REGS)
    ) free_list_inst[FETCH_W-1:0] (
        .clk(clk),
        .reset(reset),
        .alloc_en(alloc_en),
        .alloc_phys(alloc_phys),
        .alloc_valid(alloc_valid),
        .free_en(commit_en && (commit_arch_rd != 5'd0)),
        .free_phys(commit_phys_rd)
    );
    
    // ============================================================
    //  Rename Table (Architectural → Physical Mapping)
    // ============================================================
    logic [4:0] rename_arch_rd[FETCH_W-1:0];
    logic [5:0] rename_new_phys_rd[FETCH_W-1:0];
    logic [FETCH_W-1:0] rename_en;
    
    // Map each lane's RS1/RS2 to physical registers
    logic [FETCH_W-1:0][5:0] phys_rs1;
    logic [FETCH_W-1:0][5:0] phys_rs2;
    
    // Instantiate rename tables for each architectural register port
    rename_table #(
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS)
    ) rename_table_inst[FETCH_W-1:0] (
        .clk(clk),
        .reset(reset),
        .arch_rs1(dec_rs1),
        .arch_rs2(dec_rs2),
        .phys_rs1(phys_rs1),
        .phys_rs2(phys_rs2),
        .rename_en(rename_en),
        .arch_rd(rename_arch_rd),
        .new_phys_rd(rename_new_phys_rd),
        .commit_en(commit_en),
        .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd)
    );
    
    // ============================================================
    //  Rename Logic
    // ============================================================
    always_comb begin
        // Default values
        rename_en = '0;
        for (int i = 0; i < FETCH_W; i++) begin
            rename_arch_rd[i] = 5'd0;
            rename_new_phys_rd[i] = 6'd0;
            
            // Enable rename if instruction has a destination register (not X0)
            if (dec_valid[i] && dec_rd_valid[i] && (dec_rd[i] != 5'd0)) begin
                rename_en[i] = alloc_valid[i];  // Only rename if allocation succeeded
                rename_arch_rd[i] = dec_rd[i];
                rename_new_phys_rd[i] = alloc_phys[i];
            end
        end
    end
    
    // ============================================================
    //  Pipeline Registers (Decode → Rename)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            rename_valid <= '0;
            rename_opcode <= '0;
            rename_prs1 <= '0;
            rename_prs2 <= '0;
            rename_prd <= '0;
            rename_imm <= '0;
            rename_pc <= '0;
            rename_rs1_valid <= '0;
            rename_rs2_valid <= '0;
            rename_rd_valid <= '0;
            rename_is_alu <= '0;
            rename_is_load <= '0;
            rename_is_store <= '0;
            rename_is_branch <= '0;
            rename_is_cas <= '0;
            rename_alu_func <= '0;
        end else begin
            for (int i = 0; i < FETCH_W; i++) begin
                if (rename_ready) begin
                    rename_valid[i] <= dec_valid[i];
                    rename_opcode[i] <= dec_opcode[i];
                    rename_imm[i] <= dec_imm[i];
                    rename_pc[i] <= dec_pc[i];
                    rename_alu_func[i] <= dec_alu_func[i];
                    rename_is_alu[i] <= dec_is_alu[i];
                    rename_is_load[i] <= dec_is_load[i];
                    rename_is_store[i] <= dec_is_store[i];
                    rename_is_branch[i] <= dec_is_branch[i];
                    rename_is_cas[i] <= dec_is_cas[i];
                    
                    // Pass through register valid flags
                    rename_rs1_valid[i] <= dec_rs1_valid[i];
                    rename_rs2_valid[i] <= dec_rs2_valid[i];
                    
                    // Handle X0 special case (always physical register 0)
                    if (dec_rd[i] == 5'd0) begin
                        rename_prd[i] <= 6'd0;
                        rename_rd_valid[i] <= 1'b0;  // X0 writes are no-ops
                    end else if (dec_rd_valid[i] && alloc_valid[i]) begin
                        rename_prd[i] <= alloc_phys[i];
                        rename_rd_valid[i] <= 1'b1;
                    end else begin
                        rename_prd[i] <= 6'd0;
                        rename_rd_valid[i] <= 1'b0;
                    end
                    
                    // Map source registers to physical registers
                    if (dec_rs1_valid[i]) begin
                        // X0 always maps to physical register 0
                        rename_prs1[i] <= (dec_rs1[i] == 5'd0) ? 6'd0 : phys_rs1[i];
                    end else begin
                        rename_prs1[i] <= 6'd0;
                    end
                    
                    if (dec_rs2_valid[i]) begin
                        rename_prs2[i] <= (dec_rs2[i] == 5'd0) ? 6'd0 : phys_rs2[i];
                    end else begin
                        rename_prs2[i] <= 6'd0;
                    end
                end else begin
                    // If rename not ready, hold current values (stall)
                    // rename_valid[i] stays the same (others too)
                end
            end
        end
    end
    
    // ============================================================
    //  Backpressure Logic
    // ============================================================
    // For now, always ready unless we run out of physical registers
    // Check if we can allocate all needed physical registers
    logic can_allocate_all;
    always_comb begin
        can_allocate_all = 1'b1;
        for (int i = 0; i < FETCH_W; i++) begin
            if (dec_valid[i] && dec_rd_valid[i] && (dec_rd[i] != 5'd0)) begin
                if (!alloc_valid[i]) begin
                    can_allocate_all = 1'b0;
                end
            end
        end
        rename_ready = can_allocate_all;
    end
    
    // ============================================================
    //  Debug/Validation
    // ============================================================
    // Count free physical registers
    logic [6:0] free_count;
    always_comb begin
        free_count = '0;
        // This would require looking inside free_list
        // For now, we'll trust alloc_valid signals
    end

endmodule
//===========================================================
//  Rename Table (Architectural → Physical Mapping)
//  Updated for array interface
//===========================================================
module rename_table #(
    parameter int ARCH_REGS = 32,
    parameter int PHYS_REGS = 48
)(
    input  logic              clk,
    input  logic              reset,

    // Lookup (read mapping) - per lane
    input  logic [4:0]        arch_rs1,
    input  logic [4:0]        arch_rs2,
    output logic [5:0]        phys_rs1,
    output logic [5:0]        phys_rs2,

    // Rename (new destination mapping) - per lane
    input  logic              rename_en,
    input  logic [4:0]        arch_rd,
    input  logic [5:0]        new_phys_rd,

    // Commit (restore architectural state)
    input  logic              commit_en,
    input  logic [4:0]        commit_arch_rd,
    input  logic [5:0]        commit_phys_rd
);

    logic [5:0] map_table [ARCH_REGS-1:0];  // current mapping
    logic [5:0] committed_table [ARCH_REGS-1:0]; // committed mapping (for recovery)

    // Read current mapping - X0 always maps to physical register 0
    assign phys_rs1 = (arch_rs1 == 5'd0) ? 6'd0 : map_table[arch_rs1];
    assign phys_rs2 = (arch_rs2 == 5'd0) ? 6'd0 : map_table[arch_rs2];

    // Update mapping on rename or commit
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                map_table[i]       <= 6'(i);  // Initial mapping: arch -> same phys
                committed_table[i] <= 6'(i);
            end
        end else begin
            // Rename: update speculative mapping
            if (rename_en && arch_rd != 5'd0) begin  // Don't rename X0
                map_table[arch_rd] <= new_phys_rd;
            end
            
            // Commit: update committed mapping (for misprediction recovery)
            if (commit_en && commit_arch_rd != 5'd0) begin
                committed_table[commit_arch_rd] <= commit_phys_rd;
            end
        end
    end

endmodule

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
    logic [PHYS_REGS-1:0] updated_mask;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            free_mask <= {PHYS_REGS{1'b1}};
            alloc_phys <= '0;
            alloc_valid <= 1'b0;
        end else begin
            // Create temporary updated free_mask
            updated_mask = free_mask;
            
            // Apply free FIRST (combinational update)
            if (free_en)
                updated_mask[free_phys] = 1'b1;
                
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
