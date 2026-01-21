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
    
    // Expected values for checking
    typedef struct {
        logic [5:0] opcode;
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic [31:0] imm;
        logic rs1_valid;
        logic rs2_valid;
        logic rd_valid;
        logic is_alu;
        logic is_load;
        logic is_store;
        logic is_branch;
        logic is_cas;
    } expected_t;
    
    expected_t expected[FETCH_W];
    
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
    
    // Test tasks
    task automatic reset_test();
        reset = 1;
        instr_valid = '0;
        instr = '0;
        pc = '0;
        decode_ready = 0;
        repeat(2) @(posedge clk);
        reset = 0;
        @(posedge clk);
    endtask
    
    // Check results against expected
    task automatic check_results(int lane);
        string lane_str = $sformatf("Lane %0d", lane);
        
        if (!dec_valid[lane]) begin
            $display("%t: %s: dec_valid=0 (expected 1)", $time, lane_str);
            $finish(1);
        end
        
        if (dec_opcode[lane] !== expected[lane].opcode) begin
            $display("%t: %s: dec_opcode=%6b (expected %6b)", 
                     $time, lane_str, dec_opcode[lane], expected[lane].opcode);
            $finish(1);
        end
        
        if (dec_rs1[lane] !== expected[lane].rs1) begin
            $display("%t: %s: dec_rs1=%5b (expected %5b)", 
                     $time, lane_str, dec_rs1[lane], expected[lane].rs1);
            $finish(1);
        end
        
        if (dec_rs2[lane] !== expected[lane].rs2) begin
            $display("%t: %s: dec_rs2=%5b (expected %5b)", 
                     $time, lane_str, dec_rs2[lane], expected[lane].rs2);
            $finish(1);
        end
        
        if (dec_rd[lane] !== expected[lane].rd) begin
            $display("%t: %s: dec_rd=%5b (expected %5b)", 
                     $time, lane_str, dec_rd[lane], expected[lane].rd);
            $finish(1);
        end
        
        if (dec_imm[lane] !== expected[lane].imm) begin
            $display("%t: %s: dec_imm=%h (expected %h)", 
                     $time, lane_str, dec_imm[lane], expected[lane].imm);
            $finish(1);
        end
        
        if (dec_rs1_valid[lane] !== expected[lane].rs1_valid) begin
            $display("%t: %s: dec_rs1_valid=%b (expected %b)", 
                     $time, lane_str, dec_rs1_valid[lane], expected[lane].rs1_valid);
            $finish(1);
        end
        
        if (dec_rs2_valid[lane] !== expected[lane].rs2_valid) begin
            $display("%t: %s: dec_rs2_valid=%b (expected %b)", 
                     $time, lane_str, dec_rs2_valid[lane], expected[lane].rs2_valid);
            $finish(1);
        end
        
        if (dec_rd_valid[lane] !== expected[lane].rd_valid) begin
            $display("%t: %s: dec_rd_valid=%b (expected %b)", 
                     $time, lane_str, dec_rd_valid[lane], expected[lane].rd_valid);
            $finish(1);
        end
        
        if (dec_is_alu[lane] !== expected[lane].is_alu) begin
            $display("%t: %s: dec_is_alu=%b (expected %b)", 
                     $time, lane_str, dec_is_alu[lane], expected[lane].is_alu);
            $finish(1);
        end
        
        if (dec_is_load[lane] !== expected[lane].is_load) begin
            $display("%t: %s: dec_is_load=%b (expected %b)", 
                     $time, lane_str, dec_is_load[lane], expected[lane].is_load);
            $finish(1);
        end
        
        if (dec_is_store[lane] !== expected[lane].is_store) begin
            $display("%t: %s: dec_is_store=%b (expected %b)", 
                     $time, lane_str, dec_is_store[lane], expected[lane].is_store);
            $finish(1);
        end
        
        if (dec_is_branch[lane] !== expected[lane].is_branch) begin
            $display("%t: %s: dec_is_branch=%b (expected %b)", 
                     $time, lane_str, dec_is_branch[lane], expected[lane].is_branch);
            $finish(1);
        end
        
        if (dec_is_cas[lane] !== expected[lane].is_cas) begin
            $display("%t: %s: dec_is_cas=%b (expected %b)", 
                     $time, lane_str, dec_is_cas[lane], expected[lane].is_cas);
            $finish(1);
        end
        
        $display("%t: %s: PASS", $time, lane_str);
    endtask
    
    // Test 1: R-type instructions
    task test_rtype();
        $display("\n=== Test 1: R-type Instructions ===");
        
        // Lane 0: ADD X1, X2, X3
        instr[0] = {6'b000000, 5'd1, 5'd2, 5'd3, 5'd0, 6'b000000};
        instr_valid[0] = 1'b1;
        pc[0] = 32'h1000;
        
        expected[0].opcode = 6'b000000;
        expected[0].rd = 5'd1;
        expected[0].rs1 = 5'd2;
        expected[0].rs2 = 5'd3;
        expected[0].imm = 32'd0;
        expected[0].rs1_valid = 1'b1;
        expected[0].rs2_valid = 1'b1;
        expected[0].rd_valid = 1'b1;
        expected[0].is_alu = 1'b1;
        expected[0].is_load = 1'b0;
        expected[0].is_store = 1'b0;
        expected[0].is_branch = 1'b0;
        expected[0].is_cas = 1'b0;
        
        // Lane 1: AND X10, X20, X30
        instr[1] = {6'b000000, 5'd10, 5'd20, 5'd30, 5'd0, 6'b000000};
        instr_valid[1] = 1'b1;
        pc[1] = 32'h1004;
        
        expected[1].opcode = 6'b000000;
        expected[1].rd = 5'd10;
        expected[1].rs1 = 5'd20;
        expected[1].rs2 = 5'd30;
        expected[1].imm = 32'd0;
        expected[1].rs1_valid = 1'b1;
        expected[1].rs2_valid = 1'b1;
        expected[1].rd_valid = 1'b1;
        expected[1].is_alu = 1'b1;
        expected[1].is_load = 1'b0;
        expected[1].is_store = 1'b0;
        expected[1].is_branch = 1'b0;
        expected[1].is_cas = 1'b0;
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        check_results(0);
        check_results(1);
    endtask
    
    // Test 2: I-type instructions
    task test_itype();
        $display("\n=== Test 2: I-type Instructions ===");
        
        // Lane 0: ADDI X5, X6, #42
        instr[0] = {6'b001000, 5'd5, 5'd6, 12'd42};
        instr_valid[0] = 1'b1;
        pc[0] = 32'h2000;
        
        expected[0].opcode = 6'b001000;
        expected[0].rd = 5'd5;
        expected[0].rs1 = 5'd6;
        expected[0].rs2 = 5'd0;
        expected[0].imm = 32'd42;  // Positive immediate
        expected[0].rs1_valid = 1'b1;
        expected[0].rs2_valid = 1'b0;
        expected[0].rd_valid = 1'b1;
        expected[0].is_alu = 1'b1;
        expected[0].is_load = 1'b0;
        expected[0].is_store = 1'b0;
        expected[0].is_branch = 1'b0;
        expected[0].is_cas = 1'b0;
        
        // Lane 1: SUBI X7, X8, #-100 (negative immediate)
        instr[1] = {6'b001001, 5'd7, 5'd8, 12'hF9C};  // -100 in 12-bit signed
        instr_valid[1] = 1'b1;
        pc[1] = 32'h2004;
        
        expected[1].opcode = 6'b001001;
        expected[1].rd = 5'd7;
        expected[1].rs1 = 5'd8;
        expected[1].rs2 = 5'd0;
        expected[1].imm = -32'd100;  // Negative immediate sign-extended
        expected[1].rs1_valid = 1'b1;
        expected[1].rs2_valid = 1'b0;
        expected[1].rd_valid = 1'b1;
        expected[1].is_alu = 1'b1;
        expected[1].is_load = 1'b0;
        expected[1].is_store = 1'b0;
        expected[1].is_branch = 1'b0;
        expected[1].is_cas = 1'b0;
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        check_results(0);
        check_results(1);
    endtask
    
    // Test 3: Load/Store instructions
    task test_memtype();
        $display("\n=== Test 3: Load/Store Instructions ===");
        
        // Lane 0: LDR X9, [X10, #128]
        instr[0] = {6'b010000, 5'd9, 5'd10, 9'd128, 2'b00, 11'd0};
        instr_valid[0] = 1'b1;
        pc[0] = 32'h3000;
        
        expected[0].opcode = 6'b010000;
        expected[0].rd = 5'd9;
        expected[0].rs1 = 5'd10;
        expected[0].rs2 = 5'd0;
        expected[0].imm = 32'd128;  // Load immediate
        expected[0].rs1_valid = 1'b1;
        expected[0].rs2_valid = 1'b0;
        expected[0].rd_valid = 1'b1;
        expected[0].is_alu = 1'b0;
        expected[0].is_load = 1'b1;
        expected[0].is_store = 1'b0;
        expected[0].is_branch = 1'b0;
        expected[0].is_cas = 1'b0;
        
        // Lane 1: STR X11, [X12, #-256]
        instr[1] = {6'b010001, 5'd11, 5'd12, 9'h100, 2'b00, 11'd0};  // -256
        instr_valid[1] = 1'b1;
        pc[1] = 32'h3004;
        
        expected[1].opcode = 6'b010001;
        expected[1].rd = 5'd0;
        expected[1].rs1 = 5'd12;  // Base
        expected[1].rs2 = 5'd11;  // Store data register
        expected[1].imm = -32'd256;  // Negative offset
        expected[1].rs1_valid = 1'b1;
        expected[1].rs2_valid = 1'b1;
        expected[1].rd_valid = 1'b0;
        expected[1].is_alu = 1'b0;
        expected[1].is_load = 1'b0;
        expected[1].is_store = 1'b1;
        expected[1].is_branch = 1'b0;
        expected[1].is_cas = 1'b0;
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        check_results(0);
        check_results(1);
    endtask
    
    // Test 4: Branch instructions
    task test_branches();
        $display("\n=== Test 4: Branch Instructions ===");
        
        // Lane 0: CBZ X1, #16
        instr[0] = {6'b011000, 5'd1, 19'd4, 2'b00};  // 4 << 2 = 16
        instr_valid[0] = 1'b1;
        pc[0] = 32'h4000;
        
        expected[0].opcode = 6'b011000;
        expected[0].rd = 5'd0;
        expected[0].rs1 = 5'd1;
        expected[0].rs2 = 5'd0;
        expected[0].imm = 32'd16;  // Shifted left by 2
        expected[0].rs1_valid = 1'b1;
        expected[0].rs2_valid = 1'b0;
        expected[0].rd_valid = 1'b0;
        expected[0].is_alu = 1'b0;
        expected[0].is_load = 1'b0;
        expected[0].is_store = 1'b0;
        expected[0].is_branch = 1'b1;
        expected[0].is_cas = 1'b0;
        
        // Lane 1: B #-8
        instr[1] = {6'b100000, 26'h3FFFFFE};  // -2 << 2 = -8
        instr_valid[1] = 1'b1;
        pc[1] = 32'h4004;
        
        expected[1].opcode = 6'b100000;
        expected[1].rd = 5'd0;
        expected[1].rs1 = 5'd0;
        expected[1].rs2 = 5'd0;
        expected[1].imm = -32'd8;  // Negative branch offset
        expected[1].rs1_valid = 1'b0;
        expected[1].rs2_valid = 1'b0;
        expected[1].rd_valid = 1'b0;
        expected[1].is_alu = 1'b0;
        expected[1].is_load = 1'b0;
        expected[1].is_store = 1'b0;
        expected[1].is_branch = 1'b1;
        expected[1].is_cas = 1'b0;
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        check_results(0);
        check_results(1);
    endtask
    
    // Test 5: CAS instruction
    task test_cas();
        $display("\n=== Test 5: CAS Instruction ===");
        
        // Lane 0: CAS X1, X2, X3
        instr[0] = {6'b101000, 5'd1, 5'd2, 5'd3, 11'd0};
        instr_valid[0] = 1'b1;
        pc[0] = 32'h5000;
        
        expected[0].opcode = 6'b101000;
        expected[0].rd = 5'd1;
        expected[0].rs1 = 5'd2;
        expected[0].rs2 = 5'd3;
        expected[0].imm = 32'd0;
        expected[0].rs1_valid = 1'b1;
        expected[0].rs2_valid = 1'b1;
        expected[0].rd_valid = 1'b1;
        expected[0].is_alu = 1'b0;
        expected[0].is_load = 1'b0;
        expected[0].is_store = 1'b0;
        expected[0].is_branch = 1'b0;
        expected[0].is_cas = 1'b1;
        
        // Lane 1: NOP
        instr[1] = {6'b111000, 26'd0};
        instr_valid[1] = 1'b1;
        pc[1] = 32'h5004;
        
        expected[1].opcode = 6'b111000;
        expected[1].rd = 5'd0;
        expected[1].rs1 = 5'd0;
        expected[1].rs2 = 5'd0;
        expected[1].imm = 32'd0;
        expected[1].rs1_valid = 1'b0;
        expected[1].rs2_valid = 1'b0;
        expected[1].rd_valid = 1'b0;
        expected[1].is_alu = 1'b0;
        expected[1].is_load = 1'b0;
        expected[1].is_store = 1'b0;
        expected[1].is_branch = 1'b0;
        expected[1].is_cas = 1'b0;
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        check_results(0);
        check_results(1);
    endtask
    
    // Test 6: Invalid instructions and NOPs
    task test_invalid();
        $display("\n=== Test 6: Invalid Instructions ===");
        
        // Lane 0: Undefined opcode
        instr[0] = 32'hDEADBEEF;
        instr_valid[0] = 1'b1;
        pc[0] = 32'h6000;
        
        expected[0].opcode = 6'b111111;  // Should be treated as NOP
        expected[0].rd = 5'd0;
        expected[0].rs1 = 5'd0;
        expected[0].rs2 = 5'd0;
        expected[0].imm = 32'd0;
        expected[0].rs1_valid = 1'b0;
        expected[0].rs2_valid = 1'b0;
        expected[0].rd_valid = 1'b0;
        expected[0].is_alu = 1'b0;
        expected[0].is_load = 1'b0;
        expected[0].is_store = 1'b0;
        expected[0].is_branch = 1'b0;
        expected[0].is_cas = 1'b0;
        
        // Lane 1: Valid instruction but instr_valid=0
        instr[1] = {6'b000000, 5'd1, 5'd2, 5'd3, 5'd0, 6'b000000};
        instr_valid[1] = 1'b0;
        pc[1] = 32'h6004;
        
        // Should output dec_valid=0
        expected[1].opcode = 6'b000000;
        expected[1].rd = 5'd0;
        expected[1].rs1 = 5'd0;
        expected[1].rs2 = 5'd0;
        expected[1].imm = 32'd0;
        expected[1].rs1_valid = 1'b0;
        expected[1].rs2_valid = 1'b0;
        expected[1].rd_valid = 1'b0;
        expected[1].is_alu = 1'b0;
        expected[1].is_load = 1'b0;
        expected[1].is_store = 1'b0;
        expected[1].is_branch = 1'b0;
        expected[1].is_cas = 1'b0;
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        if (dec_valid[0] !== 1'b1) begin
            $display("%t: Lane 0: dec_valid should be 1 for NOP", $time);
            $finish(1);
        end
        if (dec_valid[1] !== 1'b0) begin
            $display("%t: Lane 1: dec_valid should be 0 when instr_valid=0", $time);
            $finish(1);
        end
        $display("%t: Invalid instruction test PASS", $time);
    endtask
    
    // Test 7: Backpressure test
    task test_backpressure();
        $display("\n=== Test 7: Backpressure Test ===");
        
        // First cycle: decode_ready=0
        instr[0] = {6'b000000, 5'd1, 5'd2, 5'd3, 5'd0, 6'b000000};
        instr[1] = {6'b001000, 5'd4, 5'd5, 12'd100};
        instr_valid = 2'b11;
        pc[0] = 32'h7000;
        pc[1] = 32'h7004;
        decode_ready = 1'b0;
        
        @(posedge clk);
        
        // Check that dec_valid should be 0 when decode_ready=0
        if (dec_valid !== 2'b00) begin
            $display("%t: Backpressure: dec_valid should be 00 when decode_ready=0", $time);
            $finish(1);
        end
        
        // Second cycle: decode_ready=1
        decode_ready = 1'b1;
        @(posedge clk);
        
        // Now outputs should be valid
        if (dec_valid !== 2'b11) begin
            $display("%t: Backpressure: dec_valid should be 11 when decode_ready=1", $time);
            $finish(1);
        end
        
        $display("%t: Backpressure test PASS", $time);
    endtask
    
    // Test 8: Immediate sign extension tests
    task test_imm_sign_extend();
        $display("\n=== Test 8: Immediate Sign Extension ===");
        
        // Test positive and negative immediates for different instruction types
        
        // I-type: ADDI with maximum positive immediate (2047)
        instr[0] = {6'b001000, 5'd1, 5'd2, 12'h7FF};
        instr_valid[0] = 1'b1;
        pc[0] = 32'h8000;
        
        expected[0].opcode = 6'b001000;
        expected[0].rd = 5'd1;
        expected[0].rs1 = 5'd2;
        expected[0].imm = 32'h000007FF;
        expected[0].rs1_valid = 1'b1;
        expected[0].rs2_valid = 1'b0;
        expected[0].rd_valid = 1'b1;
        expected[0].is_alu = 1'b1;
        
        // I-type: ADDI with negative immediate (-2048)
        instr[1] = {6'b001000, 5'd3, 5'd4, 12'h800};
        instr_valid[1] = 1'b1;
        pc[1] = 32'h8004;
        
        expected[1].opcode = 6'b001000;
        expected[1].rd = 5'd3;
        expected[1].rs1 = 5'd4;
        expected[1].imm = 32'hFFFFF800;
        expected[1].rs1_valid = 1'b1;
        expected[1].rs2_valid = 1'b0;
        expected[1].rd_valid = 1'b1;
        expected[1].is_alu = 1'b1;
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        check_results(0);
        check_results(1);
        
        // Branch with negative offset
        instr[0] = {6'b100000, 26'h3FFFFFF};  // -1 << 2 = -4
        instr_valid = 2'b01;
        pc[0] = 32'h8010;
        
        expected[0].opcode = 6'b100000;
        expected[0].imm = -32'd4;
        
        @(posedge clk);
        check_results(0);
        
        $display("%t: Immediate sign extension tests PASS", $time);
    endtask
    
    // Test 9: Register X0 handling
    task test_x0_handling();
        $display("\n=== Test 9: X0 Register Handling ===");
        
        // Even though X0 is hardwired to zero externally, decode should still
        // output the register numbers as-is
        
        // ADDI X0, X1, #42 (rd is X0 - should still be marked as valid rd)
        instr[0] = {6'b001000, 5'd0, 5'd1, 12'd42};
        instr_valid[0] = 1'b1;
        pc[0] = 32'h9000;
        
        expected[0].opcode = 6'b001000;
        expected[0].rd = 5'd0;
        expected[0].rs1 = 5'd1;
        expected[0].imm = 32'd42;
        expected[0].rs1_valid = 1'b1;
        expected[0].rd_valid = 1'b1;  // rd_valid should still be 1
        
        decode_ready = 1'b1;
        @(posedge clk);
        
        check_results(0);
        
        $display("%t: X0 register handling PASS", $time);
    endtask
    
    // Main test sequence
    initial begin
        $display("Starting decode module testbench...\n");
        
        // Initialize
        reset_test();
        
        // Run all tests
        test_rtype();
        test_itype();
        test_memtype();
        test_branches();
        test_cas();
        test_invalid();
        test_backpressure();
        test_imm_sign_extend();
        test_x0_handling();
        
        // All tests passed
        $display("\n======================================");
        $display("All tests PASSED!");
        $display("======================================\n");
        $finish(0);
    end
    
    // Waveform dump for debugging
    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("decode_tb.vcd");
            $dumpvars(0, decode_tb);
        end
    end
    
endmodule
