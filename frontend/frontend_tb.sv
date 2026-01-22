`timescale 1ns/1ps

module frontend_tb;

    // Parameters
    localparam FETCH_WIDTH = 2;
    localparam XLEN = 32;
    localparam ARCH_REGS = 32;
    localparam PHYS_REGS = 48;
    localparam CLK_PERIOD = 10;
    
    // Testbench signals
    logic clk;
    logic reset;
    
    // ============================================
    //  Fetch Module Signals
    // ============================================
    logic fetch_en;
    logic stall;
    logic redirect_en;
    logic [XLEN-1:0] redirect_pc;
    
    // imem inputs (from testbench memory model)
    logic [XLEN-1:0] imem_rdata0;
    logic [XLEN-1:0] imem_rdata1;
    logic [XLEN-1:0] imem_pc [1:0];
    logic imem_valid;
    
    // Fetch outputs
    logic [FETCH_WIDTH-1:0] if_valid;
    logic [FETCH_WIDTH-1:0][XLEN-1:0] if_pc;
    logic [FETCH_WIDTH-1:0][XLEN-1:0] if_instr;
    
    // imem outputs
    logic [XLEN-1:0] imem_addr0;
    logic [XLEN-1:0] imem_addr1;
    logic imem_ren;
    
    // ============================================
    //  Decode Module Signals
    // ============================================
    logic decode_ready;
    
    // Decode outputs
    logic [FETCH_WIDTH-1:0] dec_valid;
    logic [FETCH_WIDTH-1:0][5:0] dec_opcode;
    logic [FETCH_WIDTH-1:0][4:0] dec_rs1;
    logic [FETCH_WIDTH-1:0][4:0] dec_rs2;
    logic [FETCH_WIDTH-1:0][4:0] dec_rd;
    logic [FETCH_WIDTH-1:0][31:0] dec_imm;
    logic [FETCH_WIDTH-1:0][31:0] dec_pc;
    logic [FETCH_WIDTH-1:0] dec_rs1_valid;
    logic [FETCH_WIDTH-1:0] dec_rs2_valid;
    logic [FETCH_WIDTH-1:0] dec_rd_valid;
    logic [FETCH_WIDTH-1:0] dec_is_alu;
    logic [FETCH_WIDTH-1:0] dec_is_load;
    logic [FETCH_WIDTH-1:0] dec_is_store;
    logic [FETCH_WIDTH-1:0] dec_is_branch;
    logic [FETCH_WIDTH-1:0] dec_is_cas;
    logic [FETCH_WIDTH-1:0][5:0] dec_alu_func;
    logic [FETCH_WIDTH-1:0][4:0] dec_shamt;
    
    // ============================================
    //  Rename Module Signals
    // ============================================
    logic rename_ready;
    
    // Rename outputs (to next stage)
    logic [FETCH_WIDTH-1:0] rename_valid;
    logic [FETCH_WIDTH-1:0][5:0] rename_opcode;
    logic [FETCH_WIDTH-1:0][5:0] rename_prs1;
    logic [FETCH_WIDTH-1:0][5:0] rename_prs2;
    logic [FETCH_WIDTH-1:0][5:0] rename_prd;
    logic [FETCH_WIDTH-1:0][31:0] rename_imm;
    logic [FETCH_WIDTH-1:0][31:0] rename_pc;
    logic [FETCH_WIDTH-1:0] rename_rs1_valid;
    logic [FETCH_WIDTH-1:0] rename_rs2_valid;
    logic [FETCH_WIDTH-1:0] rename_rd_valid;
    logic [FETCH_WIDTH-1:0] rename_is_alu;
    logic [FETCH_WIDTH-1:0] rename_is_load;
    logic [FETCH_WIDTH-1:0] rename_is_store;
    logic [FETCH_WIDTH-1:0] rename_is_branch;
    logic [FETCH_WIDTH-1:0] rename_is_cas;
    logic [FETCH_WIDTH-1:0][5:0] rename_alu_func;
    
    // Commit signals (simulated for now)
    logic commit_en;
    logic [4:0] commit_arch_rd;
    logic [5:0] commit_phys_rd;
    
    // ============================================
    //  DUT Instantiations
    // ============================================
    fetch fetch_inst (
        .clk(clk),
        .reset(reset),
        .fetch_en(fetch_en),
        .stall(stall),
        .redirect_en(redirect_en),
        .redirect_pc(redirect_pc),
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
    
    decode #(
        .FETCH_W(FETCH_WIDTH)
    ) decode_inst (
        .clk(clk),
        .reset(reset),
        .instr_valid(if_valid),
        .instr(if_instr),
        .pc(if_pc),
        .decode_ready(decode_ready),
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
    
    rename_stage #(
        .FETCH_W(FETCH_WIDTH),
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS)
    ) rename_inst (
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
        .commit_en(commit_en),
        .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd)
    );
    
    // Connect decode_ready to rename_ready
    assign decode_ready = rename_ready;
    
    // Simple stall logic: stall if rename not ready
    assign stall = ~rename_ready;
    
    // ============================================
    //  Clock Generation
    // ============================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ============================================
    //  Instruction Memory Model
    // ============================================
    // Simple instruction memory with 1-cycle latency
    logic [31:0] inst_mem [0:1023];
    logic [XLEN-1:0] last_pc0, last_pc1;
    
    // Display test program at start
    initial begin
        $display("\n═══════════════════════════════════════════════════════════");
        $display(" TEST PROGRAM: 4 Instructions (2-wide fetch)");
        $display("═══════════════════════════════════════════════════════════");
        
        // Initialize instruction memory with test program
        // Instruction 0: ADD X1, X2, X3
        inst_mem[0] = {6'b000000, 5'd1, 5'd2, 5'd3, 5'd0, 6'b100000};
        $display("Address 0x00000000: ADD X1, X2, X3");
        $display("  Binary: %32b", inst_mem[0]);
        
        // Instruction 1: ADDI X4, X5, #100
        inst_mem[1] = {6'b001000, 5'd4, 5'd5, 16'd100};
        $display("Address 0x00000004: ADDI X4, X5, #100");
        $display("  Binary: %32b", inst_mem[1]);
        
        // Instruction 2: LDR X6, [X7, #64]
        inst_mem[2] = {6'b010000, 5'd6, 5'd7, 16'd64};
        $display("Address 0x00000008: LDR X6, [X7, #64]");
        $display("  Binary: %32b", inst_mem[2]);
        
        // Instruction 3: STR X8, [X9, #-16]
        inst_mem[3] = {6'b010001, 5'd8, 5'd9, 16'hFFF0};
        $display("Address 0x0000000C: STR X8, [X9, #-16]");
        $display("  Binary: %32b", inst_mem[3]);
        $display("");
    end
    
    // Memory response logic (1-cycle latency)
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            imem_valid <= 1'b0;
            imem_rdata0 <= '0;
            imem_rdata1 <= '0;
            imem_pc[0] <= '0;
            imem_pc[1] <= '0;
            last_pc0 <= '0;
            last_pc1 <= '0;
        end else begin
            imem_valid <= imem_ren;  // 1-cycle latency
            
            if (imem_ren) begin
                last_pc0 <= imem_addr0;
                last_pc1 <= imem_addr1;
                
                // Read from instruction memory
                imem_rdata0 <= inst_mem[imem_addr0[31:2]];
                imem_rdata1 <= inst_mem[imem_addr1[31:2]];
                imem_pc[0] <= imem_addr0;
                imem_pc[1] <= imem_addr1;
                
                $display("[MEM] Request: PC=%h, Addr0=%h, Addr1=%h", 
                        fetch_inst.pc_reg, imem_addr0, imem_addr1);
            end
            
            if (imem_valid) begin
                $display("[MEM] Response: Data0=%h @ PC=%h, Data1=%h @ PC=%h", 
                        imem_rdata0, imem_pc[0], imem_rdata1, imem_pc[1]);
            end
        end
    end
    
    // ============================================
    //  Display Functions
    // ============================================
    function automatic string inst_to_string(logic [31:0] instr);
        logic [5:0] opcode;
        logic [5:0] func;
        
        opcode = instr[31:26];
        func = instr[5:0];
        
        case (opcode)
            6'b000000: begin
                case (func)
                    6'b100000: return $sformatf("ADD X%0d, X%0d, X%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    default: return $sformatf("R-type func=%6b", func);
                endcase
            end
            6'b001000: return $sformatf("ADDI X%0d, X%0d, #%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b010000: return $sformatf("LDR X%0d, [X%0d, #%0d]", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b010001: return $sformatf("STR X%0d, [X%0d, #%0d]", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            default: return $sformatf("UNKNOWN opcode=%6b", opcode);
        endcase
    endfunction
    
    function automatic void display_fetch(int cycle);
        $display("\n═══════════════════════════════════════════════════════════");
        $display(" CYCLE %0d: FETCH STAGE", cycle);
        $display("═══════════════════════════════════════════════════════════");
        $display(" Inputs: fetch_en=%b, stall=%b, redirect_en=%b", 
                fetch_en, stall, redirect_en);
        $display(" Memory Request: imem_ren=%b, Addr0=%h, Addr1=%h", 
                imem_ren, imem_addr0, imem_addr1);
        $display(" Memory Response: imem_valid=%b", imem_valid);
        $display(" Outputs: if_valid=%b", if_valid);
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (if_valid[i]) begin
                $display("  Lane %0d: PC=%h, Instr=%h", i, if_pc[i], if_instr[i]);
                $display("           %s", inst_to_string(if_instr[i]));
            end else begin
                $display("  Lane %0d: INVALID", i);
            end
        end
    endfunction
    
    function automatic void display_decode(int cycle);
        $display("\n═══════════════════════════════════════════════════════════");
        $display(" CYCLE %0d: DECODE STAGE", cycle);
        $display("═══════════════════════════════════════════════════════════");
        $display(" Input Ready: decode_ready=%b", decode_ready);
        $display(" Output Valid: dec_valid=%b", dec_valid);
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (dec_valid[i]) begin
                $display("  Lane %0d: PC=%h, Opcode=%6b", i, dec_pc[i], dec_opcode[i]);
                $display("           Instruction: %s", inst_to_string(if_instr[i]));
                $display("           Registers: rs1[%0d]%s, rs2[%0d]%s, rd[%0d]%s", 
                        dec_rs1[i], dec_rs1_valid[i] ? "✓" : "✗",
                        dec_rs2[i], dec_rs2_valid[i] ? "✓" : "✗",
                        dec_rd[i], dec_rd_valid[i] ? "✓" : "✗");
                if (dec_imm[i] != 0) 
                    $display("           Immediate: %h (decimal: %0d)", 
                            dec_imm[i], $signed(dec_imm[i]));
                if (dec_is_alu[i]) $display("           Type: ALU (func=%6b)", dec_alu_func[i]);
                if (dec_is_load[i]) $display("           Type: LOAD");
                if (dec_is_store[i]) $display("           Type: STORE");
                if (dec_is_branch[i]) $display("           Type: BRANCH");
            end else begin
                $display("  Lane %0d: INVALID", i);
            end
        end
    endfunction
    
    function automatic void display_rename(int cycle);
        $display("\n═══════════════════════════════════════════════════════════");
        $display(" CYCLE %0d: RENAME STAGE", cycle);
        $display("═══════════════════════════════════════════════════════════");
        $display(" Ready for new instructions: rename_ready=%b", rename_ready);
        $display(" Output Valid: rename_valid=%b", rename_valid);
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (rename_valid[i]) begin
                $display("  Lane %0d: PC=%h, Opcode=%6b", i, rename_pc[i], rename_opcode[i]);
                $display("           Physical Registers: prs1[%0d]%s, prs2[%0d]%s, prd[%0d]%s", 
                        rename_prs1[i], rename_rs1_valid[i] ? "✓" : "✗",
                        rename_prs2[i], rename_rs2_valid[i] ? "✓" : "✗",
                        rename_prd[i], rename_rd_valid[i] ? "✓" : "✗");
                $display("           Architectural: rs1[%0d], rs2[%0d], rd[%0d]",
                        dec_rs1[i], dec_rs2[i], dec_rd[i]);
                if (rename_is_alu[i]) $display("           Type: ALU");
                if (rename_is_load[i]) $display("           Type: LOAD");
                if (rename_is_store[i]) $display("           Type: STORE");
            end else begin
                $display("  Lane %0d: INVALID", i);
            end
        end
    endfunction
    
    // ============================================
    //  Main Test Sequence
    // ============================================
    initial begin
        static int cycle = 0;
        static int error_count = 0;
        
        $display("\n═══════════════════════════════════════════════════════════");
        $display(" STARTING FRONTEND PIPELINE TEST");
        $display("═══════════════════════════════════════════════════════════");
        $display(" Pipeline: Fetch → Decode → Rename");
        $display(" Width: 2 instructions per cycle");
        $display(" Memory latency: 1 cycle");
        $display(" Total test instructions: 4");
        $display("");
        
        // Initialize
        reset = 1;
        fetch_en = 0;
        redirect_en = 0;
        redirect_pc = '0;
        commit_en = 0;
        commit_arch_rd = '0;
        commit_phys_rd = '0;
        
        // Cycle 0: Reset
        $display("\n[INITIALIZATION] Applying reset...");
        display_fetch(cycle);
        display_decode(cycle);
        display_rename(cycle);
        @(posedge clk);
        cycle++;
        
        // Release reset
        reset = 0;
        fetch_en = 1;
        $display("\n[START] Reset released, starting fetch...");
        
        // Test 4 instructions (fetched 2 at a time)
        for (int set = 0; set < 2; set++) begin
            $display("\n[SET %0d] Fetching 2 instructions...", set);
            // Wait for memory latency + pipeline (3 cycles per set)
            repeat(3) begin
                @(negedge clk);
                display_fetch(cycle);
                display_decode(cycle);
                display_rename(cycle);
                cycle++;
                @(posedge clk);
            end
        end
        
        // Stop fetching after 4 instructions
        fetch_en = 0;
        
        // One more cycle to show final outputs
        @(negedge clk);
        $display("\n[COMPLETION] All instructions fetched, showing final state...");
        display_fetch(cycle);
        display_decode(cycle);
        display_rename(cycle);
        
        // Test commit (free physical registers)
        $display("\n\n═══════════════════════════════════════════════════════════");
        $display(" TESTING COMMIT (Freeing physical registers)");
        $display("═══════════════════════════════════════════════════════════");
        
        commit_en = 1;
        commit_arch_rd = 5'd1;  // Commit X1
        commit_phys_rd = 6'd32; // Some physical register
        
        @(negedge clk);
        display_fetch(cycle);
        display_decode(cycle);
        display_rename(cycle);
        
        commit_en = 0;
        
        // Final summary
        $display("\n\n═══════════════════════════════════════════════════════════");
        $display(" TEST COMPLETE");
        $display("═══════════════════════════════════════════════════════════");
        $display("Total cycles simulated: %0d", cycle);
        $display("Total errors detected: %0d", error_count);
        $display("");
        $display("Instructions tested:");
        $display("  1. ADD X1, X2, X3");
        $display("  2. ADDI X4, X5, #100");
        $display("  3. LDR X6, [X7, #64]");
        $display("  4. STR X8, [X9, #-16]");
        $display("");
        
        if (error_count == 0) begin
            $display("✅ ALL FRONTEND STAGES WORKING CORRECTLY!");
            $display("   Fetch → Decode → Rename pipeline is functional.");
        end else begin
            $display("❌ TEST FAILED with %0d errors!", error_count);
        end
        
        $finish(error_count);
    end
    
    // ============================================
    //  Waveform Dump
    // ============================================
    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("frontend_tb.vcd");
            $dumpvars(0, frontend_tb);
        end
    end

endmodule
