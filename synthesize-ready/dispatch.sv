`timescale 1ns/1ps
import core_pkg::*;

module dispatch #(
    parameter int FETCH_W = core_pkg::FETCH_WIDTH,
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS,
    parameter int ROB_ENTRIES = 32
)(
    input  logic                    clk,
    input  logic                    reset,
    
    // From Rename Stage
    input  logic [FETCH_W-1:0]      rename_valid,
    input  logic [FETCH_W-1:0][5:0] rename_opcode,
    input  logic [FETCH_W-1:0][5:0] rename_prs1,
    input  logic [FETCH_W-1:0][5:0] rename_prs2,
    input  logic [FETCH_W-1:0][5:0] rename_prd,
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
    input  logic [FETCH_W-1:0][4:0] rename_arch_rs1,
    input  logic [FETCH_W-1:0][4:0] rename_arch_rs2,
    input  logic [FETCH_W-1:0][4:0] rename_arch_rd,
    
    input  logic                    flush_pipeline,
    output logic                    dispatch_stall,
    
    // To Physical Register File (combinational)
    output logic [PHYS_W-1:0]       prf_rtag0,
    output logic [PHYS_W-1:0]       prf_rtag1,
    output logic [PHYS_W-1:0]       prf_rtag2,
    output logic [PHYS_W-1:0]       prf_rtag3,
    input  logic [XLEN-1:0]         prf_rdata0,
    input  logic [XLEN-1:0]         prf_rdata1,
    input  logic [XLEN-1:0]         prf_rdata2,
    input  logic [XLEN-1:0]         prf_rdata3,
    
    // To Reservation Station (REGISTERED)
    output logic [FETCH_W-1:0]      rs_alloc_en,
    output logic [FETCH_W-1:0][PHYS_W-1:0] rs_alloc_dst_tag,
    output logic [FETCH_W-1:0][PHYS_W-1:0] rs_alloc_src1_tag,
    output logic [FETCH_W-1:0][PHYS_W-1:0] rs_alloc_src2_tag,
    output logic [FETCH_W-1:0][31:0] rs_alloc_src1_val,
    output logic [FETCH_W-1:0][31:0] rs_alloc_src2_val,
    output logic [FETCH_W-1:0]      rs_alloc_src1_ready,
    output logic [FETCH_W-1:0]      rs_alloc_src2_ready,
    output logic [FETCH_W-1:0][11:0] rs_alloc_op,
    output logic [1:0][31:0]        rs_alloc_pc,
    output logic [1:0][31:0]        rs_alloc_imm,
    output logic [FETCH_W-1:0][5:0] rs_alloc_rob_tag,
    input  logic                    rs_full,
    
    // To ROB (REGISTERED)
    output logic [FETCH_W-1:0]      rob_alloc_en,
    output logic [FETCH_W-1:0][4:0] rob_alloc_arch_rd,
    output logic [FETCH_W-1:0][PHYS_W-1:0] rob_alloc_phys_rd,
    output logic [FETCH_W-1:0]      rob_alloc_is_store,
    output logic [FETCH_W-1:0]      rob_alloc_is_load,
    output logic [FETCH_W-1:0]      rob_alloc_is_branch,
    output logic [FETCH_W-1:0][31:0] rob_alloc_pc,
    input  logic                    rob_alloc_ok,
    input  logic [FETCH_W-1:0][$clog2(ROB_ENTRIES)-1:0] rob_alloc_idx,
    
    // To LSU (REGISTERED)
    output logic                    lsu_alloc_en,
    output logic                    lsu_is_load,
    output logic [7:0]              lsu_opcode,
    output logic [XLEN-1:0]         lsu_offset,
    output logic [4:0]              lsu_arch_rs1,
    output logic [4:0]              lsu_arch_rs2,
    output logic [4:0]              lsu_arch_rd,
    output logic [PHYS_W-1:0]       lsu_phys_rd,
    output logic [5:0]              lsu_rob_idx,
    output logic [5:0]              lsu_base_tag,
    output logic                    lsu_base_ready,
    output logic [31:0]             lsu_base_value,
    output logic [5:0]              lsu_store_data_tag,
    output logic                    lsu_store_data_ready,
    output logic [31:0]             lsu_store_data_value,
    output logic [0:0]              lsu_lane_index,
    
    // From CDB
    input  logic [1:0]              cdb_valid,
    input  logic [1:0][PHYS_W-1:0]  cdb_tag,
    input  logic [1:0][XLEN-1:0]    cdb_value
);

    // Scoreboard
    logic [core_pkg::PREGS-1:0] preg_ready;
    
    // LSU cache
    logic [5:0]      cached_base_tag;
    logic [31:0]     cached_base_value;
    logic            cached_base_ready;
    logic            cached_valid;
    
    // Combinational signals
    logic [FETCH_W-1:0] src1_ready, src2_ready;
    logic [FETCH_W-1:0][31:0] src1_value, src2_value;
    logic [FETCH_W-1:0] alloc_en_comb;
    logic memory_op_stall;
    
    // ============================================================
    // PRF Read Ports (combinational)
    // ============================================================
    always_comb begin
        prf_rtag0 = rename_valid[0] ? rename_prs1[0] : '0;
        prf_rtag1 = rename_valid[0] ? rename_prs2[0] : '0;
        prf_rtag2 = rename_valid[1] ? rename_prs1[1] : '0;
        prf_rtag3 = rename_valid[1] ? rename_prs2[1] : '0;
    end
    
    // ============================================================
    // Scoreboard (registered)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            preg_ready <= '1;
        end else begin
            // Mark busy for instructions being dispatched this cycle
            for (int i = 0; i < FETCH_W; i++) begin
                if (rob_alloc_en[i] && rename_rd_valid[i]) begin
                    preg_ready[rename_prd[i]] <= 1'b0;
                end
            end
            // Mark ready on CDB
            for (int j = 0; j < 2; j++) begin
                if (cdb_valid[j]) begin
                    preg_ready[cdb_tag[j]] <= 1'b1;
                end
            end
        end
    end
    
    // ============================================================
    // Operand Readiness (combinational)
    // ============================================================
    always_comb begin
        for (int i = 0; i < FETCH_W; i++) begin
            // Source 1
            if (!rename_rs1_valid[i] || rename_prs1[i] == 6'd0) begin
                src1_ready[i] = 1'b1;
                src1_value[i] = '0;
            end else begin
                src1_ready[i] = preg_ready[rename_prs1[i]];
                // Same-cycle forwarding
                for (int j = 0; j < i; j++) begin
                    if (rename_valid[j] && rename_rd_valid[j] && 
                        rename_prs1[i] == rename_prd[j]) begin
                        src1_ready[i] = 1'b0;
                    end
                end
                src1_value[i] = (i == 0) ? prf_rdata0 : prf_rdata2;
                // CDB bypass
                for (int j = 0; j < 2; j++) begin
                    if (cdb_valid[j] && cdb_tag[j] == rename_prs1[i]) begin
                        src1_ready[i] = 1'b1;
                        src1_value[i] = cdb_value[j];
                    end
                end
            end
            
            // Source 2
            if (!rename_rs2_valid[i]) begin
                src2_ready[i] = 1'b1;
                src2_value[i] = rename_imm[i];
            end else if (rename_prs2[i] == 6'd0) begin
                src2_ready[i] = 1'b1;
                src2_value[i] = '0;
            end else begin
                src2_ready[i] = preg_ready[rename_prs2[i]];
                for (int j = 0; j < i; j++) begin
                    if (rename_valid[j] && rename_rd_valid[j] && 
                        rename_prs2[i] == rename_prd[j]) begin
                        src2_ready[i] = 1'b0;
                    end
                end
                src2_value[i] = (i == 0) ? prf_rdata1 : prf_rdata3;
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
    // LSU Cache
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_pipeline) begin
            cached_valid <= 1'b0;
            cached_base_tag <= '0;
            cached_base_value <= '0;
            cached_base_ready <= 1'b0;
        end else if (lsu_alloc_en) begin
            cached_valid <= 1'b1;
            cached_base_tag <= lsu_base_tag;
            cached_base_value <= lsu_base_value;
            cached_base_ready <= lsu_base_ready;
        end
    end
    
    // ============================================================
    // Combinational alloc_en for stall logic
    // ============================================================
    always_comb begin
        alloc_en_comb = '0;
        for (int i = 0; i < FETCH_W; i++) begin
            if (rename_valid[i] && !rs_full && !flush_pipeline) begin
                alloc_en_comb[i] = 1'b1;
            end
        end
    end
    
    // ============================================================
    // Stall Logic
    // ============================================================
    always_comb begin
        automatic int mem_op_count = 0;
        for (int i = 0; i < FETCH_W; i++) begin
            if (rename_valid[i] && (rename_is_load[i] || rename_is_store[i] || rename_is_cas[i])) begin
                mem_op_count++;
            end
        end
        memory_op_stall = (mem_op_count > 1);
        dispatch_stall = rs_full || !rob_alloc_ok || flush_pipeline || memory_op_stall;
    end
    
    // ============================================================
    // REGISTERED OUTPUTS
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset || flush_pipeline) begin
            // RS
            rs_alloc_en <= '0;
            rs_alloc_dst_tag <= '0;
            rs_alloc_src1_tag <= '0;
            rs_alloc_src2_tag <= '0;
            rs_alloc_src1_val <= '0;
            rs_alloc_src2_val <= '0;
            rs_alloc_src1_ready <= '0;
            rs_alloc_src2_ready <= '0;
            rs_alloc_op <= '0;
            rs_alloc_pc <= '0;
            rs_alloc_imm <= '0;
            rs_alloc_rob_tag <= '0;
            
            // ROB
            rob_alloc_en <= '0;
            rob_alloc_arch_rd <= '0;
            rob_alloc_phys_rd <= '0;
            rob_alloc_is_store <= '0;
            rob_alloc_is_load <= '0;
            rob_alloc_is_branch <= '0;
            rob_alloc_pc <= '0;
            
            // LSU
            lsu_alloc_en <= 1'b0;
            lsu_lane_index <= 1'b0;
            lsu_is_load <= 1'b0;
            lsu_opcode <= '0;
            lsu_base_tag <= '0;
            lsu_base_ready <= 1'b0;
            lsu_base_value <= '0;
            lsu_offset <= '0;
            lsu_store_data_tag <= '0;
            lsu_store_data_ready <= 1'b0;
            lsu_store_data_value <= '0;
            lsu_arch_rs1 <= '0;
            lsu_arch_rs2 <= '0;
            lsu_arch_rd <= '0;
            lsu_phys_rd <= '0;
            lsu_rob_idx <= '0;
            
        end else if (!dispatch_stall) begin
            // ====================================================
            // RS Allocation
            // ====================================================
            for (int i = 0; i < FETCH_W; i++) begin
                if (rename_valid[i] && (rename_is_alu[i] || rename_is_branch[i])) begin
                    rs_alloc_en[i] <= 1'b1;
                    rs_alloc_dst_tag[i] <= rename_prd[i];
                    rs_alloc_src1_tag[i] <= rename_prs1[i];
                    rs_alloc_src2_tag[i] <= rename_prs2[i];
                    rs_alloc_src1_val[i] <= src1_value[i];
                    rs_alloc_src2_val[i] <= src2_value[i];
                    rs_alloc_src1_ready[i] <= src1_ready[i];
                    rs_alloc_src2_ready[i] <= src2_ready[i];
                    rs_alloc_op[i] <= {rename_opcode[i], rename_alu_func[i]};
                    rs_alloc_pc[i] <= rename_pc[i];
                    rs_alloc_imm[i] <= rename_imm[i];
                    rs_alloc_rob_tag[i] <= rob_alloc_idx[i];
                end else begin
                    rs_alloc_en[i] <= 1'b0;
                end
            end
            
            // ====================================================
            // ROB Allocation
            // ====================================================
            for (int i = 0; i < FETCH_W; i++) begin
                rob_alloc_arch_rd[i] <= rename_arch_rd[i];
                rob_alloc_phys_rd[i] <= rename_prd[i];
                rob_alloc_pc[i] <= rename_pc[i];
                
                if (rename_valid[i]) begin
                    rob_alloc_en[i] <= 1'b1;
                    rob_alloc_is_store[i] <= rename_is_store[i];
                    rob_alloc_is_load[i] <= rename_is_load[i];
                    rob_alloc_is_branch[i] <= rename_is_branch[i];
                end else begin
                    rob_alloc_en[i] <= 1'b0;
                    rob_alloc_is_store[i] <= 1'b0;
                    rob_alloc_is_load[i] <= 1'b0;
                    rob_alloc_is_branch[i] <= 1'b0;
                end
            end
            
            // ====================================================
            // LSU Allocation (only one per cycle)
            // ====================================================
            lsu_alloc_en <= 1'b0;
            for (int i = 0; i < FETCH_W; i++) begin
                if (rename_valid[i] && (rename_is_load[i] || rename_is_store[i])) begin
                    lsu_alloc_en <= 1'b1;
                    lsu_lane_index <= i[0];
                    lsu_is_load <= rename_is_load[i];
                    lsu_opcode <= {rename_opcode[i], 2'b00};
                    lsu_base_tag <= rename_prs1[i];
                    lsu_offset <= rename_imm[i];
                    lsu_store_data_value <= src2_value[i];
                    lsu_store_data_tag <= rename_prs2[i];
                    lsu_store_data_ready <= src2_ready[i];
                    lsu_arch_rs1 <= rename_arch_rs1[i];
                    lsu_arch_rs2 <= rename_arch_rs2[i];
                    lsu_arch_rd <= rename_arch_rd[i];
                    lsu_phys_rd <= rename_prd[i];
                    lsu_rob_idx <= rob_alloc_idx[i];
                    
                    if (cached_valid && rename_prs1[i] == cached_base_tag && cached_base_ready) begin
                        lsu_base_value <= cached_base_value;
                        lsu_base_ready <= cached_base_ready;
                    end else begin
                        lsu_base_value <= src1_value[i];
                        lsu_base_ready <= src1_ready[i];
                    end
                    break;
                end
            end
        end
    end

endmodule
