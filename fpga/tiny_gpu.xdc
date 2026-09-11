## ==============================================================================
## tiny-gpu Xilinx Design Constraints (XDC)
## Target: AMD Xilinx Artix-7 (XC7A100T-2FGG484I)
## ==============================================================================

## -----------------------------------------------------------------------------
## 1. Primary Clock & Reset Constraints
## -----------------------------------------------------------------------------
## 50 MHz Master Oscillator Input
set_property -dict { PACKAGE_PIN R4    IOSTANDARD LVCMOS33 } [get_ports { sys_clk_50m }];
create_clock -period 20.000 -name sys_clk_50m -waveform {0.000 10.000} [get_ports { sys_clk_50m }];

## Active-Low Asynchronous Hardware Reset (Pushbutton / USB-C PD power-good)
set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

## -----------------------------------------------------------------------------
## 2. Derived Clock Networks & Clock Domain Crossings (CDC)
## -----------------------------------------------------------------------------
## Core Processing Clock: 50.0 MHz (Period: 20.0 ns)
## Display Pixel Clock:  25.175 MHz (Period: 39.722 ns - 640x480 @ 60Hz)
## DDR3L Memory Interface Clock: 100.0 MHz (Period: 10.0 ns)

set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk_50m] \
    -group [get_clocks -include_generated_clocks -filter {NAME =~ *clk_pixel*}] \
    -group [get_clocks -include_generated_clocks -filter {NAME =~ *clk_mem*}]

## -----------------------------------------------------------------------------
## 3. Status & Diagnostic LEDs
## -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { led_kernel_done }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led_core_busy   }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led_cache_hit   }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led_heartbeat   }];

## -----------------------------------------------------------------------------
## 4. HDMI 1.4 Video Interface (SII9022A Transmitter / Parallel RGB)
## -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_clk }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { hdmi_hsync }];
set_property -dict { PACKAGE_PIN W17   IOSTANDARD LVCMOS33 } [get_ports { hdmi_vsync }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { hdmi_de }];

## 24-bit RGB Data Bus (8:8:8)
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[0] }];  # B0
set_property -dict { PACKAGE_PIN Y19   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[1] }];  # B1
set_property -dict { PACKAGE_PIN AA18  IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[2] }];  # B2
set_property -dict { PACKAGE_PIN AA19  IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[3] }];  # B3
set_property -dict { PACKAGE_PIN AB20  IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[4] }];  # B4
set_property -dict { PACKAGE_PIN AB21  IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[5] }];  # B5
set_property -dict { PACKAGE_PIN AB22  IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[6] }];  # B6
set_property -dict { PACKAGE_PIN AA21  IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[7] }];  # B7

set_property -dict { PACKAGE_PIN V18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[8] }];  # G0
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[9] }];  # G1
set_property -dict { PACKAGE_PIN U20   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[10] }]; # G2
set_property -dict { PACKAGE_PIN U21   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[11] }]; # G3
set_property -dict { PACKAGE_PIN T20   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[12] }]; # G4
set_property -dict { PACKAGE_PIN T21   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[13] }]; # G5
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[14] }]; # G6
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[15] }]; # G7

set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[16] }]; # R0
set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[17] }]; # R1
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[18] }]; # R2
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[19] }]; # R3
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[20] }]; # R4
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[21] }]; # R5
set_property -dict { PACKAGE_PIN H18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[22] }]; # R6
set_property -dict { PACKAGE_PIN G18   IOSTANDARD LVCMOS33 } [get_ports { hdmi_d[23] }]; # R7

## I2C Configuration Bus for HDMI Transmitter
set_property -dict { PACKAGE_PIN F18   IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports { hdmi_scl }];
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports { hdmi_sda }];

## -----------------------------------------------------------------------------
## 5. UART Serial Debug Interface (Host Link)
## -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN C18   IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];
set_property -dict { PACKAGE_PIN C19   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

## -----------------------------------------------------------------------------
## 6. Synthesis / Placement Optimization Directives
## -----------------------------------------------------------------------------
## Infer DSP48E1 slices for vector dot products & multiplications
set_property USE_DSP48 "TRUE" [get_cells -hierarchical -filter {NAME =~ *alu_instance* || NAME =~ *vec_alu_instance*}]
