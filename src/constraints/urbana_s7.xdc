## ============================================================
## Simple-Net: FPGA Object Detection
## Master Constraints File (Final)
## Board: Real Digital Urbana (Spartan-7 XC7S50)
## ============================================================
##
## Pin assignments for all phases:
##   Phase 0: System clock, debug LEDs
##   Phase 1: DDR3 (handled by MIG IP)
##   Phase 2: OV7670 camera (PMOD A + B)
##   Phase 3: HDMI video output
##   Phase 6: Final timing constraints
##
## NOTE: DDR3 pins are NOT constrained here.
## The MIG IP wizard generates its own constraints
## automatically. Do NOT manually constrain DDR3
## pins when using MIG.


## ============================================================
## PHASE 0: System Clock (100 MHz onboard oscillator)
## ============================================================

set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]


## ============================================================
## PHASE 0: Debug LEDs
## ============================================================
## LED[0]: PLL locked
## LED[1]: DDR3 calibration complete
## LED[2]: CNN busy
## LED[3]: Detection valid

set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {debug_led[0]}]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {debug_led[1]}]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports {debug_led[2]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {debug_led[3]}]


## ============================================================
## PHASE 0: Configuration
## ============================================================

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]


## ============================================================
## PHASE 1: DDR3 Memory Hub
## ============================================================
## DDR3 pins are handled by MIG IP — it generates its own
## constraints automatically. Do NOT manually constrain DDR3
## pins when using MIG. The MIG wizard reads the board info
## and produces a separate .xdc file.


## ============================================================
## PHASE 2: OV7670 Camera
## ============================================================
## Camera data bus via PMOD A connector:
##   JA1_P (F14) -> cam_data[0]
##   JA1_N (F15) -> cam_data[1]
##   JA2_P (H13) -> cam_data[2]
##   JA2_N (H14) -> cam_data[3]
##   JA3_P (J13) -> cam_data[4]
##   JA3_N (J14) -> cam_data[5]
##   JA4_P (E14) -> cam_data[6]
##   JA4_N (E15) -> cam_data[7]
##
## Camera control signals via PMOD B connector:
##   JB1_P (H18) -> cam_pclk   (pixel clock input from camera)
##   JB1_N (G18) -> cam_xclk   (24 MHz clock output to camera)
##   JB3_P (H16) -> cam_vsync  (vertical sync)
##   JB3_N (H17) -> cam_href   (horizontal reference)
##   JB4_P (K16) -> cam_sioc   (SCCB/I2C clock)
##   JB4_N (J16) -> cam_siod   (SCCB/I2C data, bidirectional)

# Camera data bus [7:0]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {cam_data[0]}]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports {cam_data[1]}]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports {cam_data[2]}]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports {cam_data[3]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {cam_data[4]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {cam_data[5]}]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports {cam_data[6]}]
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports {cam_data[7]}]

# Camera control signals
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33} [get_ports cam_pclk]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports cam_xclk]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports cam_vsync]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports cam_href]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports cam_sioc]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports cam_siod]

# Camera pixel clock constraint
# OV7670 PCLK is typically 12 MHz (for QVGA) or 24 MHz (for VGA)
# Using 83.333ns period = 12 MHz as conservative estimate
create_clock -period 83.333 -name cam_pclk [get_ports cam_pclk]

# SCCB data line needs pullup for I2C operation
set_property PULLUP TRUE [get_ports cam_siod]


## ============================================================
## PHASE 3: HDMI Video Output
## ============================================================
## HDMI uses TMDS differential signaling.
## 4 differential pairs: 3 data channels + 1 clock channel
##
## Channel mapping:
##   D0 (Blue + sync): U17/U18
##   D1 (Green):       R16/R17
##   D2 (Red):         R14/T14
##   CLK:              U16/V17

