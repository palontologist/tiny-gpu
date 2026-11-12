# tinygpu runtime scaffold

A minimal, backend-pluggable runtime and codegen scaffold for running kernels on **tiny-gpu** (RTL sim, FPGA, future unified RISC-V CPU/GPU).

## Structure
- `device.py` — `Device` interface (caps, alloc/free, copy, compile, launch, sync)
- `buffer.py`, `kernel.py` — core types
- `backends/sim.py` — simulator backend stub (hook into `test/` cocotb harness or a functional ISA sim)
- `codegen.py` — lowering stubs (emit RV32IM / CUSTOM1 / CUSTOM2 instruction words)
- `../examples/tinygpu/vector_add.py` — end-to-end example (scaffold)

## Goals
- **Portable:** same API across sim, FPGA, and future silicon.
- **Capability-driven:** query vector width, dtypes, cores/threads at runtime.
- **Unified-memory ready:** design for a single address space as the hardware evolves.

## Next steps
1. Implement `SimulatorDevice` by reusing logic from `test/test_matadd.py` (program/data memory setup, launch, readback).
2. Add an instruction encoder (or reuse `test/helpers/rv32i.py`) in `codegen.py`.
3. Add a fast functional ISA simulator backend for iteration without iverilog.
4. Define a host↔FPGA transport backend matching the Artix-7 board.
