`timescale 1ns/1ps

module alu_tb;
    reg [31:0] A, B;
    reg [3:0] CONTROL;
    wire [31:0] RESULT;
    wire ZEROFLAG;
    
    ALU uut (.A(A), .B(B), .CONTROL(CONTROL), .RESULT(RESULT), .ZEROFLAG(ZEROFLAG));
    
    initial begin
        $display("Testing ALU...");
        
        // Test ADD
        A = 32'd10; B = 32'd20; CONTROL = 4'b0010; #10;
        if (RESULT !== 32'd30) $display("FAIL: ADD 10+20=%0d", RESULT);
        else $display("PASS: ADD");
        
        // Test SUB  
        A = 32'd30; B = 32'd10; CONTROL = 4'b0011; #10;
        if (RESULT !== 32'd20) $display("FAIL: SUB 30-10=%0d", RESULT);
        else $display("PASS: SUB");
        
        // Test AND
        A = 32'hFFFF; B = 32'hF0F0; CONTROL = 4'b0000; #10;
        if (RESULT !== 32'hF0F0) $display("FAIL: AND");
        else $display("PASS: AND");
        
        // Test OR
        A = 32'h00FF; B = 32'hFF00; CONTROL = 4'b0001; #10;
        if (RESULT !== 32'hFFFF) $display("FAIL: OR");
        else $display("PASS: OR");
        
        // Test XOR
        A = 32'hFFFF; B = 32'hFFFF; CONTROL = 4'b0100; #10;
        if (RESULT !== 32'h0000) $display("FAIL: XOR");
        else $display("PASS: XOR");
        
        // Test Zero Flag
        A = 32'd5; B = 32'd5; CONTROL = 4'b0011; #10; // 5-5=0
        if (ZEROFLAG !== 1'b1) $display("FAIL: Zero Flag");
        else $display("PASS: Zero Flag");
        
        $display("ALU Test Complete");
        $finish;
    end
endmodule
