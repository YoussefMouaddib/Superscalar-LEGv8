// vga_engine.sv
// 640×480 @ 60 Hz VGA text mode display engine
// Character grid: 80 columns × 30 rows (8×16 pixel font)
//
// Clock: clk_vga = 25 MHz (from MMCM)
//
// VGA 640×480@60Hz timing (Industry Standard):
//   Horizontal (pixels at 25 MHz):
//     Active:       640
//     Front porch:   16
//     Sync pulse:    96   (HSYNC active low)
//     Back porch:    48
//     Total:        800   → 800 × 40 ns = 32 µs line period
//
//   Vertical (lines):
//     Active:       480
//     Front porch:   10
//     Sync pulse:     2   (VSYNC active low)
//     Back porch:    33
//     Total:        525   → 525 × 32 µs = 16.8 ms frame → 59.52 Hz ≈ 60 Hz
//
// Font: 8×16 pixels per character → 80 cols × 30 rows = 2400 cells
//       Pixels below row 479 (row 480) and right of col 639 are black.
//
// Pipeline (all registered, 3-stage):
//   Stage 1: compute char cell address, send to charram
//   Stage 2: charram returns char+color; compute font ROM address, send to font_rom
//   Stage 3: font_rom returns pixel row; shift out correct pixel bit
//   Output:  RGB driven combinationally from stage 3 result + blanking
//
// Because of the 2-cycle RAM pipeline (charram 1 cycle + font_rom 1 cycle),
// the pixel counter is offset by 2 cycles when computing the output.
// This is handled by carrying blanking and pixel-position through the pipeline.

