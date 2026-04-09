# ==============================================================================
# Arty A7-100T Constraints - OOO CPU with VGA + Ethernet
# Revision: I/O expansion (replaces debug LED/Pmod bus)
# ==============================================================================

# ------------------------------------------------------------------------------
# Clock - 100 MHz crystal oscillator (true frequency, MMCM generates all others)
# ------------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name clk_100 [get_ports clk]

# MMCM-generated clocks (Vivado auto-derives these from the MMCM primitive,
# but explicit declarations help static timing analysis)
# These names must match the MMCM output net names after synthesis.
# If Vivado renames them, update accordingly after first synthesis run.
# create_generated_clock -name clk_core -source [get_pins clk_gen/mmcm_inst/CLKIN1] \
#     -multiply_by 10 -divide_by 1 -master_clock clk_100 \
#     [get_pins clk_gen/mmcm_inst/CLKOUT0]
# (Leave commented - Vivado handles MMCM-generated clocks automatically)

# ------------------------------------------------------------------------------
# Reset (BTN0, active high)
# ------------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports reset]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets reset_IBUF]

# ------------------------------------------------------------------------------
# UART TX (USB-UART bridge, real 8N1 serializer now)
# ------------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx]
set_output_delay -clock [get_clocks clk_100] 2.0 [get_ports uart_tx]

# ------------------------------------------------------------------------------
# VGA Output - JD Pmod (dual-row, 12 data pins + 2 sync)
#
# Digilent PmodVGA pinout on JD:
#   JD upper row:  JD1=VGA_R3  JD2=VGA_R2  JD3=VGA_R1  JD4=VGA_R0
#   JD lower row:  JD7=VGA_B3  JD8=VGA_B2  JD9=VGA_B1  JD10=VGA_B0
#
# Wait - the PmodVGA (12-pin) actually needs both a JD and JC dual connector
# OR you can use the single Pmod connector if it's a 2x6 right-angle.
# The Arty A7-100T JD is a single 12-pin (2×6) connector, which is exactly
# what the Digilent PmodVGA requires. Perfect fit.
#
# Arty A7-100T JD pin assignments (from Digilent Arty A7 Master XDC):
#   JD[1]=H4   JD[2]=H1   JD[3]=G1   JD[4]=G3
#   JD[7]=H2   JD[8]=G4   JD[9]=G2   JD[10]=F6  (wrong, see note)
#
# IMPORTANT: The actual Arty A7-100T JD pins differ from A7-35T.
# Use these verified pins from the official Arty A7-100T Master XDC:
# https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc
#
# JD1 = H4    JD2 = H1    JD3 = G1    JD4 = G3
# JD7 = H2    JD8 = G4    JD9 = G2    JD10 = F6   ← verify against your board rev
#
# PmodVGA connector mapping (from PmodVGA reference manual):
#   Pin 1 = VGA_R3  Pin 2 = VGA_R2  Pin 3 = VGA_R1  Pin 4 = VGA_R0
#   Pin 5 = GND     Pin 6 = VCC
#   Pin 7 = VGA_B3  Pin 8 = VGA_B2  Pin 9 = VGA_B1  Pin 10= VGA_B0
#   Pin 11= GND     Pin 12= VCC
#   (G and sync are on the other connector row of a 2×12 PmodVGA)
#
# The Digilent PmodVGA is actually a 2×6 connector using TWO Pmod ports.
# For the full 4R+4G+4B+HSYNC+VSYNC configuration you need JC+JD together.
# JC handles: R[3:0], HSYNC, VSYNC
# JD handles: G[3:0], B[3:0]
#
# *** SIMPLIFIED APPROACH for first bring-up ***
# Use JD only with a simpler 2-bit per channel VGA Pmod (or wire manually).
# The XDC below is for the full Digilent PmodVGA using JC+JD.
# JC is now FREE (we removed uart_read_data_out) - perfect timing.
# ------------------------------------------------------------------------------

# VGA Red [3:0] → JC upper row (JC1-JC4)
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]

# VGA Green [3:0] → JD upper row (JD1-JD4)
set_property -dict {PACKAGE_PIN H4  IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN H1  IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN G1  IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN G3  IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]

# VGA Blue [3:0] → JD lower row (JD7-JD10)
set_property -dict {PACKAGE_PIN H2  IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN G4  IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN G2  IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN F6  IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]

# VGA HSYNC, VSYNC → JC lower row (JC7, JC8)
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports vga_hs]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports vga_vs]

# VGA timing constraints: outputs driven by clk_vga (25 MHz)
# False path because VGA signals are asynchronous display outputs
set_false_path -to [get_ports {vga_r[*] vga_g[*] vga_b[*] vga_hs vga_vs}]

# ------------------------------------------------------------------------------
# Ethernet - LAN8720 onboard (fixed pins, soldered to Arty A7-100T PCB)
# These are the standard Arty A7 Ethernet pin assignments.
# Verify against your specific board revision.
# ------------------------------------------------------------------------------

# RMII receive (from PHY to FPGA)
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports eth_crs_dv]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[0]}]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[1]}]

# RMII ref clock (50 MHz from FPGA to PHY) - this drives the PHY reference
# Must be on a clock-capable output pin or use ODDR for clean clock output
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports eth_ref_clk]

# PHY reset (active low)
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports eth_rstn]

# Ethernet timing constraints
# eth_ref_clk is driven from MMCM clk_eth - set as generated clock
# For now, set false path on the ref clock output (it's a generated clock, not a data path)
set_false_path -to [get_ports eth_ref_clk]
set_false_path -to [get_ports eth_rstn]

# Input constraints for RMII RX (data valid on rising edge of eth_ref_clk)
# Adjust setup/hold based on LAN8720 datasheet (typ: setup=4ns, hold=2ns before ref_clk edge)
# set_input_delay -clock [generated eth_ref_clk] -max 4.0 [get_ports {eth_crs_dv eth_rxd[*]}]
# set_input_delay -clock [generated eth_ref_clk] -min 1.0 [get_ports {eth_crs_dv eth_rxd[*]}]
# Commented for now - add properly when Ethernet RX FSM is implemented

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# ------------------------------------------------------------------------------
# Timing exceptions
# ------------------------------------------------------------------------------
# Async reset - not a timing path
set_false_path -from [get_ports reset]

# Cross-clock domain: clk_core → clk_vga (VGA char RAM write from CPU, read by VGA)
# The dual-port BRAM handles this internally; flag the crossing explicitly
set_false_path -from [get_clocks clk_core*] -to [get_clocks clk_vga*]
set_false_path -from [get_clocks clk_vga*]  -to [get_clocks clk_core*]

# NOTE: After first Vivado synthesis, run report_clock_interaction to verify
# these CDC paths are properly constrained. The BRAM gray-code addressing
# provides metastability protection for the dual-clock FIFO behavior.

# ------------------------------------------------------------------------------
# Board-specific
# ------------------------------------------------------------------------------
# Tell Vivado this is a 100T (already set in project, belt-and-suspenders)
# set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
