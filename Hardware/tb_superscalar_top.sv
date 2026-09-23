`timescale 1ns/1ps

module tb_ooo_core;

    logic clk;
    logic reset;
    
    // Instantiate DUT
    ooo_core_top dut (
        .clk(clk),
        .reset(reset)
    );
    
    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Reset and run
    initial begin
        reset = 1;
        #95;
        reset = 0;
        #15000;
        $finish;
    end
    
    // ============================================================
    // Cycle-by-cycle monitoring
    // ============================================================
// ================================================================
// FULL CYCLE-BY-CYCLE DEBUG TRACE
// ================================================================

integer cycle_count;

initial begin
    cycle_count = 0;
end

always @(posedge dut.clk_core) begin
    if (!dut.sys_reset) begin

        cycle_count = cycle_count + 1;

        $display("");
        $display("==============================================================");
        $display(" CYCLE %0d   TIME %0t ns", cycle_count, $time);
        $display("==============================================================");

        // --------------------------------------------------------
        // FETCH
        // --------------------------------------------------------
        $display("--- FETCH ---");
        $display(" fetch_en=%b stall=%b redirect=%b flush=%b",
                 dut.fetch_en,
                 dut.fetch_stall,
                 dut.redirect_en,
                 dut.flush_pipeline);

        $display(" if_valid=%b", dut.if_valid);
        $display(" if_pc[0]=%08h  instr[0]=%08h",
                 dut.if_pc[0], dut.if_instr[0]);
        $display(" if_pc[1]=%08h  instr[1]=%08h",
                 dut.if_pc[1], dut.if_instr[1]);

        // --------------------------------------------------------
        // DECODE
        // --------------------------------------------------------
        $display("--- DECODE ---");
        $display(" dec_valid=%b", dut.dec_valid);

        $display(" L0: opcode=%02h rs1=%0d rs2=%0d rd=%0d imm=%08h pc=%08h",
                 dut.dec_opcode[0],
                 dut.dec_rs1[0],
                 dut.dec_rs2[0],
                 dut.dec_rd[0],
                 dut.dec_imm[0],
                 dut.dec_pc[0]);

        $display(" L1: opcode=%02h rs1=%0d rs2=%0d rd=%0d imm=%08h pc=%08h",
                 dut.dec_opcode[1],
                 dut.dec_rs1[1],
                 dut.dec_rs2[1],
                 dut.dec_rd[1],
                 dut.dec_imm[1],
                 dut.dec_pc[1]);

        $display(" rs1_valid=%b rs2_valid=%b rd_valid=%b",
                 dut.dec_rs1_valid,
                 dut.dec_rs2_valid,
                 dut.dec_rd_valid);

        $display(" is_alu=%b load=%b store=%b branch=%b cas=%b",
                 dut.dec_is_alu,
                 dut.dec_is_load,
                 dut.dec_is_store,
                 dut.dec_is_branch,
                 dut.dec_is_cas);

        // --------------------------------------------------------
        // RENAME
        // --------------------------------------------------------
        $display("--- RENAME ---");
        $display(" rename_ready=%b rename_valid=%b",
                 dut.rename_ready,
                 dut.rename_valid);

        $display(" L0: arch_rs1=%0d arch_rs2=%0d arch_rd=%0d",
                 dut.rename_arch_rs1[0],
                 dut.rename_arch_rs2[0],
                 dut.rename_arch_rd[0]);

        $display(" L1: arch_rs1=%0d arch_rs2=%0d arch_rd=%0d",
                 dut.rename_arch_rs1[1],
                 dut.rename_arch_rs2[1],
                 dut.rename_arch_rd[1]);

        $display(" L0: prs1=%0d prs2=%0d prd=%0d",
                 dut.rename_prs1[0],
                 dut.rename_prs2[0],
                 dut.rename_prd[0]);

        $display(" L1: prs1=%0d prs2=%0d prd=%0d",
                 dut.rename_prs1[1],
                 dut.rename_prs2[1],
                 dut.rename_prd[1]);

        $display(" rs1_valid=%b rs2_valid=%b rd_valid=%b",
                 dut.rename_rs1_valid,
                 dut.rename_rs2_valid,
                 dut.rename_rd_valid);

        $display(" rename_is_alu=%b load=%b store=%b branch=%b cas=%b",
                 dut.rename_is_alu,
                 dut.rename_is_load,
                 dut.rename_is_store,
                 dut.rename_is_branch,
                 dut.rename_is_cas);

        // --------------------------------------------------------
        // COMMIT -> RENAME FEEDBACK
        // --------------------------------------------------------
        $display("--- COMMIT -> RENAME ---");
        $display(" commit_en=%b", dut.commit_en);

        $display(" commit lane0: arch=%0d phys=%0d",
                 dut.commit_arch_rd[0],
                 dut.commit_phys_rd[0]);

        $display(" commit lane1: arch=%0d phys=%0d",
                 dut.commit_arch_rd[1],
                 dut.commit_phys_rd[1]);

        // --------------------------------------------------------
        // RENAME TABLES
        // --------------------------------------------------------
        $display("--- RENAME TABLES ---");

        $write(" map_table:    ");
        for (int i = 0; i < 32; i++)
            $write("%0d:%0d ", i, dut.map_table[i]);
        $display("");

        $write(" committed:    ");
        for (int i = 0; i < 32; i++)
            $write("%0d:%0d ", i, dut.committed_table[i]);
        $display("");

        // --------------------------------------------------------
        // FREE LIST
        // --------------------------------------------------------
        $display("--- FREE LIST ---");

        $display(" alloc_en=%b", dut.freelist_alloc_en);
        $display(" alloc_phys=%0d,%0d",
                 dut.freelist_alloc_phys[0],
                 dut.freelist_alloc_phys[1]);

        $display(" free_en=%b", dut.freelist_free_en);
        $display(" free_phys=%0d,%0d",
                 dut.freelist_free_phys[0],
                 dut.freelist_free_phys[1]);

        $display(" free_mask=%016h", dut.freelist_free_mask);

        // --------------------------------------------------------
        // DISPATCH
        // --------------------------------------------------------
        $display("--- DISPATCH ---");
        $display(" dispatch_stall=%b", dut.dispatch_stall);

        $display(" rs_alloc_en=%b", dut.rs_alloc_en);

        $display(" RS0: dst=%0d src1=%0d src2=%0d rob=%0d",
                 dut.rs_alloc_dst_tag[0],
                 dut.rs_alloc_src1_tag[0],
                 dut.rs_alloc_src2_tag[0],
                 dut.rs_alloc_rob_tag[0]);

        $display(" RS1: dst=%0d src1=%0d src2=%0d rob=%0d",
                 dut.rs_alloc_dst_tag[1],
                 dut.rs_alloc_src1_tag[1],
                 dut.rs_alloc_src2_tag[1],
                 dut.rs_alloc_rob_tag[1]);

        $display(" src1_ready=%b src2_ready=%b",
                 dut.rs_alloc_src1_ready,
                 dut.rs_alloc_src2_ready);

        // --------------------------------------------------------
        // ROB ALLOCATION
        // --------------------------------------------------------
        $display("--- ROB ALLOCATION ---");
        $display(" rob_alloc_en=%b ok=%b",
                 dut.rob_alloc_en,
                 dut.rob_alloc_ok);

        $display(" L0: idx=%0d arch=%0d phys=%0d pc=%08h",
                 dut.rob_alloc_idx[0],
                 dut.rob_alloc_arch_rd[0],
                 dut.rob_alloc_phys_rd[0],
                 dut.rob_alloc_pc[0]);

        $display(" L1: idx=%0d arch=%0d phys=%0d pc=%08h",
                 dut.rob_alloc_idx[1],
                 dut.rob_alloc_arch_rd[1],
                 dut.rob_alloc_phys_rd[1],
                 dut.rob_alloc_pc[1]);

        // --------------------------------------------------------
        // RESERVATION STATION
        // --------------------------------------------------------
        $display("--- ISSUE ---");

        $display(" issue_valid=%b", dut.issue_valid);

        $display(" L0: op=%03h dst=%0d rob=%0d src1=%08h src2=%08h",
                 dut.issue_op[0],
                 dut.issue_dst_tag[0],
                 dut.issue_rob_tag[0],
                 dut.issue_src1_val[0],
                 dut.issue_src2_val[0]);

        $display(" L1: op=%03h dst=%0d rob=%0d src1=%08h src2=%08h",
                 dut.issue_op[1],
                 dut.issue_dst_tag[1],
                 dut.issue_rob_tag[1],
                 dut.issue_src1_val[1],
                 dut.issue_src2_val[1]);

        // --------------------------------------------------------
        // ALU
        // --------------------------------------------------------
        $display("--- ALU RESULTS ---");

        $display(" ALU0: valid=%b tag=%0d rob=%0d value=%08h",
                 dut.alu0_result_valid,
                 dut.alu0_result_tag,
                 dut.alu0_result_rob_tag,
                 dut.alu0_result_value);

        $display(" ALU1: valid=%b tag=%0d rob=%0d value=%08h",
                 dut.alu1_result_valid,
                 dut.alu1_result_tag,
                 dut.alu1_result_rob_tag,
                 dut.alu1_result_value);

        // --------------------------------------------------------
        // CDB
        // --------------------------------------------------------
        $display("--- CDB ---");

        $display(" cdb_valid=%b", dut.cdb_valid);

        $display(" CDB0: tag=%0d rob=%0d value=%08h",
                 dut.cdb_tag[0],
                 dut.cdb_rob_tag[0],
                 dut.cdb_value[0]);

        $display(" CDB1: tag=%0d rob=%0d value=%08h",
                 dut.cdb_tag[1],
                 dut.cdb_rob_tag[1],
                 dut.cdb_value[1]);

        // --------------------------------------------------------
        // ROB COMMIT
        // --------------------------------------------------------
        $display("--- COMMIT ---");

        $display(" rob_commit_valid=%b exception=%b",
                 dut.rob_commit_valid,
                 dut.rob_commit_exception);

        $display(" L0: rob=%0d arch=%0d phys=%0d pc=%08h",
                 dut.rob_commit_rob_idx[0],
                 dut.rob_commit_arch_rd[0],
                 dut.rob_commit_phys_rd[0],
                 dut.rob_commit_pc[0]);

        $display(" L1: rob=%0d arch=%0d phys=%0d pc=%08h",
                 dut.rob_commit_rob_idx[1],
                 dut.rob_commit_arch_rd[1],
                 dut.rob_commit_phys_rd[1],
                 dut.rob_commit_pc[1]);

        // --------------------------------------------------------
        // PRF WRITEBACK
        // --------------------------------------------------------
        $display("--- PRF WRITEBACK ---");

        $display(" prf_wen=%b", dut.prf_wen);

        $display(" W0: tag=%0d data=%08h",
                 dut.prf_wtag[0],
                 dut.prf_wdata[0]);

        $display(" W1: tag=%0d data=%08h",
                 dut.prf_wtag[1],
                 dut.prf_wdata[1]);

        // --------------------------------------------------------
        // BRANCH
        // --------------------------------------------------------
        $display("--- BRANCH ---");

        $display(" result_valid=%b tag=%0d rob=%0d",
                 dut.branch_result_valid,
                 dut.branch_result_tag,
                 dut.branch_result_rob_tag);

        $display(" taken=%b target=%08h mispredict=%b",
                 dut.branch_taken,
                 dut.branch_target_pc,
                 dut.branch_mispredict);

        // --------------------------------------------------------
        // LSU
        // --------------------------------------------------------
        $display("--- LSU ---");

        $display(" alloc_en=%b load=%b",
                 dut.lsu_alloc_en,
                 dut.lsu_is_load);

        $display(" base: tag=%0d ready=%b value=%08h",
                 dut.lsu_base_tag,
                 dut.lsu_base_ready,
                 dut.lsu_base_value);

        $display(" store: tag=%0d ready=%b value=%08h",
                 dut.lsu_store_data_tag,
                 dut.lsu_store_data_ready,
                 dut.lsu_store_data_value);

        $display(" cdb: valid=%b tag=%0d value=%08h rob=%0d",
                 dut.lsu_cdb_valid,
                 dut.lsu_cdb_tag,
                 dut.lsu_cdb_value,
                 dut.lsu_cdb_rob_tag);

        // --------------------------------------------------------
        // SEQUENCE NUMBERS
        // --------------------------------------------------------
        $display("--- SEQUENCE ---");

        $display(" global_seq_counter=%0d",
                 dut.global_seq_counter);

        $display(" alloc_seq[0]=%0d alloc_seq[1]=%0d",
                 dut.alloc_seq_array[0],
                 dut.alloc_seq_array[1]);

        $display("");
    end
end
endmodule
