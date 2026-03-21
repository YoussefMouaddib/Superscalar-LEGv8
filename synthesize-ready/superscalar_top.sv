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
    
    logic [4:0] flush_rob_idx;
    
    // ============================================================
    // Fetch ↔ Control + Branch *
    // ============================================================
    logic fetch_en;
    logic fetch_stall;
    logic redirect_en;
    logic [31:0] redirect_pc;
    logic flush_pipeline;
    logic flush_exception;
    logic [31:0] flush_pc;
    
    // Branch predictor update
    logic bp_update_en, branch_is_call, branch_is_return;
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
    logic [1:0][31:0] rs_alloc_src1_val, rs_alloc_src2_val, rs_alloc_pc, rs_alloc_imm;
    logic [1:0] rs_alloc_src1_ready, rs_alloc_src2_ready;
    logic [1:0][11:0] rs_alloc_op;
    logic rs_full;
    
    logic [1:0] rob_alloc_en;
    logic [1:0][4:0] rob_alloc_arch_rd;
    logic [1:0][5:0] rob_alloc_phys_rd;
    logic [1:0] rob_alloc_is_store, rob_alloc_is_load, rob_alloc_is_branch;
    logic [1:0][31:0] rob_alloc_pc;
    logic rob_alloc_ok;
    logic [1:0][4:0] rob_alloc_idx;
    
    logic lsu_alloc_en, lsu_is_load;
    logic [7:0] lsu_opcode;
    logic [31:0] lsu_offset, lsu_store_data_value;
    logic [4:0] lsu_arch_rs1, lsu_arch_rs2, lsu_arch_rd;
    logic [5:0] lsu_phys_rd, lsu_rob_idx;
    logic lsu_store_data_ready;
    
    // ============================================================
    // ISSUE/Execution
    // ============================================================
    logic [1:0] issue_valid;
    logic [1:0][11:0] issue_op;
    logic [1:0][5:0] issue_dst_tag, issue_rob_tag;
    logic [1:0][31:0] issue_src1_val, issue_src2_val, issue_pc, issue_imm;
    
    // CDB
    logic [1:0] cdb_valid;
    logic [1:0][5:0] cdb_tag, cdb_rob_tag;
    logic [1:0][31:0] cdb_value;
    
    logic branch_result_valid;
    logic [5:0] branch_result_tag;
    logic [31:0] branch_result_value;
    logic [4:0] branch_result_rob_tag;
    logic branch_taken;
    logic [31:0] branch_target_pc;
    logic branch_mispredict;
    
    // ============================================================
    // ROB/Commit
    // ============================================================
    logic [1:0] rob_commit_valid, rob_commit_exception;
    logic [1:0][4:0] rob_commit_arch_rd;
    logic [1:0][5:0] rob_commit_phys_rd;
    logic [1:0][4:0] rob_commit_rob_idx;
    logic [1:0] rob_commit_is_store, rob_commit_is_load, rob_commit_is_branch;
    logic [1:0][31:0] rob_commit_pc;
    logic [1:0] rob_commit_branch_taken;
    logic [1:0][31:0] rob_commit_branch_target;
    logic [1:0] rob_commit_branch_is_call, rob_commit_branch_is_return;
    logic mark_ready_en0, mark_ready_en1;
    logic [4:0] mark_ready_idx0, mark_ready_idx1;
    
    // ============================================================
    // Memory
    // ============================================================
    logic mem_req, mem_we, mem_ready, mem_error, scratchpad_we, scratchpad_ready;
    logic [31:0] mem_addr, mem_wdata, mem_rdata, scratchpad_addr, scratchpad_wdata, scratchpad_rdata;

    // ============================================================
    // Uart
    // ============================================================
    logic        uart_read_en;
    logic        uart_write_en;
    logic [31:0] uart_read_data;
    logic        uart_ready;
    
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
    logic [1:0][4:0] lsu_commit_rob_idx;
    // LSU allocation signals
    logic [5:0]  lsu_base_tag;
    logic        lsu_base_ready;
    logic [31:0] lsu_base_value;
    logic [5:0]  lsu_store_data_tag;
    logic [4:0] lsu_exception_cause;
    
    // Add this as a module-level register:
    logic [31:0] global_seq_counter;
    logic [ISSUE_WIDTH-1:0][31:0] alloc_seq_array ;

     // ============================================================
    // LSU -> (uart or scratchpad) logic
    // ============================================================

    // Address decoder logic
    logic is_uart_access;
    assign is_uart_access = (mem_addr >= 32'h00010000) && 
                            (mem_addr <= 32'h0001000F);
    
    // Multiplex memory/UART signals
    assign uart_read_en = is_uart_access && mem_req;
    assign uart_write_en = is_uart_access && mem_we;
    
    // Connect scratchpad with address check
    assign scratchpad_we = !is_uart_access && mem_we;
    assign scratchpad_addr = mem_addr - 32'h00002000;
    assign scratchpad_wdata = mem_wdata;
    
    // Multiplex read data back to LSU
    assign mem_rdata = is_uart_access ? uart_read_data : scratchpad_rdata;
    assign mem_ready = is_uart_access ? uart_ready : scratchpad_ready;

    // Add this in your always_ff block:
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            global_seq_counter <= 32'd0;
        end else begin
            // Increment by number of instructions allocated this cycle
            if (|rob_alloc_en) begin
                automatic int alloc_count = 0;
                for (int i = 0; i < ISSUE_WIDTH; i++) begin
                    if (rob_alloc_en[i]) alloc_count++;
                end
                global_seq_counter <= global_seq_counter + alloc_count;
            end
        end
    end
    // Compute sequence numbers combinationally:
    always_comb begin
        automatic logic [31:0] seq_temp = global_seq_counter;
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            alloc_seq_array[i] = seq_temp;
            if (rob_alloc_en[i]) seq_temp++;
        end
    end

    
    
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
    
    
    
    // ============================================================
    // FETCH
    // ============================================================
    fetch fetch_inst (
        .clk(clk),
        .reset(reset),
        .branch_taken(branch_taken),
        .branch_target_pc(branch_target_pc),
        
        .fetch_en(fetch_en),
        .stall(fetch_stall),
        .redirect_en(redirect_en),
        .redirect_pc(redirect_pc),
        .flush_pipeline(flush_pipeline),
        
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
    
    assign flush_pipeline = '0;
    //assign flush_pipeline = branch_mispredict || flush_exception;
    assign flush_rob_idx = branch_result_rob_tag; 
    
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
        .rs_alloc_pc(rs_alloc_pc),
        .rs_alloc_imm(rs_alloc_imm),
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
        
        .lsu_offset(lsu_offset),
        .lsu_arch_rs1(lsu_arch_rs1),
        .lsu_arch_rs2(lsu_arch_rs2),
        .lsu_arch_rd(lsu_arch_rd),
        .lsu_phys_rd(lsu_phys_rd),
        .lsu_rob_idx(lsu_rob_idx),
        .lsu_base_tag(lsu_base_tag),
        .lsu_base_ready(lsu_base_ready),
        .lsu_base_value(lsu_base_value),
        .lsu_store_data_tag(lsu_store_data_tag),
        .lsu_store_data_ready(lsu_store_data_ready),
        .lsu_store_data_value(lsu_store_data_value),
        
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
        .alloc_pc(rs_alloc_pc),
        .alloc_imm(rs_alloc_imm),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_value(cdb_value),
        .issue_valid(issue_valid),
        .issue_op(issue_op),
        .issue_dst_tag(issue_dst_tag),
        .issue_src1_val(issue_src1_val),
        .issue_src2_val(issue_src2_val),
        .issue_rob_tag(issue_rob_tag),
        .issue_pc(issue_pc),
        .issue_imm(issue_imm)
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
        .src2_valid(branch_result_valid),
        .src2_tag(branch_result_tag),
        .src2_value(branch_result_value),
        .src2_rob_tag(branch_result_rob_tag),
        .src3_valid(lsu_cdb_valid),
        .src3_tag(lsu_cdb_tag),
        .src3_value(lsu_cdb_value),
        .src3_rob_tag(lsu_cdb_rob_tag),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_value(cdb_value),
        .cdb_rob_tag(cdb_rob_tag)
    );
    
    // ============================================================
    // ROB
    // ============================================================
    
    
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
        
        // Mark ready PORT 0
        .mark_ready_en(mark_ready_en0),
        .mark_ready_idx(mark_ready_idx0),
        .mark_ready_val(1'b1),
        .mark_exception(1'b0),
    
        // Mark ready PORT 1 
        .mark_ready_en1(mark_ready_en1),
        .mark_ready_idx1(mark_ready_idx1),
        .mark_ready_val1(1'b1),
        .mark_exception1(1'b0),
        
        .branch_outcome_en(branch_result_valid),
        .branch_outcome_idx(branch_result_rob_tag),
        .branch_outcome_taken(branch_taken),
        .branch_outcome_target(branch_target_pc),
        .branch_outcome_is_call(branch_outcome_is_call),   
        .branch_outcome_is_return(branch_outcome_is_return),
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
        .flush_ptr('0),
        .flush_pipeline(flush_pipeline),
        .flush_rob_idx(flush_rob_idx)
    );
    
    // Mark ROB ready from CDB
    
    
    assign mark_ready_en0 = cdb_valid[0];
    assign mark_ready_idx0 = cdb_rob_tag[0][4:0];
    
    assign mark_ready_en1 = cdb_valid[1];
    assign mark_ready_idx1 = cdb_rob_tag[1][4:0];
    
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
        .flush_pipeline(flush_exception),
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
        .perf_exceptions(),
        .lsu_base_tag(lsu_base_tag),
        .lsu_base_ready(lsu_base_ready)
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
        // Writes from CDB
        .wen0(prf_wen[0]),
        .wtag0(prf_wtag[0]),
        .wdata0(prf_wdata[0]),
        .wen1(prf_wen[1]),
        .wtag1(prf_wtag[1]),
        .wdata1(prf_wdata[1]),
        
        // Reads for dispatch
        .rtag0(prf_rtag0),
        .rdata0(prf_rdata0),
        .rtag1(prf_rtag1),
        .rdata1(prf_rdata1),
        .rtag2(prf_rtag2),
        .rdata2(prf_rdata2),
        .rtag3(prf_rtag3),
        .rdata3(prf_rdata3),
        
        // Reads for commit (NEW)
        .rtag4(prf_commit_rtag[0]),
        .rdata4(prf_commit_rdata[0]),
        .rtag5(prf_commit_rtag[1]),
        .rdata5(prf_commit_rdata[1])
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
        
        // Allocation interface
        .alloc_en(lsu_alloc_en),
        .is_load(lsu_is_load),
        .opcode(lsu_opcode),
        .alloc_seq(lsu_alloc_en ? alloc_seq_array[lsu_lane_index] : 32'd0),
        
        // Base address operand (rs1)
        .base_addr_tag(lsu_base_tag),
        .base_addr_ready(lsu_base_ready),
        .base_addr_value(lsu_base_value),
        
        // Store data operand (rs2)
        .store_data_tag(lsu_store_data_tag),
        .store_data_ready(lsu_store_data_ready),
        .store_data_value(lsu_store_data_value),
        
        .offset(lsu_offset),
        .arch_rs1(lsu_arch_rs1),
        .arch_rs2(lsu_arch_rs2),
        .arch_rd(lsu_arch_rd),
        .phys_rd(lsu_phys_rd),
        .rob_idx(lsu_rob_idx),
        
        // CDB interface (for wakeup)
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),      
        .cdb_value(cdb_value),
        
        // CDB output
        .cdb_req(lsu_cdb_valid),
        .cdb_req_tag(lsu_cdb_tag),
        .cdb_req_value(lsu_cdb_value),
        .cdb_req_exception(lsu_cdb_exception),
        
        // ROB interface
        .commit_en(rob_commit_valid),
        .commit_is_store(rob_commit_is_store),
        .commit_rob_idx(rob_commit_rob_idx),
        
        .lsu_exception(lsu_exception),
        .lsu_exception_cause(lsu_exception_cause),
        
        // Memory interface
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .mem_error(mem_error)
    );

    // ============================================================
    // UART Sim Unit
    // ============================================================
    
    uart_stub uart_inst (
        .clk(clk),
        .reset(reset),
        .addr(mem_addr),
        .read_en(uart_read_en),
        .write_en(uart_write_en),
        .write_data(mem_wdata),
        .read_data(uart_read_data),
        .ready(uart_ready)
    );
    
    // ============================================================
    // Branch Execution Unit
    // ============================================================
    
    branch_ex branch_inst (
        .clk(clk),
        .reset(reset),
        .flush_pipeline(flush_pipeline),
        
        
        .issue_valid(issue_valid),     
        .issue_op(issue_op),
        .issue_dst_tag(issue_dst_tag),
        .issue_src1_val(issue_src1_val),
        .issue_src2_val(issue_src2_val),
        .issue_pc(issue_pc),            
        .issue_imm(issue_imm),          
        .issue_rob_tag(issue_rob_tag),
        
        // Outputs to CDB arbiter
        .branch_result_valid(branch_result_valid),
        .branch_result_tag(branch_result_tag),
        .branch_result_value(branch_result_value),
        .branch_result_rob_tag(branch_result_rob_tag),
        .is_call(branch_outcome_is_call),
        .is_return(branch_outcome_is_return),
        
        // Outputs to ROB/Fetch for mispredict handling
        .branch_taken(branch_taken),
        .branch_target_pc(branch_target_pc),
        .branch_mispredict(branch_mispredict)
    );
    
    // ============================================================
    // DATA SCRATCHPAD
    // ============================================================
    data_scratchpad dmem (
        .clk(clk),
        .reset(reset),
        .mem_req(scratchpad_we || (mem_req && !is_uart_access && !mem_we)),
        .mem_we(scratchpad_we),
        .mem_addr(scratchpad_addr),
        .mem_wdata(scratchpad_wdata),
        .mem_size(2'b10),
        .mem_atomic(1'b0),
        .mem_cmp_val('0),
        .mem_ready(scratchpad_ready),
        .mem_rdata(scratchpad_rdata),
        .mem_error(mem_error)
    );

endmodule
