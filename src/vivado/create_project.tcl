# create_project.tcl
# Vivado project creation script for Simple-Net FPGA Object Detection
#
# Usage:
#   cd SIMPLE_NET
#   vivado -mode batch -source vivado/create_project.tcl
#
# Or from Vivado GUI:
#   Tools -> Run Tcl Script -> select this file
#
# This script:
#   1. Creates a new Vivado project
#   2. Sets the target FPGA part
#   3. Adds all RTL source files
#   4. Adds all simulation files
#   5. Adds constraint files
#   6. Adds weight memory files
#   7. Configures the Clock Wizard IP
#   8. Prints instructions for MIG IP setup
#
# After running this script, you still need to:
#   1. Generate the MIG IP core (see instructions printed at end)
#   2. Generate the Clock Wizard IP (see instructions printed at end)
#   3. Run Synthesis
#   4. Run Implementation
#   5. Generate Bitstream
#   6. Program the FPGA


# PROJECT SETTINGS
set project_name "simple_net"
set project_dir  "./simple_net"
set part         "xc7s50csga324-1"
set board_part   ""

# Resolve script directory to find source files
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/.."]

puts "============================================================"
puts "  Simple-Net: Creating Vivado Project"
puts "============================================================"
puts "  Project:  $project_name"
puts "  Part:     $part"
puts "  Root:     $repo_root"
puts "============================================================"


# CREATE PROJECT
if {[file exists $project_dir]} {
    puts "Removing existing project directory..."
    file delete -force $project_dir
}

create_project $project_name $project_dir -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]


# ADD RTL SOURCE FILES
puts "\nAdding RTL sources..."

