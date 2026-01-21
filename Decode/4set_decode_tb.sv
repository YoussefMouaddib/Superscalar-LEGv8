`timescale 1ns/1ps

module small_decode_tb;

    // Parameters
    localparam FETCH_W = 2;
    localparam CLK_PERIOD = 10;
    
    // Testbench signals
    logic clk;
    logic reset;
    
    // DUT inputs
    logic [FETCH_W-1:0]      instr_valid;
    logic [FETCH_W-1:0][31:0] instr;
    logic [FETCH_W-1:0][31:0] pc;
    logic                    decode_ready;
    
    // DUT outputs
    logic [FETCH_W-1:0]      dec_valid;
    logic [FETCH_W-1:0][5:0] dec_opcode;
    logic [FETCH_W-1:0][4:0] dec_rs1;
    logic [FETCH_W-1:0][4:0] dec_rs2;
    logic [FETCH_W-1:0][4:0] dec_rd;
    logic [FETCH_W-1:0][31:0] dec_imm;
    logic [FETCH_W-1:0][31:0] dec_pc;
    logic [FETCH_W-1:0]      dec_rs1_valid;
    logic [FETCH_W-1:0]      dec_rs2_valid;
    logic [FETCH_W-1:0]      dec_rd_valid;
    logic [FETCH_W-1:0]      dec_is_alu;
    logic [FETCH_W-1:0]      dec_is_load;
    logic [FETCH_W-1:0]      dec_is_store;
    logic [FETCH_W-1:0]      dec_is_branch;
    logic [FETCH_W-1:0]      dec_is_cas;
    
    // Additional outputs from decode module
    logic [FETCH_W-1:0][5:0] dec_alu_func;
    logic [FETCH_W-1:0][4:0] dec_shamt;
    
    // Instruction memory (4 sets of 2 instructions = 8 instructions)
    typedef struct {
        logic [31:0] instr[2];
        logic [31:0] pc[2];
        string description[2];
    } instruction_set_t;
    
    instruction_set_t instruction_sets[4];
    
    // Test program with CORRECT encodings that match decode module expectations
    initial begin
        // Set 0: R-type (ADD) and I-type (ADDI)
        // ADD X1, X2, X3: opcode=000000, Rd=1, Rn=2, Rm=3, SHAMT=0, FUNC=100000
        instruction_sets[0].instr[0] = {6'b000000, 5'd1, 5'd2, 5'd3, 5'd0, 6'b100000};
        instruction_sets[0].description[0] = "ADD X1, X2, X3";
        
        // ADDI X4, X5, #100: opcode=001000, Rd=4, Rn=5, imm16=100
        instruction_sets[0].instr[1] = {6'b001000, 5'd4, 5'd5, 16'd100};
        instruction_sets[0].description[1] = "ADDI X4, X5, #100";
        instruction_sets[0].pc[0] = 32'h1000;
        instruction_sets[0].pc[1] = 32'h1004;
        
        // Set 1: Load (LDR) and Store (STR) with both positive and negative offsets
        // LDR X6, [X7, #64]: opcode=010000, Rt=6, Rn=7, imm16=64
        instruction_sets[1].instr[0] = {6'b010000, 5'd6, 5'd7, 16'd64};
        instruction_sets[1].description[0] = "LDR X6, [X7, #64]";
        
        // STR X8, [X9, #-16]: opcode=010001, Rt=8, Rn=9, imm16=-16 (0xFFF0 in 16-bit 2's complement)
        instruction_sets[1].instr[1] = {6'b010001, 5'd8, 5'd9, 16'hFFF0};
        instruction_sets[1].description[1] = "STR X8, [X9, #-16]";
        instruction_sets[1].pc[0] = 32'h1008;
        instruction_sets[1].pc[1] = 32'h100C;
        
        // Set 2: Conditional branch (CBZ) and Unconditional branch (B)
        // CBZ X10, #32: opcode=100010, Rt=10, imm21=8 (8 << 2 = 32)
        instruction_sets[2].instr[0] = {6'b100010, 5'd10, 21'd8};
        instruction_sets[2].description[0] = "CBZ X10, #32";
        
        // B #-16: opcode=100000, imm26=-4 (-4 << 2 = -16)
        instruction_sets[2].instr[1] = {6'b100000, 26'h3FFFFFC};
        instruction_sets[2].description[1] = "B #-16";
        instruction_sets[2].pc[0] = 32'h1010;
        instruction_sets[2].pc[1] = 32'h1014;
        
        // Set 3: CAS (atomic) and NOP
        // CAS X11, X12, X13: opcode=010100, Rd=11, Rn=12, Rm=13, rest=0
        instruction_sets[3].instr[0] = {6'b010100, 5'd11, 5'd12, 5'd13, 5'd0, 6'b000000};
        instruction_sets[3].description[0] = "CAS X11, X12, X13";
        
        // NOP: opcode=111111, rest=0
        instruction_sets[3].instr[1] = {6'b111111, 26'd0};
        instruction_sets[3].description[1] = "NOP";
        instruction_sets[3].pc[0] = 32'h1018;
        instruction_sets[3].pc[1] = 32'h101C;
    end
    
    // Instantiate DUT
    decode #(
        .FETCH_W(FETCH_W)
    ) dut (
        .clk(clk),
        .reset(reset),
        .instr_valid(instr_valid),
        .instr(instr),
        .pc(pc),
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
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Display function for instruction - FIXED: automatic function
    function automatic string instr_to_string(logic [31:0] instr);
        logic [5:0] opcode;
        logic [5:0] func;
        
        opcode = instr[31:26];
        func = instr[5:0];
        
        case (opcode)
            // R-type
            6'b000000: begin
                case (func)
                    6'b100000: return $sformatf("ADD: rd=%0d, rn=%0d, rm=%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    6'b100010: return $sformatf("SUB: rd=%0d, rn=%0d, rm=%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    6'b100100: return $sformatf("AND: rd=%0d, rn=%0d, rm=%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    6'b100101: return $sformatf("ORR: rd=%0d, rn=%0d, rm=%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    6'b100110: return $sformatf("EOR: rd=%0d, rn=%0d, rm=%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    6'b101000: return $sformatf("NEG: rd=%0d, rn=%0d", 
                                               instr[25:21], instr[20:16]);
                    6'b000000: return $sformatf("LSL_reg: rd=%0d, rn=%0d, rm=%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    6'b000010: return $sformatf("LSR_reg: rd=%0d, rn=%0d, rm=%0d", 
                                               instr[25:21], instr[20:16], instr[15:11]);
                    6'b000001: return $sformatf("LSL_imm: rd=%0d, rn=%0d, shamt=%0d", 
                                               instr[25:21], instr[20:16], instr[10:6]);
                    6'b000011: return $sformatf("LSR_imm: rd=%0d, rn=%0d, shamt=%0d", 
                                               instr[25:21], instr[20:16], instr[10:6]);
                    6'b111000: return $sformatf("RET: rn=%0d", instr[20:16]);
                    default: return $sformatf("R-type UNKNOWN func=%6b", func);
                endcase
            end
            
            // I-type
            6'b001000: return $sformatf("ADDI: rd=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b001001: return $sformatf("SUBI: rd=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b001010: return $sformatf("ANDI: rd=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b001011: return $sformatf("ORI: rd=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b001100: return $sformatf("EORI: rd=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            
            // Load/Store
            6'b010000: return $sformatf("LDR: rt=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b010001: return $sformatf("STR: rt=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b010010: return $sformatf("LDUR: rt=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b010011: return $sformatf("STUR: rt=%0d, rn=%0d, imm16=%0d", 
                                       instr[25:21], instr[20:16], instr[15:0]);
            6'b010100: return $sformatf("CAS: rd=%0d, rn=%0d, rm=%0d", 
                                       instr[25:21], instr[20:16], instr[15:11]);
            
            // Branches
            6'b100000: return $sformatf("B: imm26=%0d", instr[25:0]);
            6'b100001: return $sformatf("BL: imm26=%0d", instr[25:0]);
            6'b100010: return $sformatf("CBZ: rt=%0d, imm21=%0d", 
                                       instr[25:21], instr[20:0]);
            6'b100011: return $sformatf("CBNZ: rt=%0d, imm21=%0d", 
                                       instr[25:21], instr[20:0]);
            
            // System
            6'b111000: return "SVC";
            6'b111111: return "NOP";
            
            default:   return $sformatf("UNKNOWN opcode=%6b", opcode);
        endcase
    endfunction
    
    // Display function for decode output - FIXED: automatic function
    function automatic void display_decode_output(int lane);
        $write("  Lane %0d: ", lane);
        if (dec_valid[lane]) begin
            $write("VALID | ");
            $write("Op=%6b | ", dec_opcode[lane]);
            $write("rs1[%0d]%s ", dec_rs1[lane], dec_rs1_valid[lane] ? "✓" : "✗");
            $write("rs2[%0d]%s ", dec_rs2[lane], dec_rs2_valid[lane] ? "✓" : "✗");
            $write("rd[%0d]%s | ", dec_rd[lane], dec_rd_valid[lane] ? "✓" : "✗");
            if (dec_imm[lane] != 0) 
                $write("imm=%h (%0d) | ", dec_imm[lane], $signed(dec_imm[lane]));
            $write("PC=%h | ", dec_pc[lane]);
            if (dec_is_alu[lane]) $write("ALU(func=%6b) ", dec_alu_func[lane]);
            if (dec_is_load[lane]) $write("LOAD ");
            if (dec_is_store[lane]) $write("STORE ");
            if (dec_is_branch[lane]) $write("BRANCH ");
            if (dec_is_cas[lane]) $write("CAS ");
            if (dec_shamt[lane] != 0) $write("shamt=%0d ", dec_shamt[lane]);
        end else begin
            $write("INVALID");
        end
        $display("");
    endfunction
    
    // Display banner
    task display_banner(string message);
        $display("\n═══════════════════════════════════════════════════════════");
        $display(" %s", message);
        $display("═══════════════════════════════════════════════════════════");
    endtask
    
    // Main test sequence
    initial begin
        int set_num;
        static int cycle_count = 0;  // FIXED: declared as static
        static int error_count = 0;  // FIXED: declared as static
        
        $display("Starting decode module testbench...");
        $display("Testing %0d sets of %0d instructions each", 4, FETCH_W);
        $display("Fully compatible with updated decode module");
        
        // Initialize
        reset = 1;
        instr_valid = '0;
        instr = '0;
        pc = '0;
        decode_ready = 0;
        
        display_banner("Cycle 0: Reset");
        $display("Reset asserted");
        @(posedge clk);
        cycle_count++;
        
        // Release reset
        reset = 0;
        decode_ready = 1;
        $display("Reset released, decode_ready=1");
        
        // Feed 4 sets of instructions
        for (set_num = 0; set_num < 4; set_num++) begin
            @(posedge clk);
            cycle_count++;
            
            // Display inputs
            display_banner($sformatf("Cycle %0d: Set %0d Input", cycle_count, set_num));
            $display("Inputs:");
            $display("  decode_ready = %b", decode_ready);
            for (int lane = 0; lane < FETCH_W; lane++) begin
                $display("  Lane %0d: instr_valid=%b, PC=%h", 
                        lane, instr_valid[lane], pc[lane]);
                $display("           Instruction: %32b", instr[lane]);
                $display("           %s", instr_to_string(instr[lane]));
                $display("           Description: %s", instruction_sets[set_num].description[lane]);
            end
            
            // Load next instruction set
            if (set_num < 3) begin
                instr_valid = 2'b11;
                for (int lane = 0; lane < FETCH_W; lane++) begin
                    instr[lane] = instruction_sets[set_num].instr[lane];
                    pc[lane] = instruction_sets[set_num].pc[lane];
                end
            end else begin
                // Last set, stop feeding instructions
                instr_valid = 2'b00;
                $display("  No more instruction sets to feed");
            end
            
            // Display outputs (at next posedge, after combinational logic)
            @(negedge clk);
            $display("\nOutputs:");
            for (int lane = 0; lane < FETCH_W; lane++) begin
                display_decode_output(lane);
            end
            
            // Quick sanity checks - FIXED: moved declarations before statements
            $display("\nSanity checks:");
            for (int lane = 0; lane < FETCH_W; lane++) begin
                logic any_class;  // FIXED: declaration before use
                
                if (dec_valid[lane]) begin
                    // Check PC passthrough
                    if (dec_pc[lane] !== pc[lane]) begin
                        $display("  ERROR Lane %0d: PC mismatch! Input=%h, Output=%h", 
                                lane, pc[lane], dec_pc[lane]);
                        error_count++;
                    end else begin
                        $display("  Lane %0d: PC passthrough OK", lane);
                    end
                    
                    // Check opcode passthrough
                    if (dec_opcode[lane] !== instr[lane][31:26]) begin
                        $display("  ERROR Lane %0d: Opcode mismatch! Input=%6b, Output=%6b", 
                                lane, instr[lane][31:26], dec_opcode[lane]);
                        error_count++;
                    end else begin
                        $display("  Lane %0d: Opcode passthrough OK", lane);
                    end
                    
                    // Check that at least one instruction class is set for non-NOP
                    any_class = dec_is_alu[lane] | dec_is_load[lane] | 
                                dec_is_store[lane] | dec_is_branch[lane] | 
                                dec_is_cas[lane];
                    if (dec_valid[lane] && !any_class && instr[lane][31:26] != 6'b111111) begin
                        $display("  WARNING Lane %0d: No instruction class set for valid non-NOP instruction", lane);
                    end
                end else begin
                    $display("  Lane %0d: Output invalid (expected if instr_valid=0 or decode_ready=0)", lane);
                end
            end
        end
        
        // Two more cycles to show final outputs
        repeat(2) begin
            @(posedge clk);
            cycle_count++;
            
            display_banner($sformatf("Cycle %0d: No more inputs", cycle_count));
            $display("Inputs:");
            $display("  decode_ready = %b", decode_ready);
            $display("  instr_valid = %b", instr_valid);
            
            @(negedge clk);
            $display("\nOutputs:");
            for (int lane = 0; lane < FETCH_W; lane++) begin
                display_decode_output(lane);
            end
        end
        
        // Test backpressure
        display_banner("Testing backpressure");
        $display("Setting decode_ready=0 for 1 cycle");
        @(posedge clk);
        decode_ready = 0;
        instr_valid = 2'b11;
        // Test different R-type: SUB X14, X15, X16
        instr[0] = {6'b000000, 5'd14, 5'd15, 5'd16, 5'd0, 6'b100010};
        // Test different I-type: SUBI X17, X18, #200
        instr[1] = {6'b001001, 5'd17, 5'd18, 16'd200};
        pc[0] = 32'h1020;
        pc[1] = 32'h1024;
        
        @(negedge clk);
        $display("\nOutputs with decode_ready=0:");
        for (int lane = 0; lane < FETCH_W; lane++) begin
            $write("  Lane %0d: ", lane);
            if (dec_valid[lane]) begin
                $display("VALID (ERROR: should be INVALID with decode_ready=0)");
                error_count++;
            end else begin
                $display("INVALID (CORRECT)");
            end
        end
        
        @(posedge clk);
        decode_ready = 1;
        @(negedge clk);
        $display("\nOutputs with decode_ready=1 again:");
        for (int lane = 0; lane < FETCH_W; lane++) begin
            display_decode_output(lane);
        end
        
        // Test immediate sign extension
        display_banner("Testing immediate sign extension");
        @(posedge clk);
        instr_valid = 2'b11;
        // Test negative immediate for I-type
        instr[0] = {6'b001000, 5'd1, 5'd2, 16'hFF80};  // ADDI X1, X2, #-128
        // Test positive immediate for store
        instr[1] = {6'b010001, 5'd3, 5'd4, 16'd255};   // STR X3, [X4, #255]
        pc[0] = 32'h1030;
        pc[1] = 32'h1034;
        
        @(negedge clk);
        $display("\nTesting sign extension:");
        $display("  Lane 0: ADDI with imm16=-128 (0xFF80)");
        $display("         Expected immediate: 0xFFFFFF80 (-128)");
        $display("         Actual immediate:   0x%h (%0d)", dec_imm[0], $signed(dec_imm[0]));
        if (dec_imm[0] !== 32'hFFFFFF80) begin
            $display("  ERROR: Sign extension incorrect!");
            error_count++;
        end
        
        $display("  Lane 1: STR with imm16=255");
        $display("         Expected immediate: 0x000000FF (255)");
        $display("         Actual immediate:   0x%h (%0d)", dec_imm[1], $signed(dec_imm[1]));
        if (dec_imm[1] !== 32'h000000FF) begin
            $display("  ERROR: Immediate incorrect!");
            error_count++;
        end
        
        // Final summary
        display_banner("Test Complete");
        $display("Total cycles: %0d", cycle_count);
        $display("Total errors: %0d", error_count);
        
        $display("\nInstruction Set Summary:");
        $display("1. Set 0: R-type (ADD X1,X2,X3) + I-type (ADDI X4,X5,#100)");
        $display("2. Set 1: Load (LDR X6,[X7,#64]) + Store (STR X8,[X9,#-16])");
        $display("3. Set 2: Conditional branch (CBZ X10,#32) + Unconditional branch (B #-16)");
        $display("4. Set 3: Atomic (CAS X11,X12,X13) + System (NOP)");
        $display("\nAdditional tests:");
        $display("- Backpressure test (decode_ready=0)");
        $display("- Immediate sign extension test");
        
        if (error_count == 0) begin
            $display("\n✅ ALL TESTS PASSED!");
        end else begin
            $display("\n❌ TEST FAILED with %0d errors!", error_count);
        end
        
        $finish(error_count);
    end
    
    // Monitor to display any warnings
    always @(posedge clk) begin
        for (int i = 0; i < FETCH_W; i++) begin
            // Check for undefined opcodes
            if (instr_valid[i] && decode_ready) begin
                case (instr[i][31:26])
                    6'b000000, 6'b001000, 6'b001001, 6'b001010, 6'b001011,
                    6'b001100, 6'b010000, 6'b010001, 6'b010010, 6'b010011,
                    6'b010100, 6'b100000, 6'b100001, 6'b100010, 6'b100011,
                    6'b111000, 6'b111111: begin
                        // Valid opcodes - do nothing
                    end
                    default: begin
                        $display("%t WARNING: Lane %0d has undefined opcode %6b", 
                                $time, i, instr[i][31:26]);
                    end
                endcase
            end
        end
    end
    
    // Waveform dump for debugging
    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("decode_tb.vcd");
            $dumpvars(0, decode_tb);
        end
    end
    
endmodule
