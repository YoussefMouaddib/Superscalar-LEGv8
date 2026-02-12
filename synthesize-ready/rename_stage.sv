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
    input  logic [FETCH_W-1:0]      dec_is_branch,
    input  logic [FETCH_W-1:0]      dec_is_cas,
    input  logic [FETCH_W-1:0][5:0] dec_alu_func,
    
    // Backpressure to decode
    output logic                    rename_ready,
    
    // To Issue Queue / Dispatch
    output logic [FETCH_W-1:0]      rename_valid,
    output logic [FETCH_W-1:0][5:0] rename_opcode,
    output logic [FETCH_W-1:0][5:0] rename_prs1,
    output logic [FETCH_W-1:0][5:0] rename_prs2,
    output logic [FETCH_W-1:0][5:0] rename_prd,
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
    
    output logic [FETCH_W-1:0][4:0] rename_arch_rs1,
    output logic [FETCH_W-1:0][4:0] rename_arch_rs2,
    output logic [FETCH_W-1:0][4:0] rename_arch_rd,
    
    
    
    // From Commit (write-back)
    input  logic [FETCH_W-1:0]      commit_en,
    input  logic [1:0][4:0]              commit_arch_rd,
    input  logic [1:0][5:0]              commit_phys_rd,
    
    // Flush signal from commit
    input  logic                    flush_pipeline
);
    
    // ============================================================
    //  Free List for Physical Register Allocation
    //  FIXED: Single instance handling multiple allocations
    // ============================================================
    logic [FETCH_W-1:0] alloc_en;
    logic [FETCH_W-1:0][5:0] alloc_phys;
    logic [FETCH_W-1:0] alloc_valid;
    
    // Create allocation requests
    always_comb begin
        for (int i = 0; i < FETCH_W; i++) begin
            alloc_en[i] = dec_valid[i] && dec_rd_valid[i] && (dec_rd[i] != 5'd0) && !flush_pipeline;
        end
    end
    
    // FIXED: Single free_list instance with multi-port allocation and free
    free_list #(
        .PHYS_REGS(PHYS_REGS),
        .ALLOC_PORTS(FETCH_W),
        .FREE_PORTS(FETCH_W)
    ) free_list_inst (
        .clk(clk),
        .reset(reset),
        // Allocation (multi-port)
        .alloc_en(alloc_en),
        .alloc_phys(alloc_phys),
        .alloc_valid(alloc_valid),
        // Free (multi-port)
        .free_en(commit_en),
        .free_phys(commit_phys_rd)
    );
    
    // ============================================================
    //  Rename Table (Architectural → Physical Mapping)
    //  FIXED: Single instance with multi-port lookups
    // ============================================================
    
    logic [1:0][5:0] rename_new_phys_rd;
    logic [FETCH_W-1:0] rename_en;
    
    // Map each lane's RS1/RS2 to physical registers
    logic [FETCH_W-1:0][5:0] phys_rs1;
    logic [FETCH_W-1:0][5:0] phys_rs2;
    logic [FETCH_W-1:0][4:0] rename_arch_rd_wire;
    
    // FIXED: Single rename_table instance with array ports
    rename_table #(
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS),
        .LOOKUP_PORTS(FETCH_W),
        .RENAME_PORTS(FETCH_W),
        .COMMIT_PORTS(FETCH_W)
    ) rename_table_inst (
        .clk(clk),
        .reset(reset),
        // Lookups (multi-port reads)
        .arch_rs1(dec_rs1),
        .arch_rs2(dec_rs2),
        .phys_rs1(phys_rs1),
        .phys_rs2(phys_rs2),
        // Renames (multi-port updates)
        .rename_en(rename_en),
        .arch_rd(rename_arch_rd_wire),
        .new_phys_rd(rename_new_phys_rd),
        // Commits (multi-port committed state updates)
        .commit_en(commit_en),
        .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd),
        .flush_pipeline(flush_pipeline)
    );
    
    // ============================================================
    //  Rename Logic
    // ============================================================
    always_comb begin
        // Default values
        rename_en = '0;
        for (int i = 0; i < FETCH_W; i++) begin
            rename_arch_rd_wire[i] = 5'd0;
            rename_new_phys_rd[i] = 6'd0;
            
            // Enable rename if instruction has a destination register (not X0) and not flushing
            if (dec_valid[i] && dec_rd_valid[i] && (dec_rd[i] != 5'd0) && !flush_pipeline) begin
                rename_en[i] = alloc_valid[i];  // Only rename if allocation succeeded
                rename_arch_rd_wire[i] = dec_rd[i];
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
            rename_arch_rs1 <= '0;
            rename_arch_rs2 <= '0;
            rename_arch_rd <= '0;
        end else if (flush_pipeline) begin
            // On flush, invalidate all rename outputs
            rename_valid <= '0;
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
                    
                    // Save architectural registers
                    rename_arch_rs1[i] <= dec_rs1[i];
                    rename_arch_rs2[i] <= dec_rs2[i];
                    rename_arch_rd[i]  <= dec_rd[i];
                    
                    // Handle X0 special case (always physical register 0)
                    if (dec_rd[i] == 5'd0) begin
                        rename_prd[i] <= 6'd0;
                        rename_rd_valid[i] <= 1'b0;
                    end else if (dec_rd_valid[i] && alloc_valid[i]) begin
                        rename_prd[i] <= alloc_phys[i];
                        rename_rd_valid[i] <= 1'b1;
                    end else begin
                        rename_prd[i] <= 6'd0;
                        rename_rd_valid[i] <= 1'b0;
                    end
                    
                    // Map source registers to physical registers
                    if (dec_rs1_valid[i]) begin
                        rename_prs1[i] <= (dec_rs1[i] == 5'd0) ? 6'd0 : phys_rs1[i];
                    end else begin
                        rename_prs1[i] <= 6'd0;
                    end
                    
                    if (dec_rs2_valid[i]) begin
                        rename_prs2[i] <= (dec_rs2[i] == 5'd0) ? 6'd0 : phys_rs2[i];
                    end else begin
                        rename_prs2[i] <= 6'd0;
                    end
                end
            end
        end
    end
    
    // ============================================================
    //  Backpressure Logic
    // ============================================================
    logic can_allocate_all;
    always_comb begin
        can_allocate_all = 1'b1;
        for (int i = 0; i < FETCH_W; i++) begin
            if ( dec_rd_valid[i] && (dec_rd[i] != 5'd0)) begin
                if (!alloc_valid[i]) begin
                    can_allocate_all = 1'b0;
                end
            end
        end
        rename_ready = can_allocate_all && !flush_pipeline;
    end

endmodule
