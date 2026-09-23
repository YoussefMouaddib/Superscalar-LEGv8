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

        // ================================================================
        // RENAME STAGE DEBUG DISPLAY
        // ================================================================
        
        
            
        
            $display("");
            $display("================================================================================================================");
            $display(" CYCLE / RENAME DEBUG");
            $display("================================================================================================================");
        
            // ------------------------------------------------------------
            // Basic control
            // ------------------------------------------------------------
            $display("TIME=%0t | RESET=%b | FLUSH=%b | RENAME_READY=%b",
                     $time,
                     dut.sys_reset,
                     dut.rename_inst.flush_pipeline,
                     dut.rename_inst.rename_ready);
        
           
        
            // ------------------------------------------------------------
            // FREE LIST
            // ------------------------------------------------------------
            $display("---- FREE LIST ------------------------------------------------------------------------------------------------");
        
            for (int i = 0; i < 2; i++) begin
                $display(
                    "LANE%0d | alloc_en=%b | alloc_valid=%b | alloc_phys=%0d",
                    i,
                    dut.rename_inst.alloc_en[i],
                    dut.rename_inst.alloc_valid[i],
                    dut.rename_inst.alloc_phys[i]
                );
            end
        
            // Internal free-list state
            $display("FREE_MASK      = %b",
                     dut.rename_inst.free_list_inst.free_mask);
        
            $display("FREE_EN_R      = %b",
                     dut.rename_inst.free_list_inst.free_en_r);
        
            for (int i = 0; i < 2; i++) begin
                $display(
                    "FREE_R[%0d]     = phys=%0d",
                    i,
                    dut.rename_inst.free_list_inst.free_phys_r[i]
                );
            end
        
            // ------------------------------------------------------------
            // RENAME TABLE LOOKUPS
            // ------------------------------------------------------------
            $display("---- RENAME TABLE LOOKUPS ------------------------------------------------------------------------------------");
        
            for (int i = 0; i < 2; i++) begin
                $display(
                    "LANE%0d | arch_rs1=%0d -> phys_rs1=%0d | arch_rs2=%0d -> phys_rs2=%0d",
                    i,
                    dut.rename_inst.dec_rs1[i],
                    dut.rename_inst.phys_rs1[i],
                    dut.rename_inst.dec_rs2[i],
                    dut.rename_inst.phys_rs2[i]
                );
            end
        
            // ------------------------------------------------------------
            // RENAME TABLE INTERNAL STATE
            // ------------------------------------------------------------
            $display("---- RENAME TABLE STATE --------------------------------------------------------------------------------------");
        
            for (int i = 0; i < 32; i++) begin
                $display(
                    "ARCH R%02d | speculative P%02d | committed P%02d",
                    i,
                    dut.rename_inst.rename_table_inst.map_table[i],
                    dut.rename_inst.rename_table_inst.committed_table[i]
                );
            end
        
            // ------------------------------------------------------------
            // SAME-CYCLE RENAME FORWARDING
            // ------------------------------------------------------------
            $display("---- SAME-CYCLE RENAME ---------------------------------------------------------------------------------------");
        
            for (int i = 0; i < 2; i++) begin
                $display(
                    "LANE%0d | rename_en=%b | arch_rd=%0d | new_phys_rd=%0d",
                    i,
                    dut.rename_inst.rename_en[i],
                    dut.rename_inst.rename_arch_rd_wire[i],
                    dut.rename_inst.rename_new_phys_rd[i]
                );
            end
        
            // ------------------------------------------------------------
            // COMMIT INFORMATION
            // ------------------------------------------------------------
            $display("---- COMMIT INPUTS --------------------------------------------------------------------------------------------");
        
            for (int i = 0; i < 2; i++) begin
                $display(
                    "LANE%0d | commit_en=%b | arch_rd=%0d | phys_rd=%0d",
                    i,
                    dut.rename_inst.commit_en[i],
                    dut.rename_inst.commit_arch_rd_r[i],
                    dut.rename_inst.commit_phys_rd_r[i]
                );
            end
        
            // ------------------------------------------------------------
            // RENAME OUTPUTS
            // ------------------------------------------------------------
            $display("---- RENAME OUTPUTS -------------------------------------------------------------------------------------------");
        
            for (int i = 0; i < 2; i++) begin
                $display(
                    "LANE%0d | valid=%b | PC=%08h | opcode=%02h | 
                    PRS1=P%0d | PRS2=P%0d | PRD=P%0d | 
                    ARCH_RS1=R%0d | ARCH_RS2=R%0d | ARCH_RD=R%0d | 
                    rs1_v=%b rs2_v=%b rd_v=%b",
                    i,
                    dut.rename_inst.rename_valid[i],
                    dut.rename_inst.rename_pc[i],
                    dut.rename_inst.rename_opcode[i],
                    dut.rename_inst.rename_prs1[i],
                    dut.rename_inst.rename_prs2[i],
                    dut.rename_inst.rename_prd[i],
                    dut.rename_inst.rename_arch_rs1[i],
                    dut.rename_inst.rename_arch_rs2[i],
                    dut.rename_inst.rename_arch_rd[i],
                    dut.rename_inst.rename_rs1_valid[i],
                    dut.rename_inst.rename_rs2_valid[i],
                    dut.rename_inst.rename_rd_valid[i]
                );
            end
        
            // ------------------------------------------------------------
            // CLASSIFICATION OUTPUTS
            // ------------------------------------------------------------
            $display("---- INSTRUCTION TYPE -----------------------------------------------------------------------------------------");
        
            for (int i = 0; i < 2; i++) begin
                $display(
                    "LANE%0d | ALU=%b LOAD=%b STORE=%b BRANCH=%b CAS=%b | ALU_FUNC=%02h | IMM=%08h",
                    i,
                    dut.rename_inst.rename_is_alu[i],
                    dut.rename_inst.rename_is_load[i],
                    dut.rename_inst.rename_is_store[i],
                    dut.rename_inst.rename_is_branch[i],
                    dut.rename_inst.rename_is_cas[i],
                    dut.rename_inst.rename_alu_func[i],
                    dut.rename_inst.rename_imm[i]
                );
            end
        
            $display("================================================================================================================");
        end

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
endmodule
