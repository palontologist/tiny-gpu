# ==============================================================================
# Vivado Non-Project Batch Synthesis & Implementation Script for tiny-gpu
# Target Part: AMD Xilinx Artix-7 (xc7a100tfgg484-2)
# ==============================================================================

set TOP_MODULE "top_artix7"
set PART_NAME  "xc7a100tfgg484-2"
set OUTPUT_DIR "./build_vivado"

# Clean and initialize output directory
file mkdir $OUTPUT_DIR

puts "======================================================================"
puts " Starting Vivado Synthesis for tiny-gpu (Part: $PART_NAME)"
puts "======================================================================"

# 1. Read SystemVerilog Source Files
set SRC_FILES [list \
    "../src/alu.sv" \
    "../src/vec_alu.sv" \
    "../src/decoder.sv" \
    "../src/fetcher.sv" \
    "../src/pc.sv" \
    "../src/registers.sv" \
    "../src/vreg.sv" \
    "../src/lsu.sv" \
    "../src/l1_cache.sv" \
    "../src/rob.sv" \
    "../src/scheduler.sv" \
    "../src/core.sv" \
    "../src/dispatch.sv" \
    "../src/controller.sv" \
    "../src/dcr.sv" \
    "../src/rasterizer.sv" \
    "../src/texture_unit.sv" \
    "../src/framebuffer_if.sv" \
    "../src/gpu.sv" \
    "./top_artix7.sv" \
]

foreach src $SRC_FILES {
    if {[file exists $src]} {
        read_verilog -sv $src
        puts "Loaded SystemVerilog source: $src"
    } else {
        puts "WARNING: Source file not found: $src"
    }
}

# 2. Read Physical and Timing Constraints
if {[file exists "./tiny_gpu.xdc"]} {
    read_xdc "./tiny_gpu.xdc"
    puts "Loaded XDC Constraints: ./tiny_gpu.xdc"
}

# 3. Run Synthesis
puts "\n--> Running Synthesis..."
synth_design -top $TOP_MODULE -part $PART_NAME -directive Default \
    -verilog_define {VECTOR_ENABLE=1} \
    -verilog_define {NUM_CORES=2} \
    -verilog_define {THREADS_PER_BLOCK=4}

write_checkpoint -force "$OUTPUT_DIR/post_synth.dcp"
report_utilization -file "$OUTPUT_DIR/synth_utilization.rpt"
report_timing_summary -file "$OUTPUT_DIR/synth_timing.rpt"

# 4. Logic Optimization & Placement
puts "\n--> Running Logic Optimization & Placement..."
opt_design
place_design
write_checkpoint -force "$OUTPUT_DIR/post_place.dcp"
report_clock_utilization -file "$OUTPUT_DIR/clock_util.rpt"

# 5. Routing & Physical Optimization
puts "\n--> Running Physical Optimization & Routing..."
phys_opt_design
route_design
write_checkpoint -force "$OUTPUT_DIR/post_route.dcp"

# 6. Final Timing, DRC, and Utilization Reports
puts "\n--> Generating Final Physical Reports..."
report_timing_summary -max_paths 10 -file "$OUTPUT_DIR/timing_summary.rpt"
report_utilization -file "$OUTPUT_DIR/utilization_summary.rpt" -hierarchical
report_power -file "$OUTPUT_DIR/power_analysis.rpt"
report_drc -file "$OUTPUT_DIR/drc_report.rpt"

# Check Worst Negative Slack (WNS) for timing closure
set wns [get_property SLACK [get_timing_paths]]
puts "======================================================================"
puts " Synthesis & Implementation Complete!"
puts " Final Worst Negative Slack (WNS): $wns ns"
if {$wns < 0} {
    puts " WARNING: Timing violations detected! Review $OUTPUT_DIR/timing_summary.rpt"
} else {
    puts " SUCCESS: Timing closed successfully!"
}
puts " Detailed reports written to: $OUTPUT_DIR/"
puts "======================================================================"

# 7. Generate Bitstream
puts "\n--> Generating FPGA Bitstream..."
write_bitstream -force "$OUTPUT_DIR/tiny_gpu_top.bit"
puts "Bitstream generated: $OUTPUT_DIR/tiny_gpu_top.bit"