`timescale 1ns/1ps

module vga_engine (
    input  logic        clk_vga,    // 25 MHz pixel clock
    input  logic        reset,      // sync to clk_vga (use reset_sync output from top)

    // Character RAM interface
    output logic [11:0] charram_addr,   // cell index to read
    input  logic [15:0] charram_data,   // char[7:0] + color[9:8], 1 cycle latency

    // Font ROM interface
    output logic [11:0] font_addr,      // {char_code[7:0], row[3:0]}, 1 cycle latency
    input  logic [7:0]  font_data,      // 8 pixel bits, MSB=leftmost

    // VGA outputs (to JD Pmod → VGA connector)
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,
    output logic        vga_hs,         // horizontal sync, active low
    output logic        vga_vs          // vertical sync, active low
);

    // ----------------------------------------------------------------
    // VGA timing parameters
    // ----------------------------------------------------------------
    // Horizontal
    localparam int H_ACTIVE  = 640;
    localparam int H_FP      = 16;
    localparam int H_SYNC    = 96;
    localparam int H_BP      = 48;
    localparam int H_TOTAL   = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    // Vertical
    localparam int V_ACTIVE  = 480;
    localparam int V_FP      = 10;
    localparam int V_SYNC    = 2;
    localparam int V_BP      = 33;
    localparam int V_TOTAL   = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 525

    // Font / grid
    localparam int FONT_W    = 8;
    localparam int FONT_H    = 16;
    localparam int GRID_COLS = H_ACTIVE / FONT_W;  // 80
    localparam int GRID_ROWS = V_ACTIVE / FONT_H;  // 30

    // ----------------------------------------------------------------
    // Pixel / line counters
    // ----------------------------------------------------------------
    logic [9:0] hcount;    // 0..799
    logic [9:0] vcount;    // 0..524

    always_ff @(posedge clk_vga or posedge reset) begin
        if (reset) begin
            hcount <= '0;
            vcount <= '0;
        end else begin
            if (hcount == H_TOTAL - 1) begin
                hcount <= '0;
                if (vcount == V_TOTAL - 1)
                    vcount <= '0;
                else
                    vcount <= vcount + 1'b1;
            end else begin
                hcount <= hcount + 1'b1;
            end
        end
    end

    // Active video region (combinational, used for pipeline stage 1)
    logic h_active_s1, v_active_s1;
    assign h_active_s1 = (hcount < H_ACTIVE);
    assign v_active_s1 = (vcount < V_ACTIVE);

    // ----------------------------------------------------------------
    // Sync pulse generation (combinational from counters)
    // HSYNC active during [H_ACTIVE+H_FP .. H_ACTIVE+H_FP+H_SYNC-1]
    // VSYNC active during [V_ACTIVE+V_FP .. V_ACTIVE+V_FP+V_SYNC-1]
    // Active LOW per VGA standard
    // ----------------------------------------------------------------
    logic hs_raw, vs_raw;
    assign hs_raw = ~((hcount >= (H_ACTIVE + H_FP)) &&
                      (hcount <  (H_ACTIVE + H_FP + H_SYNC)));
    assign vs_raw = ~((vcount >= (V_ACTIVE + V_FP)) &&
                      (vcount <  (V_ACTIVE + V_FP + V_SYNC)));

    // ----------------------------------------------------------------
    // Pipeline Stage 1: Compute char RAM address, register sync/blank
    // ----------------------------------------------------------------
    // Character cell for current pixel
    logic [6:0] col_s1;    // 0..79, which column
    logic [4:0] row_s1;    // 0..29, which row
    logic [3:0] pixel_col; // 0..7, which pixel within the char cell horizontally
    logic [3:0] pixel_row; // 0..15, which pixel within the char cell vertically

    assign col_s1    = hcount[9:3];      // hcount / 8  (integer divide, ignore frac)
    assign row_s1    = vcount[8:4];      // vcount / 16
    assign pixel_col = hcount[2:0];      // hcount % 8 (which bit in font row)
    assign pixel_row = vcount[3:0];      // vcount % 16

    // Issue charram read
    // charram_addr = row * 80 + col
    // Use 12-bit: row(5b) * 80 = up to 29*80=2320, fits in 12b
    assign charram_addr = {2'b0, row_s1} * 12'd80 + {5'b0, col_s1};

    // Register stage 1 → stage 2
    logic        blank_s2, hs_s2, vs_s2;
    logic [3:0]  pixel_col_s2;
    logic [3:0]  pixel_row_s2;

    always_ff @(posedge clk_vga or posedge reset) begin
        if (reset) begin
            blank_s2     <= 1'b1;
            hs_s2        <= 1'b1;
            vs_s2        <= 1'b1;
            pixel_col_s2 <= '0;
            pixel_row_s2 <= '0;
        end else begin
            blank_s2     <= ~(h_active_s1 && v_active_s1);
            hs_s2        <= hs_raw;
            vs_s2        <= vs_raw;
            pixel_col_s2 <= pixel_col;
            pixel_row_s2 <= pixel_row;
        end
    end

    // ----------------------------------------------------------------
    // Pipeline Stage 2: charram data available → issue font ROM read
    // charram_data[7:0]  = char code
    // charram_data[9:8]  = color attribute
    // ----------------------------------------------------------------
    // font_addr = {char_code, pixel_row} = 12 bits
    assign font_addr = {charram_data[7:0], pixel_row_s2};

    // Register stage 2 → stage 3
    logic        blank_s3, hs_s3, vs_s3;
    logic [3:0]  pixel_col_s3;
    logic [1:0]  color_s3;

    always_ff @(posedge clk_vga or posedge reset) begin
        if (reset) begin
            blank_s3     <= 1'b1;
            hs_s3        <= 1'b1;
            vs_s3        <= 1'b1;
            pixel_col_s3 <= '0;
            color_s3     <= 2'b00;
        end else begin
            blank_s3     <= blank_s2;
            hs_s3        <= hs_s2;
            vs_s3        <= vs_s2;
            pixel_col_s3 <= pixel_col_s2;
            color_s3     <= charram_data[9:8];
        end
    end

    // ----------------------------------------------------------------
    // Pipeline Stage 3: font_data available → drive RGB output
    // font_data[7:0]: bit 7=leftmost pixel, bit 0=rightmost
    // pixel_col_s3=0 → bit 7, pixel_col_s3=7 → bit 0
    // ----------------------------------------------------------------
    logic pixel_on;
    assign pixel_on = font_data[3'd7 - pixel_col_s3[2:0]];

    // Color palette (4 colors via 2-bit attribute):
    //   00 = white on black  (fg: 4'hF, bg: 4'h0)
    //   01 = cyan on black   (fg: R=0,G=F,B=F)
    //   10 = yellow on black (fg: R=F,G=F,B=0)
    //   11 = red on black    (fg: R=F,G=0,B=0)
    logic [3:0] fg_r, fg_g, fg_b;

    always_comb begin
        case (color_s3)
            2'b00: begin fg_r = 4'hF; fg_g = 4'hF; fg_b = 4'hF; end  // white
            2'b01: begin fg_r = 4'h0; fg_g = 4'hF; fg_b = 4'hF; end  // cyan
            2'b10: begin fg_r = 4'hF; fg_g = 4'hF; fg_b = 4'h0; end  // yellow
            2'b11: begin fg_r = 4'hF; fg_g = 4'h0; fg_b = 4'h0; end  // red
        endcase
    end

    // Final RGB output: pixel_on ? foreground : black, gated by blank
    always_ff @(posedge clk_vga or posedge reset) begin
        if (reset) begin
            vga_r  <= 4'h0;
            vga_g  <= 4'h0;
            vga_b  <= 4'h0;
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else begin
            vga_hs <= hs_s3;
            vga_vs <= vs_s3;
            if (blank_s3 || !pixel_on) begin
                vga_r <= 4'h0;
                vga_g <= 4'h0;
                vga_b <= 4'h0;
            end else begin
                vga_r <= fg_r;
                vga_g <= fg_g;
                vga_b <= fg_b;
            end
        end
    end

endmodule
