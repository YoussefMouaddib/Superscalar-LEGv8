# ==============================================================================
# Arty A7-100T Constraints for OOO CPU
# ==============================================================================

# ------------------------------------------------------------------------------
# Clock Signal (55 MHz oscillator on Arty A7)
# ------------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 18.180 -name sys_clk [get_ports clk]

# ------------------------------------------------------------------------------
# Reset (Button BTN0 on Arty A7)
# ------------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports reset]

# ------------------------------------------------------------------------------
# UART TX (FPGA TX to PC RX) - USB UART on Arty A7
# ------------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx]

# ------------------------------------------------------------------------------
# Debug Output - uart_read_data_out[31:0] mapped to LEDs + Pmod connectors
# ------------------------------------------------------------------------------
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets reset_IBUF]
set_property MAX_FANOUT 1000 [get_nets reset_IBUF]

# --- LEDs (4 bits: LD3, LD2, LD1, LD0) for bits [3:0] ---
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[3]}]

# --- RGB LEDs (using only R channel, 4 more bits) for bits [7:4] ---
set_property -dict {PACKAGE_PIN E1  IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[4]}]
set_property -dict {PACKAGE_PIN F6  IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[5]}]
set_property -dict {PACKAGE_PIN G6  IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[6]}]
set_property -dict {PACKAGE_PIN G4  IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[7]}]

# --- Pmod JA (8 pins) for bits [15:8] ---
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[8]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[9]}]
set_property -dict {PACKAGE_PIN A11 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[10]}]
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[11]}]
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[12]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[13]}]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[14]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[15]}]

# --- Pmod JB (8 pins) for bits [23:16] ---
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[16]}]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[17]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[18]}]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[19]}]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[20]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[21]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[22]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[23]}]

# --- Pmod JC (8 pins) for bits [31:24] ---
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[24]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[25]}]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[26]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[27]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[28]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[29]}]
set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[30]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {uart_read_data_out[31]}]

# ------------------------------------------------------------------------------
# Configuration Properties
# ------------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]


# ------------------------------------------------------------------------------
# Timing Constraints
# ------------------------------------------------------------------------------
# Relax timing on debug outputs (they're just for observability)
set_false_path -from [get_clocks sys_clk] -to [get_ports {uart_read_data_out[*]}]

# Optional: Add input/output delay constraints if needed
# set_input_delay -clock sys_clk 2 [get_ports reset]
# set_output_delay -clock sys_clk 2 [get_ports uart_tx]

# ------------------------------------------------------------------------------
# Device-specific for 100T - add these to ensure proper mapping
# ------------------------------------------------------------------------------
# Tell Vivado this is a 100T device (the part is set in project, but these help)
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
