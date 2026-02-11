`timescale 1ns/1ps
import core_pkg::*;

module dispatch #(
    parameter int FETCH_W = core_pkg::FETCH_WIDTH,
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS,
    parameter int RS_ENTRIES = 16,
    parameter int ROB_ENTRIES = core_pkg::ROB_ENTRIES
)(
    input  logic                    clk,
    input  logic                    reset,
    
    // ============================================================
    // From Rename Stage
    // ============================================================
    input  logic [FETCH_W-1:0]      rename_valid,
    input  logic [FETCH_W-1:0][5:0] rename_opcode,
    input  logic [FETCH_W-1:0][5:0] rename_prs1,      // Physical source 1
    input  logic [FETCH_W-1:0][5:0] rename_prs2,      // Physical source 2
    input  logic [FETCH_W-1:0][5:0] rename_prd,       // Physical destination
    input  logic [FETCH_W-1:0][31:0] rename_imm,
    input  logic [FETCH_W-1:0][31:0] rename_pc,
    input  logic [FETCH_W-1:0]      rename_rs1_valid,
    input  logic [FETCH_W-1:0]      rename_rs2_valid,
    input  logic [FETCH_W-1:0]      rename_rd_valid,
    input  logic [FETCH_W-1:0]      rename_is_alu,
    input  logic [FETCH_W-1:0]      rename_is_load,
    input  logic [FETCH_W-1:0]      rename_is_store,
    input  logic [FETCH_W-1:0]      rename_is_branch,
    input  logic [FETCH_W-1:0]      rename_is_cas,
    input  logic [FETCH_W-1:0][5:0] rename_alu_func,
    input  logic [FETCH_W-1:0][4:0]              rename_arch_rs1,
    input  logic [FETCH_W-1:0][4:0]              rename_arch_rs2,
    input  logic [FETCH_W-1:0][4:0]              rename_arch_rd,
    
    // NEW: Flush signal
    input  logic                    flush_pipeline,
    
    output logic                    dispatch_stall,   // Backpressure to rename
    
    // ============================================================
    // To Physical Register File (PRF) - Read Ports
    // ============================================================
    output logic [PHYS_W-1:0]       prf_rtag0,
    input  logic [XLEN-1:0]         prf_rdata0,
    output logic [PHYS_W-1:0]       prf_rtag1,
    input  logic [XLEN-1:0]         prf_rdata1,
    output logic [PHYS_W-1:0]       prf_rtag2,
    input  logic [XLEN-1:0]         prf_rdata2,
    output logic [PHYS_W-1:0]       prf_rtag3,
    input  logic [XLEN-1:0]         prf_rdata3,
    
    // ============================================================
    // To Reservation Station (RS)
    // ============================================================
    output logic [FETCH_W-1:0]      rs_alloc_en,
    output logic [FETCH_W-1:0][PHYS_W-1:0] rs_alloc_dst_tag,
    output logic [FETCH_W-1:0][PHYS_W-1:0] rs_alloc_src1_tag,
    output logic [FETCH_W-1:0][PHYS_W-1:0] rs_alloc_src2_tag,
    output logic [FETCH_W-1:0][63:0] rs_alloc_src1_val,
    output logic [FETCH_W-1:0][63:0] rs_alloc_src2_val,
    output logic [FETCH_W-1:0]      rs_alloc_src1_ready,
    output logic [FETCH_W-1:0]      rs_alloc_src2_ready,
    output logic [FETCH_W-1:0][7:0] rs_alloc_op,
    output logic [FETCH_W-1:0][5:0] rs_alloc_rob_tag,
    input  logic                    rs_full,          // From RS
    
    // ============================================================
    // To/From ROB
    // ============================================================
    output logic [FETCH_W-1:0]      rob_alloc_en,
    output logic [FETCH_W-1:0][4:0]              rob_alloc_arch_rd,
    output logic [FETCH_W-1:0][PHYS_W-1:0]       rob_alloc_phys_rd,
    // ADDED: ROB metadata outputs
    output logic [FETCH_W-1:0]      rob_alloc_is_store,
    output logic [FETCH_W-1:0]      rob_alloc_is_load,
    output logic [FETCH_W-1:0]      rob_alloc_is_branch,
    output logic [FETCH_W-1:0][31:0]             rob_alloc_pc,
    
    input  logic                    rob_alloc_ok,
    input  logic [FETCH_W-1:0][$clog2(ROB_ENTRIES)-1:0] rob_alloc_idx,
    
    // ============================================================
    // To LSU (for loads/stores)
    // ============================================================
    output logic                    lsu_alloc_en,
    output logic                    lsu_is_load,
    output logic [7:0]              lsu_opcode,
    output logic [XLEN-1:0]         lsu_base_addr,
    output logic [XLEN-1:0]         lsu_offset,
    output logic [4:0]              lsu_arch_rs1,
    output logic [4:0]              lsu_arch_rs2,
    output logic [4:0]              lsu_arch_rd,
    output logic [PHYS_W-1:0]       lsu_phys_rd,
    output logic [5:0]              lsu_rob_idx,
    output logic [XLEN-1:0]         lsu_store_data_val,
    output logic                    lsu_store_data_ready,
    
    // ============================================================
    // From CDB (for operand readiness check)
    // ============================================================
    input  logic [1:0]              cdb_valid,
    input  logic [1:0][PHYS_W-1:0]  cdb_tag,
    input  logic [1:0][XLEN-1:0]    cdb_value
);

    // ============================================================
    // Scoreboard for tracking physical register readiness
    // ============================================================
    logic [core_pkg::PREGS-1:0] preg_ready;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // All physical registers start as ready
            preg_ready <= '1;
        end else begin
            // Mark allocated destination registers as NOT ready
            for (int i = 0; i < FETCH_W; i++) begin
                if (rob_alloc_en[i] && rob_alloc_ok && rename_rd_valid[i]) begin
                    preg_ready[rename_prd[i]] <= 1'b0;
                end
            end
            
            // Mark registers as ready when they complete on CDB
            for (int j = 0; j < 2; j++) begin
                if (cdb_valid[j]) begin
                    preg_ready[cdb_tag[j]] <= 1'b1;
                end
            end
        end
    end
    
    // ============================================================
    // PRF Read Port Arbitration (for 2-wide dispatch, 4 read ports)
    // ============================================================
    // Instruction 0: uses ports 0 and 1
    // Instruction 1: uses ports 2 and 3
    always_comb begin
        // Default assignments
        prf_rtag0 = '0;
        prf_rtag1 = '0;
        prf_rtag2 = '0;
        prf_rtag3 = '0;
        
        // Instruction 0 reads
        if (rename_valid[0]) begin
            prf_rtag0 = rename_prs1[0];
            prf_rtag1 = rename_prs2[0];
        end
        
        // Instruction 1 reads
        if (rename_valid[1]) begin
            prf_rtag2 = rename_prs1[1];
            prf_rtag3 = rename_prs2[1];
        end
    end
    
    // ============================================================
    // Operand Readiness Check
    // ============================================================
    logic [FETCH_W-1:0] src1_ready, src2_ready;
    logic [FETCH_W-1:0][XLEN-1:0] src1_value, src2_value;
    
    always_comb begin
        for (int i = 0; i < FETCH_W; i++) begin
            // Source 1 readiness
            if (!rename_rs1_valid[i]) begin
                // No source operand needed
                src1_ready[i] = 1'b1;
                src1_value[i] = '0;
            end else if (rename_prs1[i] == 6'd0) begin
                // Physical register 0 (maps to x0) - always zero
                src1_ready[i] = 1'b1;
                src1_value[i] = '0;
            end else begin
                // Check scoreboard
                src1_ready[i] = preg_ready[rename_prs1[i]];
                // Read value from PRF if ready
                if (i == 0)
                    src1_value[i] = prf_rdata0;
                else
                    src1_value[i] = prf_rdata2;
                    
                // Check CDB bypass (same-cycle forwarding)
                for (int j = 0; j < 2; j++) begin
                    if (cdb_valid[j] && cdb_tag[j] == rename_prs1[i]) begin
                        src1_ready[i] = 1'b1;
                        src1_value[i] = cdb_value[j];
                    end
                end
            end
            
            // Source 2 readiness (similar logic)
            if (!rename_rs2_valid[i]) begin
                src2_ready[i] = 1'b1;
                src2_value[i] = rename_imm[i];  // For I-type instructions
            end else if (rename_prs2[i] == 6'd0) begin
                src2_ready[i] = 1'b1;
                src2_value[i] = '0;
            end else begin
                src2_ready[i] = preg_ready[rename_prs2[i]];
                if (i == 0)
                    src2_value[i] = prf_rdata1;
                else
                    src2_value[i] = prf_rdata3;
                    
                // CDB bypass for src2
                for (int j = 0; j < 2; j++) begin
                    if (cdb_valid[j] && cdb_tag[j] == rename_prs2[i]) begin
                        src2_ready[i] = 1'b1;
                        src2_value[i] = cdb_value[j];
                    end
                end
            end
        end
    end
    
    // ============================================================
    // Dispatch to Reservation Station
    // ============================================================
    always_comb begin
        // Default: no allocation
        rs_alloc_en = '0;
        rs_alloc_dst_tag = '0;
        rs_alloc_src1_tag = '0;
        rs_alloc_src2_tag = '0;
        rs_alloc_src1_val = '0;
        rs_alloc_src2_val = '0;
        rs_alloc_src1_ready = '0;
        rs_alloc_src2_ready = '0;
        rs_alloc_op = '0;
        rs_alloc_rob_tag = '0;
        
        for (int i = 0; i < FETCH_W; i++) begin
            // Only dispatch ALU and branch instructions to RS
            if (rename_valid[i] && (rename_is_alu[i] || rename_is_branch[i]) && !rs_full && rob_alloc_ok) begin
                rs_alloc_en[i] = 1'b1;
                rs_alloc_dst_tag[i] = rename_prd[i];
                rs_alloc_src1_tag[i] = rename_prs1[i];
                rs_alloc_src2_tag[i] = rename_prs2[i];
                rs_alloc_src1_val[i] = {{32{1'b0}}, src1_value[i]};  // Zero-extend to 64-bit
                rs_alloc_src2_val[i] = {{32{1'b0}}, src2_value[i]};
                rs_alloc_src1_ready[i] = src1_ready[i];
                rs_alloc_src2_ready[i] = src2_ready[i];
                rs_alloc_op[i] = {rename_opcode[i], 2'b00};  // Combine opcode
                rs_alloc_rob_tag[i] = rob_alloc_idx[i];
            end
        end
    end
    
    // ============================================================
    // Dispatch to ROB - UPDATED with metadata
    // ============================================================
    always_comb begin
        rob_alloc_en = '0;
        rob_alloc_is_store = '0;
        rob_alloc_is_load = '0;
        rob_alloc_is_branch = '0;
        
        for (int i = 0; i < FETCH_W; i++) begin
            rob_alloc_arch_rd[i] = rename_arch_rd[i];
            rob_alloc_phys_rd[i] = rename_prd[i];
            rob_alloc_pc[i] = rename_pc[i];
            
            if (rename_valid[i] && !rs_full && !flush_pipeline) begin
                rob_alloc_en[i] = 1'b1;
                rob_alloc_is_store[i] = rename_is_store[i];
                rob_alloc_is_load[i] = rename_is_load[i];
                rob_alloc_is_branch[i] = rename_is_branch[i];
            end
        end
    end
    
    // ============================================================
    // Dispatch to LSU (Load/Store Queue)
    // ============================================================
    always_comb begin
        lsu_alloc_en = 1'b0;
        lsu_is_load = 1'b0;
        lsu_opcode = '0;
        lsu_base_addr = '0;
        lsu_offset = '0;
        lsu_arch_rs1 = '0;
        lsu_arch_rs2 = '0;
        lsu_arch_rd = '0;
        lsu_phys_rd = '0;
        lsu_rob_idx = '0;
        lsu_store_data_val = '0;
        lsu_store_data_ready = 1'b0;
        
        // POLICY: Dispatch first valid load/store instruction only
        // If both lanes have memory ops, lane 0 has priority
        // Lane 1's memory op will stall until next cycle
        for (int i = 0; i < FETCH_W; i++) begin
            if (rename_valid[i] && 
                (rename_is_load[i] || rename_is_store[i] || rename_is_cas[i]) && 
                rob_alloc_ok && !flush_pipeline) begin
                
                lsu_alloc_en = 1'b1;
                lsu_is_load = rename_is_load[i] || rename_is_cas[i];
                lsu_opcode = {rename_opcode[i], 2'b00};
                lsu_base_addr = src1_value[i];
                lsu_offset = rename_imm[i];
                lsu_arch_rs1 = rename_arch_rs1[i];
                lsu_arch_rs2 = rename_arch_rs2[i];
                lsu_arch_rd = rename_arch_rd[i];
                lsu_phys_rd = rename_prd[i];
                lsu_rob_idx = rob_alloc_idx[i];
                lsu_store_data_val = src2_value[i];
                lsu_store_data_ready = src2_ready[i];
                break;  // Only dispatch ONE memory op per cycle
            end
        end
    end
    
    // ============================================================
    // Backpressure/Stall Logic - UPDATED
    // ============================================================
    logic memory_op_stall;
    
    always_comb begin
        // Check if we have multiple memory ops competing
        automatic int mem_op_count = 0;
        for (int i = 0; i < FETCH_W; i++) begin
            if (rename_valid[i] && (rename_is_load[i] || rename_is_store[i] || rename_is_cas[i])) begin
                mem_op_count++;
            end
        end
        
        // Stall if we have >1 memory op (can't dispatch both)
        // This will cause rename to hold the second memory op until next cycle
        memory_op_stall = (mem_op_count > 1);
        
        // Combine all stall conditions
        dispatch_stall = rs_full || !rob_alloc_ok || flush_pipeline || memory_op_stall;
    end

endmodule
