// font_rom.sv
// 8×16 character font ROM
// 256 characters × 16 rows × 8 pixels = 256 × 16 = 4096 bytes
//
// Initialized from font_cp437.mem (hex file, one byte per line)
// Each byte = one row of 8 pixels, MSB = leftmost pixel
// Character N starts at byte offset N*16
//
// This is the standard IBM CP437 / PC BIOS font, public domain.
// The .mem file must be generated once and checked into the repo.
// See gen_font.py in the host/ directory for the generator script.
//
// Read latency: 1 cycle (registered output)

`timescale 1ns/1ps

module font_rom (
    input  logic        clk,
    input  logic [11:0] addr,   // [11:4]=char_code (256 chars), [3:0]=row (16 rows)
    output logic [7:0]  data    // 8 pixels, MSB=left
);
    // 4 KB font storage
    logic [7:0] mem [0:4095];

    initial begin
        $readmemh("font_cp437.mem", mem);
    end

    // Registered read - 1 cycle latency, matches BRAM timing
    always_ff @(posedge clk) begin
        data <= mem[addr];
    end

endmodule
