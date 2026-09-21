`timescale 1ns/1ps
import core_pkg::*;

module inst_rom #(
    parameter int ROM_SIZE = 256,     
    parameter int XLEN = 32
)(
    input  logic               clk,
    input  logic               reset,

    // Fetch interface
    input  logic               imem_ren,
    input  logic [XLEN-1:0]    imem_addr0,
    input  logic [XLEN-1:0]    imem_addr1,

    output logic               imem_valid,
    output logic [XLEN-1:0]    imem_rdata0,
    output logic [XLEN-1:0]    imem_rdata1,
    output logic [1:0][XLEN-1:0] imem_pc
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

        // New Program Demo Initialization
        rom['h00] = 32'h20200003;
        rom['h01] = 32'h23600010;
        rom['h02] = 32'h0021D800;
        rom['h03] = 32'h20400034;
        rom['h04] = 32'h84000002;
        rom['h05] = 32'h80000000;
        rom['h06] = 32'h40620000;
        rom['h07] = 32'h60600014;
        rom['h08] = 32'h44610000;
        rom['h09] = 32'h20210004;
        rom['h0A] = 32'h20420004;
        rom['h0B] = 32'h83FFFFFB;
        rom['h0C] = 32'h001E0038;
        rom['h0D] = 32'h00000053; // 'S'
        rom['h0E] = 32'h00000075; // 'u'
        rom['h0F] = 32'h00000070; // 'p'
        rom['h10] = 32'h00000065; // 'e'
        rom['h11] = 32'h00000072; // 'r'
        rom['h12] = 32'h00000073; // 's'
        rom['h13] = 32'h00000063; // 'c'
        rom['h14] = 32'h00000061; // 'a'
        rom['h15] = 32'h0000006C; // 'l'
        rom['h16] = 32'h00000061; // 'a'
        rom['h17] = 32'h00000072; // 'r'
        rom['h18] = 32'h00000020; // ' '
        rom['h19] = 32'h0000004C; // 'L'
        rom['h1A] = 32'h00000045; // 'E'
        rom['h1B] = 32'h00000047; // 'G'
        rom['h1C] = 32'h00000076; // 'v'
        rom['h1D] = 32'h00000038; // '8'
        rom['h1E] = 32'h00000020; // ' '
        rom['h1F] = 32'h0000004B; // 'K'
        rom['h20] = 32'h00000065; // 'e'
        rom['h21] = 32'h00000072; // 'r'
        rom['h22] = 32'h0000006E; // 'n'
        rom['h23] = 32'h00000065; // 'e'
        rom['h24] = 32'h0000006C; // 'l'
        rom['h25] = 32'h00000020; // ' '
        rom['h26] = 32'h00000069; // 'i'
        rom['h27] = 32'h00000075; // 's'
        rom['h28] = 32'h00000020; // ' '
        rom['h29] = 32'h0000004F; // 'O'
        rom['h2A] = 32'h0000004E; // 'N'
        rom['h2B] = 32'h00000000; // Null terminator
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
