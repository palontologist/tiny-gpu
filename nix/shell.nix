{ pkgs ? import <nixpkgs> {} }:

# tiny-gpu HaDes-V development shell
# Provides simulation, RISC-V cross-compilation, and FPGA flashing tools.
#
# Usage:
#   nix-shell nix/shell.nix
#
# Intel Quartus Prime is NOT in nixpkgs; install it manually:
#   https://www.intel.com/content/www/us/en/products/details/fpga/development-tools/quartus-prime.html
#   then add to PATH (see shellHook below).

pkgs.mkShell {
  name = "tiny-gpu-hadesv";

  buildInputs = with pkgs; [
    # ---- Simulation ----
    iverilog           # Icarus Verilog — primary simulator (used by Makefile)
    verilator          # Fast Verilog lint / simulation
    sv2v               # SystemVerilog → Verilog for OpenLane / iverilog

    # ---- RISC-V cross-toolchain (RV32IM — matches the HaDes-V ISA) ----
    pkgsCross.riscv32.buildPackages.gcc
    pkgsCross.riscv32.buildPackages.binutils
    pkgsCross.riscv32.buildPackages.gdb

    # ---- Python (cocotb simulation harness) ----
    python3
    python3Packages.cocotb
    python3Packages.pytest

    # ---- FPGA flashing via JTAG (Intel USB Blaster) ----
    openocd

    # ---- Waveform viewer ----
    gtkwave

    # ---- Build utilities ----
    gnumake
    git
  ];

  shellHook = ''
    echo ""
    echo "  tiny-gpu HaDes-V — development environment"
    echo "  ============================================"
    echo ""
    echo "  Simulation:"
    echo "    make test_matadd    — run matrix-addition test"
    echo "    make test_matmul    — run matrix-multiplication test"
    echo "    make compile        — build Verilog artifact only"
    echo ""
    echo "  FPGA synthesis (Intel Quartus):"
    echo "    cd quartus && quartus_sh -t build.tcl"
    echo ""
    echo "  RISC-V cross-compiler:"
    echo "    riscv32-none-elf-gcc -march=rv32im -mabi=ilp32 ..."
    echo ""
    echo "  Intel Quartus Prime must be installed separately."
    echo "  After installation, add it to PATH:"
    echo "    export PATH=\$PATH:/opt/intelFPGA_lite/<version>/quartus/bin"
    echo ""

    # If Quartus is installed on the host, expose it automatically.
    for qdir in /opt/intelFPGA_lite/*/quartus/bin \
                /opt/intelFPGA/*/quartus/bin \
                $HOME/intelFPGA_lite/*/quartus/bin; do
      if [ -d "$qdir" ]; then
        export PATH="$qdir:$PATH"
        echo "  Quartus found: $qdir"
        break
      fi
    done
  '';
}
