# Define your clock - adjust period for your target frequency
# 10.000ns = 100MHz, change to match what you're targeting
create_clock -period 10.000 -name clk [get_ports clk]

# Tell the tool your inputs arrive after some delay from the clock edge
# This is a safe default if you don't know your exact board timing
set_input_delay -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]