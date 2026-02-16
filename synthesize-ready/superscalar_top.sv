`timescale 1ns/1ps
import core_pkg::*;

module ooo_core_top (
    input  logic clk,
    input  logic reset
);

    // ============================================================
    // Fetch ↔ Instruction ROM
    // ============================================================
    logic [31:0] imem_addr0, imem_addr1;
    logic imem_ren;
    logic [31:0] imem_rdata0, imem_rdata1;
    logic [1:0][31:0] imem_pc;
    logic imem_valid;
    
    logic [1:0] if_valid;
    logic [1:0][31:0] if_pc, if_instr;
    
    // ============================================================
    // Fetch ↔ Control
    // ============================================================
    logic fetch_en;
    logic fetch_stall;
    logic redirect_en;
    logic [31:0] redirect_pc;
    logic flush_pipeline;
    logic [31:0] flush_pc;
    
    // Branch predictor update
    logic bp_update_en;
    logic [31:0] bp_update_pc, bp_update_target;
    logic bp_update_taken, bp_update_is_branch, bp_update_is_call, bp_update_is_return;
    
    // ============================================================
    // Decode outputs
    // ============================================================
    logic [1:0] dec_valid;
    logic [1:0][5:0] dec_opcode;
    logic [1:0][4:0] dec_rs1, dec_rs2, dec_rd;
    logic [1:0][31:0] dec_imm, dec_pc;
    logic [1:0] dec_rs1_valid, dec_rs2_valid, dec_rd_valid;
    logic [1:0] dec_is_alu, dec_is_load, dec_is_store, dec_is_branch, dec_is_cas;
    logic [1:0][5:0] dec_alu_func;
    logic [1:0][4:0] dec_shamt;
    logic decode_ready;
    
    // ============================================================
    // Rename outputs
    // ============================================================
    logic [1:0] rename_valid;
    logic [1:0][5:0] rename_opcode, rename_prs1, rename_prs2, rename_prd, rename_alu_func;
    logic [1:0][31:0] rename_imm, rename_pc;
    logic [1:0] rename_rs1_valid, rename_rs2_valid, rename_rd_valid;
    logic [1:0] rename_is_alu, rename_is_load, rename_is_store, rename_is_branch, rename_is_cas;
    logic [1:0][4:0] rename_arch_rs1, rename_arch_rs2, rename_arch_rd;
    logic rename_ready;
    
    logic [1:0] commit_en;
    logic [1:0][4:0] commit_arch_rd;
    logic [1:0][5:0] commit_phys_rd;
    
    // ============================================================
    // Dispatch/Issue
    // ============================================================
    logic dispatch_stall;
    logic [5:0] prf_rtag0, prf_rtag1, prf_rtag2, prf_rtag3;
    logic [31:0] prf_rdata0, prf_rdata1, prf_rdata2, prf_rdata3;
    
    logic [1:0] rs_alloc_en;
    logic [1:0][5:0] rs_alloc_dst_tag, rs_alloc_src1_tag, rs_alloc_src2_tag, rs_alloc_rob_tag;
    logic [1:0][31:0] rs_alloc_src1_val, rs_alloc_src2_val;
    logic [1:0] rs_alloc_src1_ready, rs_alloc_src2_ready;
    logic [1:0][11:0] rs_alloc_op;
    logic rs_full;
    
    logic [1:0] rob_alloc_en;
    logic [1:0][4:0] rob_alloc_arch_rd;
    logic [1:0][5:0] rob_alloc_phys_rd;
    logic [1:0] rob_alloc_is_store, rob_alloc_is_load, rob_alloc_is_branch;
    logic [1:0][31:0] rob_alloc_pc;
    logic rob_alloc_ok;
    logic [1:0][3:0] rob_alloc_idx;
    
    logic lsu_alloc_en, lsu_is_load;
    logic [7:0] lsu_opcode;
    logic [31:0] lsu_base_addr, lsu_offset, lsu_store_data_val;
    logic [4:0] lsu_arch_rs1, lsu_arch_rs2, lsu_arch_rd;
    logic [5:0] lsu_phys_rd, lsu_rob_idx;
    logic lsu_store_data_ready;
    
    // ============================================================
    // Execution
    // ============================================================
    logic [1:0] issue_valid;
    logic [1:0][11:0] issue_op;
    logic [1:0][5:0] issue_dst_tag, issue_rob_tag;
    logic [1:0][31:0] issue_src1_val, issue_src2_val;
    
    // CDB
    logic [1:0] cdb_valid;
    logic [1:0][5:0] cdb_tag, cdb_rob_tag;
    logic [1:0][31:0] cdb_value;
    
    // ============================================================
    // ROB/Commit
    // ============================================================
    logic [1:0] rob_commit_valid, rob_commit_exception;
    logic [1:0][4:0] rob_commit_arch_rd;
    logic [1:0][5:0] rob_commit_phys_rd;
    logic [1:0][3:0] rob_commit_rob_idx;
    logic [1:0] rob_commit_is_store, rob_commit_is_load, rob_commit_is_branch;
    logic [1:0][31:0] rob_commit_pc;
    logic [1:0] rob_commit_branch_taken;
    logic [1:0][31:0] rob_commit_branch_target;
    logic [1:0] rob_commit_branch_is_call, rob_commit_branch_is_return;
    
    // ============================================================
    // Memory
    // ============================================================
    logic mem_req, mem_we, mem_ready, mem_error;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    
    // ============================================================
    // Physical Register File
    // ============================================================
    logic [1:0] prf_wen;
    logic [1:0][5:0] prf_wtag;
    logic [1:0][31:0] prf_wdata;
    
    logic [1:0][5:0] prf_commit_rtag;
    logic [1:0][31:0] prf_commit_rdata;
    
    // ============================================================
    // Free List
    // ============================================================
    logic [1:0] freelist_free_en;
    logic [1:0][5:0] freelist_free_phys;
    
    // ============================================================
    // ARF
    // ============================================================
    logic [1:0] arf_wen;
    logic [1:0][4:0] arf_waddr;
    logic [1:0][31:0] arf_wdata;
    
    // ============================================================
    // LSU
    // ============================================================
    logic lsu_cdb_valid, lsu_cdb_exception;
    logic [5:0] lsu_cdb_tag;
    logic [31:0] lsu_cdb_value;
    logic [1:0] lsu_commit_en, lsu_commit_is_store;
    logic [1:0][3:0] lsu_commit_rob_idx;
    
    // ============================================================
    // INSTRUCTION ROM with Demo Program
    // ============================================================
    inst_rom #(
        .ROM_SIZE(8192),
        .XLEN(32)
    ) imem (
        .clk(clk),
        .reset(reset),
        .imem_ren(imem_ren),
        .imem_addr0(imem_addr0),
        .imem_addr1(imem_addr1),
        .imem_valid(imem_valid),
        .imem_rdata0(imem_rdata0),
        .imem_rdata1(imem_rdata1),
        .imem_pc(imem_pc),
        .prog_en(1'b0),
        .prog_addr('0),
        .prog_data('0)
    );
    
    // Demo program (loaded at reset in inst_rom)
    // X1 = 10, X2 = 5, X3 = X1+X2, X4 = X1-X2, Store X3, Load back
    
    // ============================================================
    // FETCH
    // ============================================================
    fetch fetch_inst (
        .clk(clk),
        .reset(reset),
        .fetch_en(fetch_en),
        .stall(fetch_stall),
        .redirect_en(redirect_en),
        .redirect_pc(redirect_pc),
        .flush_pipeline(flush_pipeline),
        .flush_pc(flush_pc),
        .bp_update_en(bp_update_en),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_branch(bp_update_is_branch),
        .bp_update_is_call(bp_update_is_call),
        .bp_update_is_return(bp_update_is_return),
        .imem_rdata0(imem_rdata0),
        .imem_rdata1(imem_rdata1),
        .imem_pc(imem_pc),
        .imem_valid(imem_valid),
        .if_valid(if_valid),
        .if_pc(if_pc),
        .if_instr(if_instr),
        .imem_addr0(imem_addr0),
        .imem_addr1(imem_addr1),
        .imem_ren(imem_ren)
    );
    
    // ============================================================
    // DECODE
    // ============================================================
    decode decode_inst (
        .clk(clk),
        .reset(reset),
        .instr_valid(if_valid),
        .instr(if_instr),
        .pc(if_pc),
        .decode_ready(decode_ready),
        .flush_pipeline(flush_pipeline),
        .dec_valid(dec_valid),
        .dec_opcode(dec_opcode),
        .dec_rs1(dec_rs1),
        .dec_rs2(dec_rs2),
        .dec_rd(dec_rd),
        .dec_imm(dec_imm),
        .dec_pc(dec_pc),
        .dec_rs1_valid(dec_rs1_valid),
        .dec_rs2_valid(dec_rs2_valid),
        .dec_rd_valid(dec_rd_valid),
        .dec_is_alu(dec_is_alu),
        .dec_is_load(dec_is_load),
        .dec_is_store(dec_is_store),
        .dec_is_branch(dec_is_branch),
        .dec_is_cas(dec_is_cas),
        .dec_alu_func(dec_alu_func),
        .dec_shamt(dec_shamt)
    );
    
    // ============================================================
    // RENAME
    // ============================================================
    rename_stage rename_inst (
        .clk(clk),
        .reset(reset),
        .dec_valid(dec_valid),
        .dec_opcode(dec_opcode),
        .dec_rs1(dec_rs1),
        .dec_rs2(dec_rs2),
        .dec_rd(dec_rd),
        .dec_imm(dec_imm),
        .dec_pc(dec_pc),
        .dec_rs1_valid(dec_rs1_valid),
        .dec_rs2_valid(dec_rs2_valid),
        .dec_rd_valid(dec_rd_valid),
        .dec_is_alu(dec_is_alu),
        .dec_is_load(dec_is_load),
        .dec_is_store(dec_is_store),
        .dec_is_branch(dec_is_branch),
        .dec_is_cas(dec_is_cas),
        .dec_alu_func(dec_alu_func),
        .rename_ready(rename_ready),
        .rename_valid(rename_valid),
        .rename_opcode(rename_opcode),
        .rename_prs1(rename_prs1),
        .rename_prs2(rename_prs2),
        .rename_prd(rename_prd),
        .rename_imm(rename_imm),
        .rename_pc(rename_pc),
        .rename_rs1_valid(rename_rs1_valid),
        .rename_rs2_valid(rename_rs2_valid),
        .rename_rd_valid(rename_rd_valid),
        .rename_is_alu(rename_is_alu),
        .rename_is_load(rename_is_load),
        .rename_is_store(rename_is_store),
        .rename_is_branch(rename_is_branch),
        .rename_is_cas(rename_is_cas),
        .rename_alu_func(rename_alu_func),
        .rename_arch_rs1(rename_arch_rs1),
        .rename_arch_rs2(rename_arch_rs2),
        .rename_arch_rd(rename_arch_rd),
        .commit_en(commit_en),
        .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd),
        .flush_pipeline(flush_pipeline)
    );
    
    // Control logic
    assign fetch_en = 1'b1;
    //assign fetch_stall = dispatch_stall;
    assign fetch_stall = 1'b0;  // Force no stall for now
    assign decode_ready = 1'b1;
    
    // Stub connections (connect remaining modules similarly)
    assign redirect_en = 1'b0;
    assign redirect_pc = '0;
    
// ============================================================
    // DISPATCH
    // ============================================================
    dispatch dispatch_inst (
        .clk(clk),
        .reset(reset),
        .rename_valid(rename_valid),
        .rename_opcode(rename_opcode),
        .rename_prs1(rename_prs1),
        .rename_prs2(rename_prs2),
        .rename_prd(rename_prd),
        .rename_imm(rename_imm),
        .rename_pc(rename_pc),
        .rename_rs1_valid(rename_rs1_valid),
        .rename_rs2_valid(rename_rs2_valid),
        .rename_rd_valid(rename_rd_valid),
        .rename_is_alu(rename_is_alu),
        .rename_is_load(rename_is_load),
        .rename_is_store(rename_is_store),
        .rename_is_branch(rename_is_branch),
        .rename_is_cas(rename_is_cas),
        .rename_alu_func(rename_alu_func),
        .rename_arch_rs1(rename_arch_rs1),
        .rename_arch_rs2(rename_arch_rs2),
        .rename_arch_rd(rename_arch_rd),
        .flush_pipeline(flush_pipeline),
        .dispatch_stall(dispatch_stall),
        .prf_rtag0(prf_rtag0),
        .prf_rdata0(prf_rdata0),
        .prf_rtag1(prf_rtag1),
        .prf_rdata1(prf_rdata1),
        .prf_rtag2(prf_rtag2),
        .prf_rdata2(prf_rdata2),
        .prf_rtag3(prf_rtag3),
        .prf_rdata3(prf_rdata3),
        .rs_alloc_en(rs_alloc_en),
        .rs_alloc_dst_tag(rs_alloc_dst_tag),
        .rs_alloc_src1_tag(rs_alloc_src1_tag),
        .rs_alloc_src2_tag(rs_alloc_src2_tag),
        .rs_alloc_src1_val(rs_alloc_src1_val),
        .rs_alloc_src2_val(rs_alloc_src2_val),
        .rs_alloc_src1_ready(rs_alloc_src1_ready),
        .rs_alloc_src2_ready(rs_alloc_src2_ready),
        .rs_alloc_op(rs_alloc_op),
        .rs_alloc_rob_tag(rs_alloc_rob_tag),
        .rs_full(rs_full),
        .rob_alloc_en(rob_alloc_en),
        .rob_alloc_arch_rd(rob_alloc_arch_rd),
        .rob_alloc_phys_rd(rob_alloc_phys_rd),
        .rob_alloc_is_store(rob_alloc_is_store),
        .rob_alloc_is_load(rob_alloc_is_load),
        .rob_alloc_is_branch(rob_alloc_is_branch),
        .rob_alloc_pc(rob_alloc_pc),
        .rob_alloc_ok(rob_alloc_ok),
        .rob_alloc_idx(rob_alloc_idx),
        .lsu_alloc_en(lsu_alloc_en),
        .lsu_is_load(lsu_is_load),
        .lsu_opcode(lsu_opcode),
        .lsu_base_addr(lsu_base_addr),
        .lsu_offset(lsu_offset),
        .lsu_arch_rs1(lsu_arch_rs1),
        .lsu_arch_rs2(lsu_arch_rs2),
        .lsu_arch_rd(lsu_arch_rd),
        .lsu_phys_rd(lsu_phys_rd),
        .lsu_rob_idx(lsu_rob_idx),
        .lsu_store_data_val(lsu_store_data_val),
        .lsu_store_data_ready(lsu_store_data_ready),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_value(cdb_value)
    );
    
    // ============================================================
    // RESERVATION STATION
    // ============================================================
    reservation_station rs_inst (
        .clk(clk),
        .reset(reset),
        .flush_pipeline(flush_pipeline),
        .alloc_en(rs_alloc_en),
        .alloc_dst_tag(rs_alloc_dst_tag),
        .alloc_src1_tag(rs_alloc_src1_tag),
        .alloc_src2_tag(rs_alloc_src2_tag),
        .alloc_src1_val(rs_alloc_src1_val),
        .alloc_src2_val(rs_alloc_src2_val),
        .alloc_src1_ready(rs_alloc_src1_ready),
        .alloc_src2_ready(rs_alloc_src2_ready),
        .alloc_op(rs_alloc_op),
        .alloc_rob_tag(rs_alloc_rob_tag),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_value(cdb_value),
        .issue_valid(issue_valid),
        .issue_op(issue_op),
        .issue_dst_tag(issue_dst_tag),
        .issue_src1_val(issue_src1_val),
        .issue_src2_val(issue_src2_val),
        .issue_rob_tag(issue_rob_tag)
    );
    
    assign rs_full = 1'b0; // Simplified
    
    // ============================================================
    // EXECUTION UNITS (ALU0, ALU1 - simplified, no branch yet)
    // ============================================================
    logic alu0_result_valid, alu1_result_valid;
    logic [5:0] alu0_result_tag, alu1_result_tag;
    logic [31:0] alu0_result_value, alu1_result_value;
    logic [5:0] alu0_result_rob_tag, alu1_result_rob_tag;
    
    alu alu0_inst (
        .clk(clk),
        .reset(reset),
        .issue_valid(issue_valid[0]),
        .issue_op(issue_op[0]),
        .issue_dst_tag(issue_dst_tag[0]),
        .issue_src1_val(issue_src1_val[0][31:0]),
        .issue_src2_val(issue_src2_val[0][31:0]),
        .issue_rob_tag(issue_rob_tag[0]),
        .cdb_valid(1'b0),
        .cdb_tag('0),
        .cdb_value('0),
        .rf_rdata('0),
        .alu_result_valid(alu0_result_valid),
        .alu_result_tag(alu0_result_tag),
        .alu_result_value(alu0_result_value),
        .alu_result_rob_tag(alu0_result_rob_tag),
        .alu_bypass_valid(),
        .alu_bypass_tag(),
        .alu_bypass_value()
    );
    
    alu alu1_inst (
        .clk(clk),
        .reset(reset),
        .issue_valid(issue_valid[1]),
        .issue_op(issue_op[1]),
        .issue_dst_tag(issue_dst_tag[1]),
        .issue_src1_val(issue_src1_val[1][31:0]),
        .issue_src2_val(issue_src2_val[1][31:0]),
        .issue_rob_tag(issue_rob_tag[1]),
        .cdb_valid(1'b0),
        .cdb_tag('0),
        .cdb_value('0),
        .rf_rdata('0),
        .alu_result_valid(alu1_result_valid),
        .alu_result_tag(alu1_result_tag),
        .alu_result_value(alu1_result_value),
        .alu_result_rob_tag(alu1_result_rob_tag),
        .alu_bypass_valid(),
        .alu_bypass_tag(),
        .alu_bypass_value()
    );
    
    // ============================================================
    // CDB ARBITER
    // ============================================================
    cdb_arbiter cdb_arb_inst (
        .clk(clk),
        .reset(reset),
        .src0_valid(alu0_result_valid),
        .src0_tag(alu0_result_tag),
        .src0_value(alu0_result_value),
        .src0_rob_tag(alu0_result_rob_tag),
        .src1_valid(alu1_result_valid),
        .src1_tag(alu1_result_tag),
        .src1_value(alu1_result_value),
        .src1_rob_tag(alu1_result_rob_tag),
        .src2_valid(1'b0),
        .src2_tag('0),
        .src2_value('0),
        .src2_rob_tag('0),
        .src3_valid(lsu_cdb_valid),
        .src3_tag(lsu_cdb_tag),
        .src3_value(lsu_cdb_value),
        .src3_rob_tag('0),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_value(cdb_value),
        .cdb_rob_tag(cdb_rob_tag)
    );
    
    // ============================================================
    // ROB
    // ============================================================
    logic mark_ready_en;
    logic [3:0] mark_ready_idx;
    
    rob rob_inst (
        .clk(clk),
        .reset(reset),
        .alloc_en(rob_alloc_en),
        .alloc_arch_rd(rob_alloc_arch_rd),
        .alloc_phys_rd(rob_alloc_phys_rd),
        .alloc_is_store(rob_alloc_is_store),
        .alloc_is_load(rob_alloc_is_load),
        .alloc_is_branch(rob_alloc_is_branch),
        .alloc_pc(rob_alloc_pc),
        .alloc_ok(rob_alloc_ok),
        .alloc_idx(rob_alloc_idx),
        .mark_ready_en(mark_ready_en),
        .mark_ready_idx(mark_ready_idx),
        .mark_ready_val(1'b1),
        .mark_exception(1'b0),
        .branch_outcome_en(1'b0),
        .branch_outcome_idx('0),
        .branch_outcome_taken(1'b0),
        .branch_outcome_target('0),
        .branch_outcome_is_call(1'b0),
        .branch_outcome_is_return(1'b0),
        .commit_valid(rob_commit_valid),
        .commit_arch_rd(rob_commit_arch_rd),
        .commit_phys_rd(rob_commit_phys_rd),
        .commit_exception(rob_commit_exception),
        .commit_rob_idx(rob_commit_rob_idx),
        .commit_is_store(rob_commit_is_store),
        .commit_is_load(rob_commit_is_load),
        .commit_is_branch(rob_commit_is_branch),
        .commit_pc(rob_commit_pc),
        .commit_branch_taken(rob_commit_branch_taken),
        .commit_branch_target(rob_commit_branch_target),
        .commit_branch_is_call(rob_commit_branch_is_call),
        .commit_branch_is_return(rob_commit_branch_is_return),
        .rob_full(),
        .rob_almost_full(),
        .flush_en(1'b0),
        .flush_ptr('0)
    );
    
    // Mark ROB ready from CDB
    assign mark_ready_en = cdb_valid[0] | cdb_valid[1];
    assign mark_ready_idx = cdb_valid[0] ? cdb_rob_tag[0][3:0] : cdb_rob_tag[1][3:0];
    
    // ============================================================
    // COMMIT STAGE
    // ============================================================
    commit_stage commit_inst (
        .clk(clk),
        .reset(reset),
        .rob_commit_valid(rob_commit_valid),
        .rob_commit_arch_rd(rob_commit_arch_rd),
        .rob_commit_phys_rd(rob_commit_phys_rd),
        .rob_commit_exception(rob_commit_exception),
        .rob_commit_is_store(rob_commit_is_store),
        .rob_commit_is_load(rob_commit_is_load),
        .rob_commit_is_branch(rob_commit_is_branch),
        .rob_commit_pc(rob_commit_pc),
        .rob_commit_rob_idx(rob_commit_rob_idx),
        .rob_commit_branch_taken(rob_commit_branch_taken),
        .rob_commit_branch_target(rob_commit_branch_target),
        .rob_commit_branch_is_call(rob_commit_branch_is_call),
        .rob_commit_branch_is_return(rob_commit_branch_is_return),
        .arf_wen(arf_wen),
        .arf_waddr(arf_waddr),
        .arf_wdata(arf_wdata),
        .prf_commit_rtag(prf_commit_rtag),
        .prf_commit_rdata(prf_commit_rdata),
        .freelist_free_en(freelist_free_en),
        .freelist_free_phys(freelist_free_phys),
        .rename_commit_en(commit_en),
        .rename_commit_arch_rd(commit_arch_rd),
        .rename_commit_phys_rd(commit_phys_rd),
        .exception_valid(),
        .exception_cause(),
        .exception_pc(),
        .exception_tval(),
        .flush_pipeline(flush_pipeline),
        .flush_pc(flush_pc),
        .lsu_commit_en(lsu_commit_en),
        .lsu_commit_is_store(lsu_commit_is_store),
        .lsu_commit_rob_idx(lsu_commit_rob_idx),
        .bp_update_en(bp_update_en),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_branch(bp_update_is_branch),
        .bp_update_is_call(bp_update_is_call),
        .bp_update_is_return(bp_update_is_return),
        .perf_insns_committed(),
        .perf_cycles(),
        .perf_exceptions()
    );
    
    // ============================================================
    // PHYSICAL REGISTER FILE
    // ============================================================
    assign prf_wen = cdb_valid;
    assign prf_wtag = cdb_tag;
    assign prf_wdata = cdb_value;
    
    regfile_synth prf_inst (
        .clk(clk),
        .reset(reset),
        .wen0(prf_wen[0]),
        .wtag0(prf_wtag[0]),
        .wdata0(prf_wdata[0]),
        .wen1(prf_wen[1]),
        .wtag1(prf_wtag[1]),
        .wdata1(prf_wdata[1]),
        .rtag0(prf_rtag0),
        .rdata0(prf_rdata0),
        .rtag1(prf_rtag1),
        .rdata1(prf_rdata1),
        .rtag2(prf_rtag2),
        .rdata2(prf_rdata2),
        .rtag3(prf_rtag3),
        .rdata3(prf_rdata3)
    );
    
    // Commit reads from PRF
    regfile_synth prf_commit_read (
        .clk(clk),
        .reset(reset),
        .wen0(1'b0),
        .wtag0('0),
        .wdata0('0),
        .wen1(1'b0),
        .wtag1('0),
        .wdata1('0),
        .rtag0(prf_commit_rtag[0]),
        .rdata0(prf_commit_rdata[0]),
        .rtag1(prf_commit_rtag[1]),
        .rdata1(prf_commit_rdata[1]),
        .rtag2('0),
        .rdata2(),
        .rtag3('0),
        .rdata3()
    );
    
    // ============================================================
    // ARF
    // ============================================================
    arch_regfile arf_inst (
        .clk(clk),
        .reset(reset),
        .wen(arf_wen),
        .waddr(arf_waddr),
        .wdata(arf_wdata),
        .raddr0('0),
        .rdata0(),
        .raddr1('0),
        .rdata1()
    );
    
    // ============================================================
    // LSU
    // ============================================================
    lsu lsu_inst (
        .clk(clk),
        .reset(reset),
        .flush_pipeline(flush_pipeline),
        .alloc_en(lsu_alloc_en),
        .is_load(lsu_is_load),
        .opcode(lsu_opcode),
        .base_addr(lsu_base_addr),
        .offset(lsu_offset),
        .arch_rs1(lsu_arch_rs1),
        .arch_rs2(lsu_arch_rs2),
        .arch_rd(lsu_arch_rd),
        .phys_rd(lsu_phys_rd),
        .rob_idx(lsu_rob_idx),
        .store_data_val(lsu_store_data_val),
        .store_data_ready(lsu_store_data_ready),
        .cdb_valid(lsu_cdb_valid),
        .cdb_tag(lsu_cdb_tag),
        .cdb_value(lsu_cdb_value),
        .cdb_exception(lsu_cdb_exception),
        .commit_en(lsu_commit_en),
        .commit_is_store(lsu_commit_is_store),
        .commit_rob_idx(lsu_commit_rob_idx),
        .lsu_exception(),
        .lsu_exception_cause(),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .mem_error(mem_error)
    );
    
    // ============================================================
    // DATA SCRATCHPAD
    // ============================================================
    data_scratchpad dmem (
        .clk(clk),
        .reset(reset),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_size(2'b10),
        .mem_atomic(1'b0),
        .mem_cmp_val('0),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .mem_error(mem_error)
    );

endmodule
