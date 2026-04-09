// vga_charram.sv
// 80×30 character display RAM
// Dual-port: CPU write port (clk_core), VGA read port (clk_vga)
// True dual-clock BRAM - synthesizes to Xilinx RAMB18/RAMB36
//
// Memory layout:
//   Cell address = row * 80 + col  (0 to 2399)
//   Each cell = 16 bits:
//     [7:0]  = ASCII character code
//     [9:8]  = color attribute: 00=white, 01=cyan, 10=yellow, 11=red
//     [15:10] = unused (keep 0)
//
// CPU memory map:
//   Word-aligned: byte address = 0x00030000 + cell_index * 4
//   The top-level address decoder strips the base and divides by 4.
//   CPU writes 32-bit words but only bits[9:0] are stored.
//
// VGA engine interface:
//   Provide cell_addr (0-2399), get back char_data 1 cycle later.

`timescale 1ns/1ps

module vga_charram #(
    parameter int COLS      = 80,
    parameter int ROWS      = 30,
    parameter int NUM_CELLS = COLS * ROWS   // 2400
)(
    // CPU write port (clk_core domain)
    input  logic        clk_cpu,
    input  logic        cpu_wen,
    input  logic [11:0] cpu_waddr,   // cell index 0-2399 (12 bits covers 4096)
    input  logic [15:0] cpu_wdata,   // [7:0]=char, [9:8]=color

    // VGA read port (clk_vga domain, 25 MHz)
    input  logic        clk_vga,
    input  logic [11:0] cpu_raddr,   // exposed for debug; VGA engine drives vga_raddr
    input  logic [11:0] vga_raddr,   // cell index from VGA engine
    output logic [15:0] vga_rdata    // char + color, 1 cycle latency
);

    // True dual-port BRAM
    // Xilinx infers RAMB36 for arrays > 16K bits; RAMB18 for <= 16K bits.
    // 2400 cells × 16 bits = 38,400 bits → one RAMB36
    (* ram_style = "block" *)
    logic [15:0] mem [0:NUM_CELLS-1];

    // Initialize to spaces (0x20) with white color (0x00)
    initial begin
        for (int i = 0; i < NUM_CELLS; i++)
            mem[i] = 16'h0020;   // space, white
    end

    // CPU write port (synchronous)
    always_ff @(posedge clk_cpu) begin
        if (cpu_wen)
            mem[cpu_waddr] <= cpu_wdata[15:0];
    end

    // VGA read port (synchronous, 1 cycle latency)
    always_ff @(posedge clk_vga) begin
        vga_rdata <= mem[vga_raddr];
    end

endmodule