set_property -dict {PACKAGE_PIN U17 IOSTANDARD TMDS_33} [get_ports hdmi_d0_p]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD TMDS_33} [get_ports hdmi_d0_n]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD TMDS_33} [get_ports hdmi_d1_p]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD TMDS_33} [get_ports hdmi_d1_n]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD TMDS_33} [get_ports hdmi_d2_p]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD TMDS_33} [get_ports hdmi_d2_n]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD TMDS_33} [get_ports hdmi_clk_p]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD TMDS_33} [get_ports hdmi_clk_n]


## ============================================================
## PHASE 6: Clock Domain Crossing Constraints
## ============================================================
## These false paths prevent the timing analyzer from trying
## to meet timing on paths that cross clock domains. The actual
## synchronization is handled by double-FF synchronizers and
## async FIFOs in the RTL.

# Camera pixel clock is asynchronous to all generated clocks
set_clock_groups -asynchronous \
    -group [get_clocks cam_pclk] \
    -group [get_clocks -of_objects [get_pins u_clk_gen/u_clk_wiz/clk_out1]] \
    -group [get_clocks -of_objects [get_pins u_clk_gen/u_clk_wiz/clk_out2]] \
    -group [get_clocks -of_objects [get_pins u_clk_gen/u_clk_wiz/clk_out3]]

# MIG ui_clk is asynchronous to pixel clock and camera clock
# (MIG generates its own clock from sys_clk via internal PLL)
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins u_mig/u_mig_7series_0_mig/u_ddr3_infrastructure/gen_mmcm.mmcm_i/CLKFBOUT]] \
    -group [get_clocks cam_pclk]

# False path on double-FF synchronizers for detection results
# These signals change once per frame (~16ms) and are stable
# for millions of clock cycles before being sampled.
set_false_path -from [get_cells {detect_x_ui_reg[*]}] \
               -to   [get_cells {detect_x_px_reg[*]}]
set_false_path -from [get_cells {detect_y_ui_reg[*]}] \
               -to   [get_cells {detect_y_px_reg[*]}]
set_false_path -from [get_cells {detect_conf_ui_reg[*]}] \
               -to   [get_cells {detect_conf_px_reg[*]}]
set_false_path -from [get_cells {detect_valid_ui_reg}] \
               -to   [get_cells {detect_valid_px_reg}]

# False path on frame buffer selection (changes once per frame)
set_false_path -from [get_cells {write_buf_sel_reg}] \
               -to   [get_cells {cam_fb_base_reg[*]}]

# False path on frame_start synchronizer chain
set_false_path -from [get_cells {u_capture/frame_start_reg}] \
               -to   [get_cells {frame_start_sync1_reg}]


## ============================================================
## PHASE 6: Timing Exceptions
## ============================================================

# SCCB runs at ~100 kHz — no tight timing needed
# The 24 MHz clock drives it with large margin
set_false_path -from [get_clocks -of_objects [get_pins u_clk_gen/u_clk_wiz/clk_out1]] \
               -to   [get_ports cam_sioc]
set_false_path -from [get_clocks -of_objects [get_pins u_clk_gen/u_clk_wiz/clk_out1]] \
               -to   [get_ports cam_siod]

# Debug LEDs are human-visible — no timing concern
set_false_path -to [get_ports {debug_led[*]}]


## ============================================================
## PHASE 6: Physical Constraints
## ============================================================

# Place the clock generator PLL near the clock input pin
# for best jitter performance (optional, Vivado usually does well)
# set_property LOC MMCME2_ADV_X0Y0 [get_cells u_clk_gen/u_clk_wiz/mmcm_adv_inst]

# HDMI serializers should be placed near the output pins
# to minimize skew between channels (optional)
# set_property IOB TRUE [get_ports hdmi_d0_p]
# set_property IOB TRUE [get_ports hdmi_d1_p]
# set_property IOB TRUE [get_ports hdmi_d2_p]
# set_property IOB TRUE [get_ports hdmi_clk_p]


## ============================================================
## PHASE 6: Bitstream Settings
## ============================================================

# SPI flash programming settings (for persistent configuration)
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]

# Internal voltage reference (reduces external component count)
set_property INTERNAL_VREF 0.675 [get_iobanks 34]