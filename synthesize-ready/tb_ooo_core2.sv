`timescale 1ns/1ps

module tb_ooo_core_second;

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
    
    // ============================================================
    // PROGRAM LOADING (CRITICAL FIX)
    // ============================================================
    initial begin
        // Load a simple test program into instruction memory
        // Wait for reset to complete
        @(negedge reset);
        @(posedge clk);
        
        $display("\n===============================================");
        $display("LOADING TEST PROGRAM INTO INSTRUCTION MEMORY");
        $display("===============================================\n");
        
        // Simple test program:
        // 0x00: ADDI X1, X0, 10    (X1 = 10)
        // 0x04: ADDI X2, X0, 5     (X2 = 5)
        // 0x08: ADD  X3, X1, X2    (X3 = X1 + X2 = 15)
        // 0x0C: SUB  X4, X1, X2    (X4 = X1 - X2 = 5)
        // 0x10: NOP
        // 0x14: NOP
        
        // ADDI X1, X0, 10: opcode=001000 (I-type ALU), rd=1, rs1=0, imm=10
        // Format: [31:26]=opcode [25:21]=rd [20:16]=rs1 [15:0]=imm
        dut.imem.rom_mem[0] = 32'b001000_00001_00000_0000000000001010; // ADDI X1, X0, 10
        
        // ADDI X2, X0, 5
        dut.imem.rom_mem[1] = 32'b001000_00010_00000_0000000000000101; // ADDI X2, X0, 5
        
        // ADD X3, X1, X2: opcode=000000 (R-type), rd=3, rs1=1, rs2=2, func=100000 (ADD)
        // Format: [31:26]=opcode [25:21]=rd [20:16]=rs1 [15:11]=rs2 [10:6]=shamt [5:0]=func
        dut.imem.rom_mem[2] = 32'b000000_00011_00001_00010_00000_100000; // ADD X3, X1, X2
        
        // SUB X4, X1, X2: func=100010 (SUB)
        dut.imem.rom_mem[3] = 32'b000000_00100_00001_00010_00000_100010; // SUB X4, X1, X2
        
        // NOPs (treat as ADDI X0, X0, 0)
        dut.imem.rom_mem[4] = 32'b111111_00000_00000_0000000000000000;
        dut.imem.rom_mem[5] = 32'b111111_00000_00000_0000000000000000;
        
        $display("Program loaded:");
        $display("  0x00: ADDI X1, X0, 10");
        $display("  0x04: ADDI X2, X0, 5");
        $display("  0x08: ADD  X3, X1, X2");
        $display("  0x0C: SUB  X4, X1, X2");
        $display("  0x10: NOP");
        $display("  0x14: NOP\n");
    end
    
    // ============================================================
    // RESET AND RUN
    // ============================================================
    initial begin
        $display("\n=== STARTING SIMULATION ===\n");
        reset = 1;
        #25;  // Hold reset for 2.5 cycles
        reset = 0;
        $display("\n=== RESET RELEASED AT TIME %0t ===\n", $time);
        
        #2000;  // Run for 200 cycles
        
        $display("\n=== FINAL REGISTER STATE ===");
        $display("Expected: X1=10, X2=5, X3=15, X4=5");
        $display("Actual:");
        $display("  X1 = %0d (0x%h)", dut.arf_inst.regs[1], dut.arf_inst.regs[1]);
        $display("  X2 = %0d (0x%h)", dut.arf_inst.regs[2], dut.arf_inst.regs[2]);
        $display("  X3 = %0d (0x%h)", dut.arf_inst.regs[3], dut.arf_inst.regs[3]);
        $display("  X4 = %0d (0x%h)", dut.arf_inst.regs[4], dut.arf_inst.regs[4]);
        
        $finish;
    end
    
    // ============================================================
    // DETAILED CYCLE-BY-CYCLE MONITORING
    // ============================================================
    int cycle;
    logic prev_reset;
    
    always_ff @(posedge clk) begin
        prev_reset <= reset;
        
        if (reset) begin
            cycle <= 0;
        end else begin
            cycle <= cycle + 1;
            
            // Only print first 50 cycles in detail to avoid spam
            if (cycle < 50) begin
                $display("\n╔═══════════════════════════════════════════════════════════");
                $display("║ CYCLE %0d (Time %0t)", cycle, $time);
                $display("╚═══════════════════════════════════════════════════════════");
                
                // ==================== FETCH STAGE ====================
                $display("\n[FETCH STAGE]");
                $display("  PC Requested    : 0x%h (addr0) / 0x%h (addr1)", 
                    dut.imem_addr0, dut.imem_addr1);
                $display("  IMEM Read Enable: %b", dut.imem_ren);
                $display("  IMEM Valid      : %b", dut.imem_valid);
                
                if (dut.imem_valid) begin
                    $display("  IMEM Data[0]    : 0x%h (at PC 0x%h)", 
                        dut.imem_rdata0, dut.imem_pc[0]);
                    $display("  IMEM Data[1]    : 0x%h (at PC 0x%h)", 
                        dut.imem_rdata1, dut.imem_pc[1]);
                end
                
                $display("  IF Valid        : %b%b", dut.if_valid[1], dut.if_valid[0]);
                if (dut.if_valid[0]) 
                    $display("  IF Instr[0]     : 0x%h @ PC 0x%h", dut.if_instr[0], dut.if_pc[0]);
                if (dut.if_valid[1]) 
                    $display("  IF Instr[1]     : 0x%h @ PC 0x%h", dut.if_instr[1], dut.if_pc[1]);
                
                $display("  Fetch Stall     : %b", dut.fetch_stall);
                $display("  Redirect        : %b (to 0x%h)", dut.redirect_en, dut.redirect_pc);
                $display("  Flush           : %b (to 0x%h)", dut.flush_pipeline, dut.flush_pc);
                
                // ==================== DECODE STAGE ====================
                $display("\n[DECODE STAGE]");
                $display("  Decode Ready    : %b", dut.decode_ready);
                $display("  Decode Valid    : %b%b", dut.dec_valid[1], dut.dec_valid[0]);
                
                for (int i = 0; i < 2; i++) begin
                    if (dut.dec_valid[i]) begin
                        $display("\n  Lane %0d:", i);
                        $display("    Opcode : 0x%h", dut.dec_opcode[i]);
                        $display("    RD     : x%0d (valid=%b)", dut.dec_rd[i], dut.dec_rd_valid[i]);
                        $display("    RS1    : x%0d (valid=%b)", dut.dec_rs1[i], dut.dec_rs1_valid[i]);
                        $display("    RS2    : x%0d (valid=%b)", dut.dec_rs2[i], dut.dec_rs2_valid[i]);
                        $display("    Imm    : %0d (0x%h)", $signed(dut.dec_imm[i]), dut.dec_imm[i]);
                        $display("    Type   : ALU=%b LD=%b ST=%b BR=%b CAS=%b", 
                            dut.dec_is_alu[i], dut.dec_is_load[i], dut.dec_is_store[i], 
                            dut.dec_is_branch[i], dut.dec_is_cas[i]);
                    end
                end
                
                // ==================== RENAME STAGE ====================
                $display("\n[RENAME STAGE]");
                $display("  Rename Ready    : %b", dut.rename_ready);
                $display("  Rename Valid    : %b%b", dut.rename_valid[1], dut.rename_valid[0]);
                
                for (int i = 0; i < 2; i++) begin
                    if (dut.rename_valid[i]) begin
                        $display("\n  Lane %0d:", i);
                        $display("    Arch RD  : x%0d → Physical p%0d", 
                            dut.rename_arch_rd[i], dut.rename_prd[i]);
                        $display("    Arch RS1 : x%0d → Physical p%0d", 
                            dut.rename_arch_rs1[i], dut.rename_prs1[i]);
                        $display("    Arch RS2 : x%0d → Physical p%0d", 
                            dut.rename_arch_rs2[i], dut.rename_prs2[i]);
                    end
                end
                
                // ==================== DISPATCH/ROB ====================
                $display("\n[DISPATCH/ROB]");
                $display("  Dispatch Stall  : %b", dut.dispatch_stall);
                $display("  ROB Alloc OK    : %b", dut.rob_alloc_ok);
                $display("  ROB Alloc Enable: %b%b", dut.rob_alloc_en[1], dut.rob_alloc_en[0]);
                
                if (dut.rob_alloc_ok) begin
                    for (int i = 0; i < 2; i++) begin
                        if (dut.rob_alloc_en[i]) begin
                            $display("  Lane %0d → ROB[%0d]: x%0d=p%0d @ PC=0x%h (LD=%b ST=%b BR=%b)",
                                i, dut.rob_alloc_idx[i], dut.rob_alloc_arch_rd[i], 
                                dut.rob_alloc_phys_rd[i], dut.rob_alloc_pc[i],
                                dut.rob_alloc_is_load[i], dut.rob_alloc_is_store[i],
                                dut.rob_alloc_is_branch[i]);
                        end
                    end
                end
                
                // ==================== RESERVATION STATION ====================
                $display("\n[RESERVATION STATION]");
                $display("  RS Full         : %b", dut.rs_full);
                $display("  RS Alloc Enable : %b%b", dut.rs_alloc_en[1], dut.rs_alloc_en[0]);
                
                for (int i = 0; i < 2; i++) begin
                    if (dut.rs_alloc_en[i]) begin
                        $display("  Lane %0d: DST=p%0d SRC1=p%0d(rdy=%b) SRC2=p%0d(rdy=%b) OP=0x%h ROB=%0d",
                            i, dut.rs_alloc_dst_tag[i], 
                            dut.rs_alloc_src1_tag[i], dut.rs_alloc_src1_ready[i],
                            dut.rs_alloc_src2_tag[i], dut.rs_alloc_src2_ready[i],
                            dut.rs_alloc_op[i], dut.rs_alloc_rob_tag[i]);
                    end
                end
                
                // ==================== ISSUE ====================
                $display("\n[ISSUE]");
                $display("  Issue Valid     : %b%b", dut.issue_valid[1], dut.issue_valid[0]);
                
                for (int i = 0; i < 2; i++) begin
                    if (dut.issue_valid[i]) begin
                        $display("  Lane %0d: DST=p%0d SRC1=0x%h SRC2=0x%h OP=0x%h ROB=%0d",
                            i, dut.issue_dst_tag[i], dut.issue_src1_val[i][31:0],
                            dut.issue_src2_val[i][31:0], dut.issue_op[i], 
                            dut.issue_rob_tag[i]);
                    end
                end
                
                // ==================== CDB ====================
                $display("\n[CDB BROADCAST]");
                $display("  CDB Valid       : %b%b", dut.cdb_valid[1], dut.cdb_valid[0]);
                
                for (int i = 0; i < 2; i++) begin
                    if (dut.cdb_valid[i]) begin
                        $display("  Port %0d: TAG=p%0d VALUE=0x%h (%0d) ROB=%0d",
                            i, dut.cdb_tag[i], dut.cdb_value[i], 
                            $signed(dut.cdb_value[i]), dut.cdb_rob_tag[i]);
                    end
                end
                
                // ==================== COMMIT ====================
                $display("\n[COMMIT]");
                $display("  Commit Valid    : %b%b", dut.rob_commit_valid[1], dut.rob_commit_valid[0]);
                
                for (int i = 0; i < 2; i++) begin
                    if (dut.rob_commit_valid[i]) begin
                        $display("  Lane %0d: ROB[%0d] x%0d=p%0d @ PC=0x%h",
                            i, dut.rob_commit_rob_idx[i], dut.rob_commit_arch_rd[i],
                            dut.rob_commit_phys_rd[i], dut.rob_commit_pc[i]);
                    end
                end
                
                // ==================== MEMORY ====================
                if (dut.lsu_alloc_en) begin
                    $display("\n[LSU ALLOCATION]");
                    $display("  Load=%b Addr=0x%h+%0d PRD=p%0d ROB=%0d",
                        dut.lsu_is_load, dut.lsu_base_addr, dut.lsu_offset,
                        dut.lsu_phys_rd, dut.lsu_rob_idx);
                end
                
                if (dut.mem_req) begin
                    $display("\n[MEMORY ACCESS]");
                    $display("  WE=%b Addr=0x%h WData=0x%h Ready=%b",
                        dut.mem_we, dut.mem_addr, dut.mem_wdata, dut.mem_ready);
                end
            end
        end
    end
    
    // ============================================================
    // PRF STATE SNAPSHOT (every 10 cycles)
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset && (cycle > 0) && (cycle % 10 == 0) && (cycle < 50)) begin
            $display("\n┌─────────────────────────────────────┐");
            $display("│ PHYSICAL REGISTER FILE (Cycle %2d) │", cycle);
            $display("└─────────────────────────────────────┘");
            for (int i = 0; i < 48; i += 8) begin
                $display("p%2d=%08h p%2d=%08h p%2d=%08h p%2d=%08h p%2d=%08h p%2d=%08h p%2d=%08h p%2d=%08h",
                    i,   dut.prf_inst.regs[i],
                    i+1, dut.prf_inst.regs[i+1],
                    i+2, dut.prf_inst.regs[i+2],
                    i+3, dut.prf_inst.regs[i+3],
                    i+4, dut.prf_inst.regs[i+4],
                    i+5, dut.prf_inst.regs[i+5],
                    i+6, dut.prf_inst.regs[i+6],
                    i+7, dut.prf_inst.regs[i+7]);
            end
        end
    end
    
    // ============================================================
    // ERROR DETECTION
    // ============================================================
    always_ff @(posedge clk) begin
        if (!reset && cycle > 5) begin
            // Check if fetch is stuck
            if (!dut.if_valid && !dut.fetch_stall && dut.imem_ren) begin
                $display("\n⚠️  WARNING: Fetch appears stuck - no valid instructions after cycle %0d", cycle);
            end
            
            // Check if pipeline is completely empty after 20 cycles
            if (cycle == 20) begin
                if (!dut.rob_commit_valid && dut.rob_inst.occupancy == 0) begin
                    $display("\n❌ ERROR: Pipeline completely empty at cycle 20 - likely stuck!");
                    $display("   Check: IMEM validity, decode logic, rename allocation");
                end
            end
        end
    end
    
    // Dump waveforms
    initial begin
        $dumpfile("ooo_core.vcd");
        $dumpvars(0, tb_ooo_core);
    end

endmodule
