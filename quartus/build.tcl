#!/usr/bin/env tclsh
# Intel Quartus Prime Build Script — tiny-gpu HaDes-V
#
# Usage:
#   quartus_sh -t build.tcl
#
# Requirements:
#   Intel Quartus Prime Lite (free) or Pro installed and on PATH.
#   NixOS: nix develop .#  (flake.nix in this repo)
#   Other:  export PATH=$PATH:/opt/intelFPGA_lite/<version>/quartus/bin
#
# After a successful build:
#   • Bitstream: output_files/tiny-gpu-hadesv.sof
#   • Flash via USB Blaster:
#       quartus_pgm -c "USB-Blaster" -m JTAG \
#           -o "P;output_files/tiny-gpu-hadesv.sof@1"
#
# Intel FPGA board support:
#   Cyclone V  (DE0-CV / DE1-SoC)   — current default, ~$100
#   Arria 10   (Arrow DECA)          — change DEVICE in gpu.qsf
#   Agilex 7   (Intel Dev Kit)       — change FAMILY/DEVICE in gpu.qsf,
#                                      uncomment AI_TENSOR_ACCEL_ENABLE

package require ::quartus::project
package require ::quartus::flow

set project_name "tiny-gpu-hadesv"
set script_dir   [file dirname [info script]]

# ---- Open or create project ----
if {![project_exists $project_name]} {
    project_new $project_name -revision $project_name
} else {
    project_open $project_name -revision $project_name
}

# Load QSF settings
source [file join $script_dir gpu.qsf]

# ---- Full compilation flow ----
#   Analysis & Synthesis → Fitter → Assembler → Timing Analyser
if {[catch {execute_flow -compile} result]} {
    post_message -type error "Compilation failed: $result"
    project_close
    exit 1
}

# ---- Static Timing Analysis ----
if {[catch {execute_module -tool sta} sta_result]} {
    post_message -type warning "Timing analysis warnings: $sta_result"
}

# ---- Report summary ----
post_message "Build complete."
post_message "  Bitstream : output_files/${project_name}.sof"
post_message "  Reports   : output_files/*.rpt"
post_message ""
post_message "To flash (USB Blaster):"
post_message "  quartus_pgm -c USB-Blaster -m JTAG \\"
post_message "    -o P;output_files/${project_name}.sof@1"

project_close
