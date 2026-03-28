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
        #10000;
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
            /*if (dut.lsu_alloc_en) begin
                $display("[LSU_ALLOC] ld:%b addr=%h+%0d prd=p%0d rob=%0d",
                    dut.lsu_is_load, dut.lsu_base_addr, dut.lsu_offset,
                    dut.lsu_phys_rd, dut.lsu_rob_idx);
            end*/
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
    // In your testbench module, add these signals:
        logic [7:0] uart_tx_char;
        assign uart_tx_char = dut.uart_inst.tx_data_reg;
        
        // Monitor UART writes
        always @(posedge clk) begin
            if (!reset) begin
                // Display as both ASCII and hex
                
                $display("[UART TX] '%c' (0x%h)", uart_tx_char, uart_tx_char);
                
                
            end
        end
        
    



    
    // ============================================================
    // RS Table Display (every 10 cycles)
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset ) begin
            $display("\n===== RS TABLE (Cycle %0d) =====", cycle);
            $display("Entry | V | Dst | Src1(R) | Src2(R) | Op   | ROB | Age");
            $display("------|---|-----|---------|---------|------|-----|----");
            for (int i = 0; i < 32; i++) begin
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
    /*
    // ============================================================
    // ROB Table Display (every 10 cycles)
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset ) begin
            $display("\n===== ROB TABLE (Cycle %0d) =====", cycle);
            $display("Idx | V | R | ARD | PRD | PC       | LD | ST | BR | Exception");
            $display("----|---|---|-----|-----|----------|----|----|----|-----------");
            for (int i = 0; i < 32; i++) begin
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
    /*
        always @(posedge clk) begin
        // Print after the posedge to capture the state at the end of the cycle
        // Use a small delay to ensure all signals have settled (optional)
        #1;
        
        $display("========== CYCLE %0d LSU QUEUES ==========", cycle);
        
        // Load Queue (LQ)
            $display("LQ (head=%0d, tail=%0d):", dut.lsu_inst.lq_head, dut.lsu_inst.lq_tail);
            for (int i = 0; i < 16; i++) begin
                if (dut.lsu_inst.lq[i].valid) begin
                $display("  LQ[%0d]: valid=1 dest_tag=p%0d rob=%0d base_tag=p%0d base_ready=%0d base_val=%h offset=%h addr_valid=%0d addr=%h executing=%0d exception=%0d",
                    i,
                    dut.lsu_inst.lq[i].dest_tag,
                    dut.lsu_inst.lq[i].rob_idx,
                    dut.lsu_inst.lq[i].base_tag,
                    dut.lsu_inst.lq[i].base_ready,
                    dut.lsu_inst.lq[i].base_val,
                    dut.lsu_inst.lq[i].offset,
                    dut.lsu_inst.lq[i].addr_valid,
                    dut.lsu_inst.lq[i].addr,
                    dut.lsu_inst.lq[i].executing,
                    dut.lsu_inst.lq[i].exception
                );
            end else begin
                $display("  LQ[%0d]: invalid", i);
            end
        end
        
        // Store Queue (SQ)
            $display("SQ (head=%0d, tail=%0d):", dut.lsu_inst.sq_head, dut.lsu_inst.sq_tail);
            for (int i = 0; i < 16; i++) begin
                if (dut.lsu_inst.sq[i].valid) begin
                $display("  SQ[%0d]: valid=1 rob=%0d base_tag=p%0d base_ready=%0d base_val=%h data_tag=p%0d data_ready=%0d data_val=%h offset=%h addr_valid=%0d addr=%h committed=%0d executing=%0d exception=%0d",
                    i,
                    dut.lsu_inst.sq[i].rob_idx,
                    dut.lsu_inst.sq[i].base_tag,
                    dut.lsu_inst.sq[i].base_ready,
                    dut.lsu_inst.sq[i].base_val,
                    dut.lsu_inst.sq[i].data_tag,
                    dut.lsu_inst.sq[i].data_ready,
                    dut.lsu_inst.sq[i].data_val,
                    dut.lsu_inst.sq[i].offset,
                    dut.lsu_inst.sq[i].addr_valid,
                    dut.lsu_inst.sq[i].addr,
                    dut.lsu_inst.sq[i].committed,
                    dut.lsu_inst.sq[i].executing,
                    dut.lsu_inst.sq[i].exception
                );
            end else begin
                $display("  SQ[%0d]: invalid", i);
            end
        end
        
        $display("load_in_flight=%0d load_in_flight_idx=%0d store_in_flight=%0d",
            dut.lsu_inst.load_in_flight,
            dut.lsu_inst.load_in_flight_idx,
            dut.lsu_inst.store_in_flight
        );
        
        $display("=========================================\n");
    end
always_ff @(posedge clk) begin
    $display("========== LSU SIGNALS ==========");
    
    // Allocation inputs
    $display("[LSU_ALLOC] en=%b is_load=%b opcode=%h", 
        dut.lsu_inst.alloc_en, 
        dut.lsu_inst.is_load, 
        dut.lsu_inst.opcode);
    
    $display("[LSU_ADDR] base_tag=p%0d base_ready=%b base_val=%h offset=%h", 
        dut.lsu_inst.base_addr_tag,
        dut.lsu_inst.base_addr_ready,
        dut.lsu_inst.base_addr_value,
        dut.lsu_inst.offset);
    
    $display("[LSU_DATA] store_tag=p%0d store_ready=%b store_val=%h",
        dut.lsu_inst.store_data_tag,
        dut.lsu_inst.store_data_ready,
        dut.lsu_inst.store_data_value);
    
    $display("[LSU_ARCH] rs1=x%0d rs2=x%0d rd=x%0d phys_rd=p%0d rob=%0d",
        dut.lsu_inst.arch_rs1,
        dut.lsu_inst.arch_rs2,
        dut.lsu_inst.arch_rd,
        dut.lsu_inst.phys_rd,
        dut.lsu_inst.rob_idx);
    
    // CDB output
    $display("[LSU_CDB] req=%b tag=p%0d value=%h exception=%b",
        dut.lsu_inst.cdb_req,
        dut.lsu_inst.cdb_req_tag,
        dut.lsu_inst.cdb_req_value,
        dut.lsu_inst.cdb_req_exception);
    
    // ROB commit inputs
    $display("[LSU_COMMIT] en=%b%b is_store=%b%b rob_idx=%0d,%0d",
        dut.lsu_inst.commit_en[1],
        dut.lsu_inst.commit_en[0],
        dut.lsu_inst.commit_is_store[1],
        dut.lsu_inst.commit_is_store[0],
        dut.lsu_inst.commit_rob_idx[0],
        dut.lsu_inst.commit_rob_idx[1]);
    
    // Memory interface
    $display("[LSU_MEM] req=%b we=%b addr=%h wdata=%h ready=%b rdata=%h error=%b",
        dut.lsu_inst.mem_req,
        dut.lsu_inst.mem_we,
        dut.lsu_inst.mem_addr,
        dut.lsu_inst.mem_wdata,
        dut.lsu_inst.mem_ready,
        dut.lsu_inst.mem_rdata,
        dut.lsu_inst.mem_error);
    
    // Exception
    $display("[LSU_EXCEPT] exception=%b cause=%h",
        dut.lsu_inst.lsu_exception,
        dut.lsu_inst.lsu_exception_cause);
    
    // Internal state
    $display("[LSU_STATE] lq_head=%0d lq_tail=%0d sq_head=%0d sq_tail=%0d load_flight=%b store_flight=%b",
        dut.lsu_inst.lq_head,
        dut.lsu_inst.lq_tail,
        dut.lsu_inst.sq_head,
        dut.lsu_inst.sq_tail,
        dut.lsu_inst.load_in_flight,
        dut.lsu_inst.store_in_flight);
    
    $display("=================================");
end*/
endmodule