# Clocking
add_files -norecurse [glob -nocomplain $repo_root/src/rtl/clocking/*.sv]

# Utils
add_files -norecurse [glob -nocomplain $repo_root/src/rtl/utils/*.sv]

# Memory
add_files -norecurse [glob -nocomplain $repo_root/src/rtl/memory/*.sv]

# Camera
add_files -norecurse [glob -nocomplain $repo_root/src/rtl/camera/*.sv]

# Video
add_files -norecurse [glob -nocomplain $repo_root/src/rtl/video/*.sv]

# Downsampler
add_files -norecurse [glob -nocomplain $repo_root/src/rtl/downsampler/*.sv]

# CNN
add_files -norecurse [glob -nocomplain $repo_root/src/rtl/cnn/*.sv]

# Top level
add_files -norecurse $repo_root/src/rtl/top_simple_net.sv

# Set top module
set_property top top_simple_net [current_fileset]

set src_count [llength [get_files -of_objects [get_filesets sources_1]]]
puts "  Added $src_count source files"
puts "  Top module: top_simple_net"


# ADD SIMULATION FILES
puts "\nAdding simulation sources..."

if {[string equal [get_filesets -quiet sim_1] ""]} {
    create_fileset -simset sim_1
}

set sim_files [glob -nocomplain $repo_root/sim/*.sv]
if {[llength $sim_files] > 0} {
    add_files -fileset sim_1 -norecurse $sim_files
}

set_property top tb_top_simple_net [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

set sim_count [llength [get_files -of_objects [get_filesets sim_1]]]
puts "  Added $sim_count simulation files"
puts "  Top testbench: tb_top_simple_net"


# ADD CONSTRAINT FILES
puts "\nAdding constraints..."

if {[string equal [get_filesets -quiet constrs_1] ""]} {
    create_fileset -constrset constrs_1
}

add_files -fileset constrs_1 -norecurse $repo_root/src/constraints/urbana_s7.xdc
set_property used_in_synthesis true  [get_files urbana_s7.xdc]
set_property used_in_implementation true [get_files urbana_s7.xdc]

puts "  Added urbana_s7.xdc"


# ADD WEIGHT MEMORY FILES
puts "\nAdding weight memory files..."

set mem_files [glob -nocomplain $repo_root/weights/*.mem]
if {[llength $mem_files] > 0} {
    add_files -norecurse $mem_files

    foreach mem_file $mem_files {
        set fname [file tail $mem_file]
        set_property used_in_synthesis true [get_files $fname]
        set_property used_in_simulation true [get_files $fname]
    }

    puts "  Added [llength $mem_files] weight files:"
    foreach mem_file $mem_files {
        puts "    [file tail $mem_file]"
    }
} else {
    puts "  WARNING: No .mem files found in weights/"
    puts "  Run the training pipeline to generate them:"
    puts "    cd software/train/tools"
    puts "    python train.py"
    puts "    python quantize.py"
    puts "    python export_weights.py"
}


# CONFIGURE SIMULATION
puts "\nConfiguring simulation..."

set_property -name {xsim.simulate.runtime} -value {500ms} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

set_property -name {xsim.elaborate.xelab.more_options} \
    -value "--generic_top tb_top_simple_net" \
    -objects [get_filesets sim_1]


# CONFIGURE SYNTHESIS
puts "\nConfiguring synthesis..."

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]


# CONFIGURE IMPLEMENTATION
puts "\nConfiguring implementation..."

set_property strategy Performance_Auto [get_runs impl_1]
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]


# CREATE CLOCK WIZARD IP
puts "\nCreating Clock Wizard IP..."

if {[llength [get_ips -quiet clk_wiz_0]] == 0} {
    create_ip -name clk_wiz -vendor xilinx.com -library ip \
        -version 6.0 -module_name clk_wiz_0

    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.000} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {25.000} \
        CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {125.000} \
        CONFIG.CLKOUT2_USED {true} \
        CONFIG.CLKOUT3_USED {true} \
        CONFIG.NUM_OUT_CLKS {3} \
        CONFIG.CLKIN1_JITTER_PS {100.0} \
        CONFIG.MMCM_CLKFBOUT_MULT_F {10.000} \
        CONFIG.MMCM_CLKIN1_PERIOD {10.000} \
        CONFIG.MMCM_CLKOUT0_DIVIDE_F {41.667} \
        CONFIG.MMCM_CLKOUT1_DIVIDE {40} \
        CONFIG.MMCM_CLKOUT2_DIVIDE {8} \
        CONFIG.RESET_TYPE {ACTIVE_HIGH} \
        CONFIG.RESET_PORT {reset} \
        CONFIG.LOCKED_PORT {locked} \
        CONFIG.CLK_OUT1_PORT {clk_out1} \
        CONFIG.CLK_OUT2_PORT {clk_out2} \
        CONFIG.CLK_OUT3_PORT {clk_out3} \
    ] [get_ips clk_wiz_0]

    generate_target all [get_ips clk_wiz_0]
    puts "  Clock Wizard IP created and configured"
    puts "    clk_out1: 24 MHz (camera XCLK)"
    puts "    clk_out2: 25 MHz (HDMI pixel clock)"
    puts "    clk_out3: 125 MHz (HDMI serializer)"
} else {
    puts "  Clock Wizard IP already exists -- skipping"
}


# COMPLETION SUMMARY
puts "\n============================================================"
puts "  PROJECT CREATED SUCCESSFULLY"
puts "============================================================"
puts ""
puts "  Project location: [file normalize $project_dir]"
puts ""
puts "  REMAINING MANUAL STEPS:"
puts ""
puts "  1. CREATE MIG IP (DDR3 Controller):"
puts "     a. Open the project in Vivado GUI"
puts "     b. IP Catalog -> search 'MIG'"
puts "     c. Select 'Memory Interface Generator (MIG 7 Series)'"
puts "     d. Configure:"
puts "        - Component Name: mig_7series_0"
puts "        - Memory Type: DDR3 SDRAM"
puts "        - Data Width: 16"
puts "        - Memory Part: select your board's DDR3 chip"
puts "          (check Urbana board schematic)"
puts "        - UI Clock: check 'Additional Clocks' if needed"
puts "        - System Clock: No Buffer (we feed it directly)"
puts "        - Reference Clock: Use System Clock"
puts "     e. Complete the wizard and generate the IP"
puts ""
puts "  2. VERIFY CLOCK WIZARD:"
puts "     The clk_wiz_0 IP has been auto-created with:"
puts "       Input:  100 MHz"
puts "       Out 1:  24 MHz  (camera)"
puts "       Out 2:  25 MHz  (HDMI pixel)"
puts "       Out 3:  125 MHz (HDMI serial)"
puts "     Open IP and verify MMCM settings if needed."
puts ""
puts "  3. GENERATE WEIGHT FILES (if not done):"
puts "     cd software/train/tools"
puts "     python train.py"
puts "     python quantize.py"
puts "     python export_weights.py"
puts ""
puts "  4. BUILD:"
puts "     a. Run Synthesis"
puts "     b. Run Implementation"
puts "     c. Generate Bitstream"
puts "     d. Program FPGA"
puts ""
puts "  5. SIMULATION (optional):"
puts "     a. Set sim_1 as active"
puts "     b. Top module: tb_top_simple_net"
puts "     c. Run Behavioral Simulation"
puts "     Note: MIG is stubbed in testbench with behavioral model"
puts ""
puts "============================================================"
puts "  Resource Estimate:"
puts "    DSP48:  70-90 of 120  (CNN MAC operations)"
puts "    BRAM:   ~215 KB of 338 KB"
puts "      DDR3 Controller:  ~15 KB"
puts "      Video Pipeline:   ~40 KB"
puts "      CNN Engine:       ~160 KB"
puts "    Free Margin:        ~120 KB BRAM, ~30 DSP48"
puts "============================================================"