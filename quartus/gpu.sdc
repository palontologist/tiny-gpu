# Timing Constraints — tiny-gpu HaDes-V Intel FPGA build
# Target: 200 MHz on Cyclone V / Arria 10
#         250 MHz on Agilex 7  (adjust -period accordingly)

# ---- Primary clock ----
create_clock -name clk -period 5.0 [get_ports clk]
# For 200 MHz target: -period 5.0
# For 250 MHz target: -period 4.0

# ---- Input constraints ----
set_false_path -from [get_ports reset]
set_false_path -from [get_ports start]

# ---- Output constraints ----
set_false_path -to [get_ports done]

# ---- PLL clock derivation (add if a PLL IP is instantiated) ----
# derive_pll_clocks
# derive_clock_uncertainty

# ---- Multicycle paths ----
# ROB hazard check is a combinational tree — allow 2 cycles for timing closure
set_multicycle_path -from [get_registers {rob_instance*}] \
                    -to   [get_registers {scheduler_instance*}] \
                    -setup 2
set_multicycle_path -from [get_registers {rob_instance*}] \
                    -to   [get_registers {scheduler_instance*}] \
                    -hold 1
