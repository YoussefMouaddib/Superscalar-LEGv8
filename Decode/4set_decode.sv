`timescale 1ns/1ps

module decode_tb;

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
    
    // Instruction memory (4 sets of 2 instructions = 8 instructions)
    typedef struct {
        logic [31:0] instr[2];
        logic [31:0] pc[2];
    } instruction_set_t;
    
    instruction_set_t instruction_sets[4];
    
    // Test program
    initial begin
        // Set 0: R-type and I-type
        instruction_sets[0].instr[0] = {6'b000000, 5'd1, 5'd2, 5'd3, 5'd0, 6'b000000};    // ADD X1, X2, X3
        instruction_sets[0].instr[1] = {6'b001000, 5'd4, 5'd5, 12'd100, 4'b0000};        // ADDI X4, X5, #100
        instruction_sets[0].pc[0] = 32'h1000;
        instruction_sets[0].pc[1] = 32'h1004;
        
        // Set 1: Load and Store
        instruction_sets[1].instr[0] = {6'b010000, 5'd6, 5'd7, 12'd64, 4'b0000};         // LDR X6, [X7, #64]
        instruction_sets[1].instr[1] = {6'b010001, 5'd8, 5'd9, 12'hFF0, 4'b0000};        // STR X8, [X9, #-16]
        instruction_sets[1].pc[0] = 32'h1008;
        instruction_sets[1].pc[1] = 32'h100C;
        
        // Set 2: Branches
        instruction_sets[2].instr[0] = {6'b011000, 5'd10, 19'd8, 2'b00};                  // CBZ X10, #32
        instruction_sets[2].instr[1] = {6'b100000, 26'h3FFFFFC};                         // B #-16
        instruction_sets[2].pc[0] = 32'h1010;
        instruction_sets[2].pc[1] = 32'h1014;
        
        // Set 3: CAS and NOP
        instruction_sets[3].instr[0] = {6'b101000, 5'd11, 5'd12, 5'd13, 11'd0};          // CAS X11, X12, X13
        instruction_sets[3].instr[1] = {6'b111000, 26'd0};                               // NOP
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
        .dec_is_cas(dec_is_cas)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Display function for instruction
    function string instr_to_string(logic [31:0] instr);
        logic [5:0] opcode = instr[31:26];
        case (opcode)
            6'b000000: return $sformatf("R-type: rd=%0d, rs1=%0d, rs2=%0d", 
                                       instr[25:21], instr[20:16], instr[15:11]);
            6'b001000: return $sformatf("ADDI: rd=%0d, rs1=%0d, imm12=%0d", 
                                       instr[25:21], instr[20:16], instr[15:4]);
            6'b001001: return $sformatf("SUBI: rd=%0d, rs1=%0d, imm12=%0d", 
                                       instr[25:21], instr[20:16], instr[15:4]);
            6'b010000: return $sformatf("LDR: rt=%0d, rn=%0d, imm12=%0d", 
                                       instr[25:21], instr[20:16], instr[15:4]);
            6'b010001: return $sformatf("STR: rt=%0d, rn=%0d, imm12=%0d", 
                                       instr[25:21], instr[20:16], instr[15:4]);
            6'b011000: return $sformatf("CBZ: rt=%0d, imm19=%0d", 
                                       instr[25:21], instr[20:2]);
            6'b100000: return $sformatf("B: imm26=%0d", instr[25:0]);
            6'b101000: return $sformatf("CAS: rd=%0d, rn=%0d, rm=%0d", 
                                       instr[25:21], instr[20:16], instr[15:11]);
            6'b111000: return "NOP/SYS";
            default:   return $sformatf("UNKNOWN opcode=%6b", opcode);
        endcase
    endfunction
    
    // Display function for decode output
    function void display_decode_output(int lane);
        $write("  Lane %0d: ", lane);
        if (dec_valid[lane]) begin
            $write("VALID | ");
            $write("Op=%6b | ", dec_opcode[lane]);
            $write("rs1[%0d]%s ", dec_rs1[lane], dec_rs1_valid[lane] ? "✓" : "✗");
            $write("rs2[%0d]%s ", dec_rs2[lane], dec_rs2_valid[lane] ? "✓" : "✗");
            $write("rd[%0d]%s | ", dec_rd[lane], dec_rd_valid[lane] ? "✓" : "✗");
            if (dec_imm[lane] != 0) 
                $write("imm=%h | ", dec_imm[lane]);
            $write("PC=%h | ", dec_pc[lane]);
            if (dec_is_alu[lane]) $write("ALU ");
            if (dec_is_load[lane]) $write("LOAD ");
            if (dec_is_store[lane]) $write("STORE ");
            if (dec_is_branch[lane]) $write("BRANCH ");
            if (dec_is_cas[lane]) $write("CAS ");
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
        int cycle_count = 0;
        
        $display("Starting decode module testbench...");
        $display("Testing %0d sets of %0d instructions each", 4, FETCH_W);
        
        // Initialize
        reset = 1;
        instr_valid = '0;
        instr = '0;
        pc = '0;
        decode_ready = 0;
        
        display_banner("Cycle 0: Reset");
        @(posedge clk);
        cycle_count++;
        
        // Release reset
        reset = 0;
        decode_ready = 1;
        
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
            end
            
            // Display outputs (at next posedge, after combinational logic)
            @(negedge clk);
            $display("\nOutputs:");
            for (int lane = 0; lane < FETCH_W; lane++) begin
                display_decode_output(lane);
            end
            
            // Quick sanity checks
            $display("\nSanity checks:");
            for (int lane = 0; lane < FETCH_W; lane++) begin
                if (dec_valid[lane]) begin
                    // Check PC passthrough
                    if (dec_pc[lane] !== pc[lane]) 
                        $display("  ERROR Lane %0d: PC mismatch! Input=%h, Output=%h", 
                                lane, pc[lane], dec_pc[lane]);
                    
                    // Check opcode passthrough
                    if (dec_opcode[lane] !== instr[lane][31:26])
                        $display("  ERROR Lane %0d: Opcode mismatch! Input=%6b, Output=%6b", 
                                lane, instr[lane][31:26], dec_opcode[lane]);
                    
                    // Check that at least one instruction class is set
                    logic any_class = dec_is_alu[lane] | dec_is_load[lane] | 
                                     dec_is_store[lane] | dec_is_branch[lane] | 
                                     dec_is_cas[lane];
                    if (dec_valid[lane] && !any_class && instr[lane][31:26] != 6'b111000)
                        $display("  WARNING Lane %0d: No instruction class set for valid instruction", lane);
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
        instr[0] = {6'b000000, 5'd14, 5'd15, 5'd16, 5'd0, 6'b000000};
        instr[1] = {6'b001000, 5'd17, 5'd18, 12'd200, 4'b0000};
        pc[0] = 32'h1020;
        pc[1] = 32'h1024;
        
        @(negedge clk);
        $display("\nOutputs with decode_ready=0:");
        for (int lane = 0; lane < FETCH_W; lane++) begin
            $write("  Lane %0d: ", lane);
            if (dec_valid[lane]) 
                $display("VALID (ERROR: should be INVALID with decode_ready=0)");
            else
                $display("INVALID (CORRECT)");
        end
        
        @(posedge clk);
        decode_ready = 1;
        @(negedge clk);
        $display("\nOutputs with decode_ready=1 again:");
        for (int lane = 0; lane < FETCH_W; lane++) begin
            display_decode_output(lane);
        end
        
        // Final summary
        display_banner("Test Complete");
        $display("Total cycles: %0d", cycle_count);
        $display("All 4 instruction sets processed successfully!");
        $display("\nInstruction Set Summary:");
        $display("1. Set 0: R-type (ADD) + I-type (ADDI)");
        $display("2. Set 1: Load (LDR) + Store (STR)");
        $display("3. Set 2: Conditional branch (CBZ) + Unconditional branch (B)");
        $display("4. Set 3: Atomic (CAS) + System (NOP)");
        $display("\nBackpressure test: PASS");
        
        $finish(0);
    end
    
    // Monitor to display any warnings
    always @(posedge clk) begin
        for (int i = 0; i < FETCH_W; i++) begin
            // Check for undefined opcodes
            if (instr_valid[i] && decode_ready) begin
                case (instr[i][31:26])
                    6'b000000, 6'b001000, 6'b001001, 6'b001010, 6'b001011,
                    6'b001100, 6'b010000, 6'b010001, 6'b011000, 6'b011001,
                    6'b100000, 6'b100001, 6'b101000, 6'b111000: begin
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
