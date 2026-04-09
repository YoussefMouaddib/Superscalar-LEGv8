// mmcm_clocks.sv
// Clock generation for OOO core I/O expansion
//
// Input:  100 MHz crystal oscillator (Arty A7-100T pin E3)
// Output: clk_core  = 60 MHz  → OOO pipeline (matches timing closure)
//         clk_vga   = 25 MHz  → VGA pixel clock (640×480@60Hz)
//         clk_eth   = 50 MHz  → LAN8720 RMII REF_CLK
//         locked          → all clocks stable; hold core in reset until high
//
// MMCM math (Artix-7, 100 MHz input):
//   VCO = input * CLKFBOUT_MULT_F / DIVCLK_DIVIDE
//   VCO must be in [600, 1200] MHz for Artix-7 speed grade -1
//
//   Chosen: DIVCLK_DIVIDE=1, CLKFBOUT_MULT_F=10.0 → VCO = 1000 MHz
//   clk_core : CLKOUT0_DIVIDE_F = 16.667 → 60.00 MHz  (exact: 1000/16.667)
//   clk_vga  : CLKOUT1_DIVIDE   = 40     → 25.00 MHz
//   clk_eth  : CLKOUT2_DIVIDE   = 20     → 50.00 MHz
//
// NOTE: CLKOUT0_DIVIDE_F accepts fractional values in steps of 0.125.
//       16.625 → 60.120 MHz, 16.750 → 59.701 MHz, 16.667 not exact.
//       Use 16.625 for closest to 60 MHz (0.2% error, well within UART tolerance).
//       UART divisor at 60.120 MHz, 115200 baud: 60120000/115200 = 521.9 → 522
//
// Synthesis: This file targets the Xilinx MMCME2_BASE primitive directly.
// If you prefer IP Catalog: use Clocking Wizard with these exact parameters
// and replace this file with the generated wrapper.

`timescale 1ns/1ps

module mmcm_clocks (
    input  logic clk_in,      // 100 MHz from crystal, pin E3
    input  logic reset_in,    // async reset from BTN0 (active high)
    output logic clk_core,    // 60 MHz → OOO core, UART
    output logic clk_vga,     // 25 MHz → VGA engine
    output logic clk_eth,     // 50 MHz → LAN8720 REF_CLK output
    output logic locked       // all outputs stable (active high)
);

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------
    logic clk_feedback;        // MMCM internal feedback path
    logic clk_feedback_buf;    // buffered feedback
    logic clk_core_raw;
    logic clk_vga_raw;
    logic clk_eth_raw;

    // ----------------------------------------------------------------
    // MMCME2_BASE primitive instantiation
    // Xilinx UG472 - 7 Series Clocking Resources
    // ----------------------------------------------------------------
    MMCME2_BASE #(
        // Input
        .CLKIN1_PERIOD      (10.0),      // 100 MHz → 10 ns period

        // VCO configuration
        .DIVCLK_DIVIDE      (1),         // input pre-divider
        .CLKFBOUT_MULT_F    (10.0),      // VCO multiplier → 1000 MHz VCO
        .CLKFBOUT_PHASE     (0.0),

        // CLKOUT0: ~60 MHz core clock
        .CLKOUT0_DIVIDE_F   (16.625),    // 1000/16.625 = 60.15 MHz
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT0_DUTY_CYCLE (0.5),

        // CLKOUT1: 25 MHz VGA pixel clock
        .CLKOUT1_DIVIDE     (40),        // 1000/40 = 25.00 MHz  (exact)
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT1_DUTY_CYCLE (0.5),

        // CLKOUT2: 50 MHz Ethernet RMII ref
        .CLKOUT2_DIVIDE     (20),        // 1000/20 = 50.00 MHz  (exact)
        .CLKOUT2_PHASE      (0.0),
        .CLKOUT2_DUTY_CYCLE (0.5),

        // Unused outputs - still need divide values
        .CLKOUT3_DIVIDE     (10),
        .CLKOUT4_DIVIDE     (10),
        .CLKOUT5_DIVIDE     (10),
        .CLKOUT3_PHASE      (0.0),
        .CLKOUT4_PHASE      (0.0),
        .CLKOUT5_PHASE      (0.0),
        .CLKOUT3_DUTY_CYCLE (0.5),
        .CLKOUT4_DUTY_CYCLE (0.5),
        .CLKOUT5_DUTY_CYCLE (0.5),

        .BANDWIDTH          ("OPTIMIZED"),
        .CLKOUT4_CASCADE    ("FALSE"),
        .REF_JITTER1        (0.0),
        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        // Input
        .CLKIN1     (clk_in),
        .RST        (reset_in),

        // Feedback (must use BUFG for internal feedback)
        .CLKFBIN    (clk_feedback_buf),
        .CLKFBOUT   (clk_feedback),

        // Outputs (raw, before BUFG)
        .CLKOUT0    (clk_core_raw),
        .CLKOUT1    (clk_vga_raw),
        .CLKOUT2    (clk_eth_raw),
        .CLKOUT3    (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT0B   (),
        .CLKOUT1B   (),
        .CLKOUT2B   (),

        // Status
        .LOCKED     (locked),

        // Unused
        .PWRDWN     (1'b0)
    );

    // ----------------------------------------------------------------
    // Global clock buffers (BUFG) - required for clock routing
    // Every MMCM output that drives flip-flops needs a BUFG.
    // ----------------------------------------------------------------
    BUFG bufg_feedback (.I(clk_feedback), .O(clk_feedback_buf));
    BUFG bufg_core     (.I(clk_core_raw), .O(clk_core));
    BUFG bufg_vga      (.I(clk_vga_raw),  .O(clk_vga));
    BUFG bufg_eth      (.I(clk_eth_raw),  .O(clk_eth));

endmodule
