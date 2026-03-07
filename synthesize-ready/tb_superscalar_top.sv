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
        #300;
        $finish;
    end
    
    // ============================================================
    // Cycle-by-cycle monitoring
    // ============================================================
    int cycle;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            cycle <= 0;
        end else begin
            cycle <= cycle + 1;
            
            $display("\n========== CYCLE %0d ==========", cycle);
            
            // FETCH
            $display("[FETCH] PC=%h ren=%b valid=%b instr0=%h instr1=%h", 
                dut.imem_addr0, dut.imem_ren, dut.if_valid, 
                dut.if_instr[0], dut.if_instr[1]);
            if (!reset && cycle < 10) begin
                $display("C%0d: ren=%b addr=%h valid=%b data=%h stall=%b if_valid=%b", 
                    cycle, dut.imem_ren, dut.imem_addr0, dut.imem_valid, 
                    dut.imem_rdata0, dut.fetch_stall, dut.if_valid);
            end
            // DECODE
            if (dut.dec_valid != 0) begin
                for (int i = 0; i < 2; i++) begin
                    if (dut.dec_valid[i]) begin
                        $display("[DECODE%0d] op=%h rd=x%0d rs1=x%0d rs2=x%0d imm=%0d flags=alu:%b ld:%b st:%b br:%b",
                            i, dut.dec_opcode[i], dut.dec_rd[i], dut.dec_rs1[i], dut.dec_rs2[i],
                            $signed(dut.dec_imm[i]), dut.dec_is_alu[i], dut.dec_is_load[i], 
                            dut.dec_is_store[i], dut.dec_is_branch[i]);
                    end
                end
            end
            
            // RENAME
            if (dut.rename_valid != 0) begin
                for (int i = 0; i < 2; i++) begin
                    if (dut.rename_valid[i]) begin
                        $display("[RENAME%0d] ard=x%0d->p%0d prs1=p%0d prs2=p%0d",
                            i, dut.rename_arch_rd[i], dut.rename_prd[i], 
                            dut.rename_prs1[i], dut.rename_prs2[i]);
                    end
                end
            end
            
            // ROB ALLOCATION
            if (dut.rob_alloc_en != 0 && dut.rob_alloc_ok) begin
                for (int i = 0; i < 2; i++) begin
                    if (dut.rob_alloc_en[i]) begin
                        $display("[ROB_ALLOC%0d] idx=%0d ard=x%0d prd=p%0d pc=%h ld:%b st:%b br:%b",
                            i, dut.rob_alloc_idx[i], dut.rob_alloc_arch_rd[i], 
                            dut.rob_alloc_phys_rd[i], dut.rob_alloc_pc[i],
                            dut.rob_alloc_is_load[i], dut.rob_alloc_is_store[i], 
                            dut.rob_alloc_is_branch[i]);
                    end
                end
            end
            
            // RS ALLOCATION
            if (dut.rs_alloc_en != 0) begin
                for (int i = 0; i < 2; i++) begin
                    if (dut.rs_alloc_en[i]) begin
                        $display("[RS_ALLOC%0d] dst=p%0d src1=p%0d(%b) src2=p%0d(%b) rob=%0d op=%h",
                            i, dut.rs_alloc_dst_tag[i], dut.rs_alloc_src1_tag[i], 
                            dut.rs_alloc_src1_ready[i], dut.rs_alloc_src2_tag[i], 
                            dut.rs_alloc_src2_ready[i], dut.rs_alloc_rob_tag[i],
                            dut.rs_alloc_op[i]);
                    end
                end
            end
            
            // ISSUE
            if (dut.issue_valid != 0) begin
                for (int i = 0; i < 2; i++) begin
                    if (dut.issue_valid[i]) begin
                        $display("[ISSUE%0d] dst=p%0d src1=%h src2=%h rob=%0d op=%h",
                            i, dut.issue_dst_tag[i], dut.issue_src1_val[i][31:0], 
                            dut.issue_src2_val[i][31:0], dut.issue_rob_tag[i],
                            dut.issue_op[i]);
                    end
                end
            end
            
            // CDB
            if (dut.cdb_valid != 0) begin
                for (int i = 0; i < 2; i++) begin
                    if (dut.cdb_valid[i]) begin
                        $display("[CDB%0d] tag=p%0d value=%h rob=%0d",
                            i, dut.cdb_tag[i], dut.cdb_value[i], dut.cdb_rob_tag[i]);
                    end
                end
            end
            
            // COMMIT
            if (dut.rob_commit_valid != 0) begin
                for (int i = 0; i < 2; i++) begin
                    if (dut.rob_commit_valid[i]) begin
                        $display("[COMMIT%0d] rob=%0d ard=x%0d prd=p%0d pc=%h ld:%b st:%b",
                            i, dut.rob_commit_rob_idx[i], dut.rob_commit_arch_rd[i], 
                            dut.rob_commit_phys_rd[i], dut.rob_commit_pc[i],
                            dut.rob_commit_is_load[i], dut.rob_commit_is_store[i]);
                    end
                end
            end
            
            // LSU
            if (dut.lsu_alloc_en) begin
                $display("[LSU_ALLOC] ld:%b addr=%h+%0d prd=p%0d rob=%0d",
                    dut.lsu_is_load, dut.lsu_base_addr, dut.lsu_offset,
                    dut.lsu_phys_rd, dut.lsu_rob_idx);
            end
            if (dut.mem_req) begin
                $display("[MEM] we:%b addr=%h wdata=%h", 
                    dut.mem_we, dut.mem_addr, dut.mem_wdata);
            end
            
            // FLUSH
            if (dut.flush_pipeline) begin
                $display("[FLUSH] pc=%h", dut.flush_pc);
            end
        end
    end
    // ROB Internal State Monitor
    always_ff @(posedge clk) begin
        if (!reset) begin
            automatic int local_head, local_tail, local_occ;
            automatic int alloc_cnt, commit_cnt;
            
            // Capture automatic variables (sample at clock edge)
            local_head = dut.rob_inst.head;
            local_tail = dut.rob_inst.tail;
            local_occ = dut.rob_inst.occupancy;
            
            // Allocation tracking
            if (dut.rob_alloc_en != 0) begin
                alloc_cnt = 0;
                for (int i = 0; i < 2; i++) begin
                    if (dut.rob_alloc_en[i]) alloc_cnt++;
                end
                $display("[ROB_ALLOC] slots=%0d ok=%b head=%0d tail=%0d→%0d occ=%0d→%0d",
                    alloc_cnt, dut.rob_alloc_ok,
                    local_head, local_tail, dut.rob_inst.tail,
                    local_occ, dut.rob_inst.occupancy);
            end
            
            // Mark ready tracking
            if (dut.mark_ready_en0 || dut.mark_ready_en1) begin
                $display("[ROB_MARK_READY] port0=%b(idx=%0d) port1=%b(idx=%0d)",
                    dut.mark_ready_en0, dut.mark_ready_idx0,
                    dut.mark_ready_en1, dut.mark_ready_idx1);
            end
            
            // Commit tracking
            if (dut.rob_commit_valid != 0) begin
                commit_cnt = 0;
                for (int i = 0; i < 2; i++) begin
                    if (dut.rob_commit_valid[i]) begin
                        $display("[ROB_COMMIT_DETAIL%0d] rob_idx=%0d ard=x%0d prd=p%0d ready=%b pc=%h",
                            i, dut.rob_commit_rob_idx[i],
                            dut.rob_commit_arch_rd[i], dut.rob_commit_phys_rd[i],
                            dut.rob_inst.rob_mem[dut.rob_commit_rob_idx[i]].ready,
                            dut.rob_commit_pc[i]);
                        commit_cnt++;
                    end
                end
                $display("[ROB_COMMIT_STATE] slots=%0d head=%0d→%0d occ=%0d→%0d",
                    commit_cnt, local_head, dut.rob_inst.head,
                    local_occ, dut.rob_inst.occupancy);
            end
            
            // Show head entry state every 5 cycles
            if (cycle % 5 == 0 && local_occ > 0) begin
                $display("[ROB_HEAD_STATUS] idx=%0d valid=%b ready=%b ard=x%0d pc=%h",
                    local_head,
                    dut.rob_inst.rob_mem[local_head].valid,
                    dut.rob_inst.rob_mem[local_head].ready,
                    dut.rob_inst.rob_mem[local_head].arch_rd,
                    dut.rob_inst.rob_mem[local_head].pc);
            end
        end
    end

    /*
    // ============================================================
    // RS Table Display (every 10 cycles)
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset && (cycle % 2 == 0)) begin
            $display("\n===== RS TABLE (Cycle %0d) =====", cycle);
            $display("Entry | V | Dst | Src1(R) | Src2(R) | Op   | ROB | Age");
            $display("------|---|-----|---------|---------|------|-----|----");
            for (int i = 0; i < 16; i++) begin
                if (dut.rs_inst.rs_mem[i].valid) begin
                    $display("  %2d  | %b | p%-2d | p%-2d(%b) | p%-2d(%b) | %h |  %-2d | %0d",
                        i,
                        dut.rs_inst.rs_mem[i].valid,
                        dut.rs_inst.rs_mem[i].dst_tag,
                        dut.rs_inst.rs_mem[i].src1_tag,
                        dut.rs_inst.rs_mem[i].src1_ready,
                        dut.rs_inst.rs_mem[i].src2_tag,
                        dut.rs_inst.rs_mem[i].src2_ready,
                        dut.rs_inst.rs_mem[i].opcode,
                        dut.rs_inst.rs_mem[i].rob_tag,
                        dut.rs_inst.rs_mem[i].age);
                end
            end
        end
    end
    
    // ============================================================
    // ROB Table Display (every 10 cycles)
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset && (cycle % 2 == 0)) begin
            $display("\n===== ROB TABLE (Cycle %0d) =====", cycle);
            $display("Idx | V | R | ARD | PRD | PC       | LD | ST | BR | Exception");
            $display("----|---|---|-----|-----|----------|----|----|----|-----------");
            for (int i = 0; i < 16; i++) begin
                if (dut.rob_inst.rob_mem[i].valid) begin
                    $display(" %2d | %b | %b | x%-2d | p%-2d | %h |  %b |  %b |  %b |     %b",
                        i,
                        dut.rob_inst.rob_mem[i].valid,
                        dut.rob_inst.rob_mem[i].ready,
                        dut.rob_inst.rob_mem[i].arch_rd,
                        dut.rob_inst.rob_mem[i].phys_rd,
                        dut.rob_inst.rob_mem[i].pc,
                        dut.rob_inst.rob_mem[i].is_load,
                        dut.rob_inst.rob_mem[i].is_store,
                        dut.rob_inst.rob_mem[i].is_branch,
                        dut.rob_inst.rob_mem[i].exception);
                end
            end
            $display("HEAD=%0d TAIL=%0d OCCUPANCY=%0d", 
                dut.rob_inst.head, dut.rob_inst.tail, dut.rob_inst.occupancy);
        end
    end
    
    always_ff @(posedge clk) begin
        if (dut.mem_req) begin
            $display("[MEM] req=%b we=%b addr=%h wdata=%h ready=%b rdata=%h",
                dut.mem_req, dut.mem_we, dut.mem_addr, dut.mem_wdata,
                dut.mem_ready, dut.mem_rdata);
        end
    end
    
    // ============================================================
    // ARF Display (every 50 cycles)
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset) begin
            $display("\n===== ARCH REGISTER FILE (Cycle %0d) =====", cycle);
            for (int i = 0; i < 32; i += 4) begin
                $display("X%-2d=%h  X%-2d=%h  X%-2d=%h  X%-2d=%h",
                    i, dut.arf_inst.regs[i],
                    i+1, dut.arf_inst.regs[i+1],
                    i+2, dut.arf_inst.regs[i+2],
                    i+3, dut.arf_inst.regs[i+3]);
            end
        end
    end

    // ============================================================
    // PRF Display 
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset) begin
            $display("\n===== ARCH REGISTER FILE (Cycle %0d) =====", cycle);
            for (int i = 0; i < 32; i += 4) begin
                $display("X%-2d=%h  X%-2d=%h  X%-2d=%h  X%-2d=%h",
                    i, dut.prf_inst.regs[i],
                    i+1, dut.prf_inst.regs[i+1],
                    i+2, dut.prf_inst.regs[i+2],
                    i+3, dut.prf_inst.regs[i+3]);
            end
        end
    end
    
    // Dump waveforms
    initial begin
        $dumpfile("ooo_core.vcd");
        $dumpvars(0, tb_ooo_core);
    end */

endmodule
