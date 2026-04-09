`timescale 1ns/1ps
import core_pkg::*;

module inst_rom #(
    parameter int ROM_SIZE = 256,     
    parameter int XLEN = 32
)(
    input  logic             clk,
    input  logic             reset,

    // Fetch interface
    input  logic             imem_ren,
    input  logic [XLEN-1:0]  imem_addr0,
    input  logic [XLEN-1:0]  imem_addr1,

    output logic             imem_valid,
    output logic [XLEN-1:0]  imem_rdata0,
    output logic [XLEN-1:0]  imem_rdata1,
    output logic [1:0][XLEN-1:0]  imem_pc
);

    // ROM storage with BRAM inference
    (* ram_style = "block" *) 
    logic [XLEN-1:0] rom [0:(ROM_SIZE/4)-1];

    // ============================================================
    //  Hardcoded Program (initialized at synthesis)
    // ============================================================
    initial begin
        // Initialize all to NOP (optional - only needed if you access uninitialized addresses)
        for (int i = 0; i < (ROM_SIZE/4); i++) begin
            rom[i] = 32'h00000000;
        end

        // UART Hello World Program
        rom['h00] = 32'h20200001;  // ADDI X1, X0, #1
        rom['h01] = 32'h20A00010;  // ADDI X5, X0, #16
        rom['h02] = 32'h00212800;  // LSL X1, X1, X5
        rom['h03] = 32'h20410004;  // ADDI X2, X1, #4
        rom['h04] = 32'h20C00001;  // ADDI X6, X0, #1  (X6 = TX_BUSY mask)
        rom['h05] = 32'h21200002;  // ADDI X9, X0, #2
        rom['h06] = 32'h20A0000C;  // ADDI X5, X0, #12
        rom['h07] = 32'h01292800;  // LSL X9, X9, X5
        rom['h08] = 32'h20C00048;  // ADDI X6, X0, #72  ('H')
        rom['h09] = 32'h44C90000;  // STR X6, [X9, #0]
        rom['h0A] = 32'h20C00065;  // ADDI X6, X0, #101 ('e')
        rom['h0B] = 32'h44C90004;  // STR X6, [X9, #4]
        rom['h0C] = 32'h20C0006C;  // ADDI X6, X0, #108 ('l')
        rom['h0D] = 32'h44C90008;  // STR X6, [X9, #8]
        rom['h0E] = 32'h20C0006C;  // ADDI X6, X0, #108 ('l')
        rom['h0F] = 32'h44C9000C;  // STR X6, [X9, #12]
        rom['h10] = 32'h20C0006F;  // ADDI X6, X0, #111 ('o')
        rom['h11] = 32'h44C90010;  // STR X6, [X9, #16]
        rom['h12] = 32'h20C0002C;  // ADDI X6, X0, #44  (',')
        rom['h13] = 32'h44C90014;  // STR X6, [X9, #20]
        rom['h14] = 32'h20C00020;  // ADDI X6, X0, #32  (' ')
        rom['h15] = 32'h44C90018;  // STR X6, [X9, #24]
        rom['h16] = 32'h20C0004C;  // ADDI X6, X0, #76  ('L')
        rom['h17] = 32'h44C9001C;  // STR X6, [X9, #28]
        rom['h18] = 32'h20C00045;  // ADDI X6, X0, #69  ('E')
        rom['h19] = 32'h44C90020;  // STR X6, [X9, #32]
        rom['h1A] = 32'h20C00047;  // ADDI X6, X0, #71  ('G')
        rom['h1B] = 32'h44C90024;  // STR X6, [X9, #36]
        rom['h1C] = 32'h20C00076;  // ADDI X6, X0, #118 ('v')
        rom['h1D] = 32'h44C90028;  // STR X6, [X9, #40]
        rom['h1E] = 32'h20C00038;  // ADDI X6, X0, #56  ('8')
        rom['h1F] = 32'h44C9002C;  // STR X6, [X9, #44]
        rom['h20] = 32'h20C00021;  // ADDI X6, X0, #33  ('!')
        rom['h21] = 32'h44C90030;  // STR X6, [X9, #48]
        rom['h22] = 32'h20C0000D;  // ADDI X6, X0, #13  (CR)
        rom['h23] = 32'h44C90034;  // STR X6, [X9, #52]
        rom['h24] = 32'h20C0000A;  // ADDI X6, X0, #10  (LF)
        rom['h25] = 32'h44C90038;  // STR X6, [X9, #56]
        rom['h26] = 32'h20C00000;  // ADDI X6, X0, #0   (null terminator)
        rom['h27] = 32'h44C9003C;  // STR X6, [X9, #60]
        rom['h28] = 32'h20690000;  // ADDI X3, X9, #0   (X3 = string pointer)
        
        // send_string loop
        rom['h29] = 32'h40830000;  // LDR X4, [X3, #0]
        rom['h2A] = 32'h6080001B;  // CBZ X4, done (PC+27 words)
        
        // wait_tx loop
        rom['h2B] = 32'h40C20000;  // LDR X6, [X2, #0]
        rom['h2C] = 32'h00C62824;  // AND X6, X6, X6
        rom['h2D] = 32'h64DFFFFE;  // CBNZ X6, wait_tx (PC-8)
        
        rom['h2E] = 32'h44810000;  // STR X4, [X1, #0]
        rom['h2F] = 32'h20630004;  // ADDI X3, X3, #4
        rom['h30] = 32'h83FFFFF6;  // B send_string (PC-40)
        
        // done: infinite loop
        rom['h31] = 32'h80000000;  // B done
    end

    // ============================================================
    //  Read Logic (1-cycle latency)
    // ============================================================
    always_ff @(posedge clk) begin
        if (imem_ren) begin
            imem_valid <= 1'b1;
            imem_rdata0 <= rom[imem_addr0[XLEN-1:2]];
            imem_rdata1 <= rom[imem_addr1[XLEN-1:2]];
            imem_pc[0] <= imem_addr0;
            imem_pc[1] <= imem_addr1;
            
            // synthesis translate_off
            $display("[IROM] Fetch: PC0=%h, instr0=%h, PC1=%h, instr1=%h", 
                    imem_addr0, rom[imem_addr0[XLEN-1:2]], 
                    imem_addr1, rom[imem_addr1[XLEN-1:2]]);
            // synthesis translate_on
        end else begin
            imem_valid <= 1'b0;
        end
    end

endmodule
