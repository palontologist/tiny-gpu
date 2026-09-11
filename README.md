# tiny-gpu

A RISC-V-based GPU implementation in Verilog designed to explore and implement high-performance GPU architectures—from scalar cores and vector SIMD to cache hierarchies and graphics rasterization.

Built with ~20 files of fully documented Verilog, the project evolves through 7 development milestones: RV32IM scalar core, INT4/FP32 ML extensions, sparsity-aware execution, out-of-order ROB, L1 cache, graphics pipeline, and 128-bit vector SIMD. It includes verified matrix addition/multiplication and vector kernels with full simulation and execution traces.

### Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [GPU](#gpu)
  - [Memory](#memory)
  - [Core](#core)
- [Hardware Implementation](#hardware-implementation)
- [ISA](#isa)
  - [Base RV32IM](#base-rv32im)
  - [Custom Extensions](#custom-extensions)
  - [Register File](#register-file)
- [Execution](#execution)
  - [Pipeline Stages](#pipeline-stages)
  - [Out-of-Order Execution](#out-of-order-execution)
  - [Sparsity-Aware Execution](#sparsity-aware-execution)
  - [Thread](#thread)
- [Kernels](#kernels)
  - [Matrix Addition](#matrix-addition-rv32i)
  - [Matrix Multiplication](#matrix-multiplication-rv32im)
  - [Vector DP4A](#vector-dp4a-phase-7--custom2)
- [Simulation](#simulation)
- [Optimizations](#optimizations)
  - [Implemented](#implemented-optimizations)
  - [Future](#future-optimizations)
- [Unified CPU/GPU Architecture (Approach B: RVV) & Modular Extensibility](#unified-cpugpu-architecture-approach-b-rvv--modular-extensibility)
- [Next Steps](#next-steps)

# Overview

While there are many resources for learning CPU architecture, GPU internals remain largely proprietary and opaque. Open-source implementations like [Miaow](https://github.com/VerticalResearchGroup/miaow) and [VeriGPU](https://github.com/hughperkins/VeriGPU/tree/main) are excellent but highly complex.

`tiny-gpu` is designed to bridge this gap, providing a transparent and modular reference implementation of a GPU's core logic.

## What is tiny-gpu?

> [!IMPORTANT]
> **tiny-gpu** is a RISC-V-based GPU implementation focused on the fundamental principles of GPGPU and ML-accelerator architectures. It emphasizes the general mechanisms of data parallelism and memory throughput rather than graphics-specific hardware.

The project is structured into 7 development milestones:

- **Phase 1**: RV32IM scalar core (RISC-V base ISA)
- **Phase 2**: INT4/FP32 custom extensions for ML inference
- **Phase 3**: Sparsity-aware execution (zero-skip for power efficiency)
- **Phase 4**: Out-of-order execution with Tomasulo-style ROB
- **Phase 5**: Per-thread L1 data cache (2-way set-associative)
- **Phase 6**: Graphics pipeline (rasterizer + texture unit + framebuffer)
- **Phase 7**: 128-bit vector extensions (INT8/INT4 SIMD, FP32 stubs)

The project explores four primary domains:
1. **Architecture** - Defining the core elements of a GPU and their interconnections.
2. **Parallelization** - Implementing the SIMD programming model in hardware.
3. **Memory** - Managing bandwidth constraints and latency via caching.
4. **ML Acceleration** - Utilizing vector units and quantization for efficient inference.

# Architecture

![Architecture](/docs/images/architecture.png)

## GPU

`tiny-gpu` executes a single kernel at a time through the following process:
1. Load global program memory with kernel code (32-bit RV32IM instructions).
2. Load data memory with the necessary data (32-bit scalar or 128-bit vector).
3. Specify the thread count in the device control register.
4. Launch the kernel via the start signal.

The GPU architecture consists of:
1. Device control register
2. Dispatcher
3. Compute cores (each containing a ROB, L1 cache, and vector units)
4. Memory controllers for data and program memory
5. L1 data cache (per-thread, 2-way set-associative)

### GPU Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_CORES` | 2 | Number of compute cores |
| `THREADS_PER_BLOCK` | 4 | SIMD width per core |
| `ROB_DEPTH` | 16 | Reorder buffer entries per core |
| `L1_SETS` | 16 | L1 cache sets per thread |
| `VECTOR_ENABLE` | 1 | 128-bit data bus (0 = 32-bit legacy) |

### Device Control Register
The device control register stores metadata for kernel execution, primarily the `thread_count`—the total number of threads launched for the active kernel.

### Dispatcher
The dispatcher manages the distribution of threads to compute cores. It organizes threads into **blocks** and assigns them to available cores. Once all blocks are processed, the dispatcher signals kernel completion.

## Memory

`tiny-gpu` interfaces with an external global memory, separating data and program memory for architectural simplicity.

### Global Memory
- **Data Memory:** 8-bit addressability (256 word-addressable rows). Supports 32-bit scalar data or 128-bit vector data (when `VECTOR_ENABLE=1`).
- **Program Memory:** 8-bit addressability (256 word-addressable rows) storing 32-bit RV32IM instructions.

### Memory Controllers
The memory controllers manage outgoing requests from the compute cores, throttling access based on external memory bandwidth and relaying responses back to the requesting resource.

### L1 Data Cache
To mitigate global memory latency, each thread utilizes a **private L1 data cache** (Phase 5):
- **Organization:** 2-way set-associative (16 sets by default).
- **Policy:** Write-through (no dirty bits required).
- **Latency:** 1 cycle hit; memory-controller round-trip + 1 fill cycle for misses.
- **Replacement:** LRU (Least Recently Used) policy per set.

## Core

Each core manages a block of threads. To maximize resource utilization, the core provides a dedicated ALU, LSU, PC, scalar/vector register files, and L1 cache for each thread.

### Scheduler
A single scheduler manages the execution of threads through a 7-stage pipeline. The scheduler executes one block to completion, processing all threads in-sync and sequentially.

- **Sparsity-Aware Execution (Phase 3):** If all threads in a warp have zero-valued operands for an ALU operation, the scheduler skips the EXECUTE stage and writes zero directly to save power and cycles.
- **ROB Hazard Management (Phase 4):** Before advancing past the REQUEST stage, the scheduler checks for unresolved in-flight writes in the ROB. The pipeline stalls until the hazard clears or the value is forwarded.

### Reorder Buffer (ROB)
Phase 4 introduces a Tomasulo-style ROB for out-of-order execution:
- **In-order allocation** at the tail, **in-order commit** at the head.
- **Out-of-order writeback** upon execution unit completion.
- **Hazard detection** and **Result forwarding** to minimize pipeline stalls.

Each ROB entry covers one warp-level instruction, storing per-thread result data for SIMD execution.

### Fetcher
Asynchronously fetches 32-bit instructions from program memory based on the current PC.

### Decoder
Decodes RV32IM instructions into control signals, including:
- **Standard RV32I** opcodes.
- **RV32M** multiply/divide extensions.
- **Custom Opcodes:** `CUSTOM0` (RET), `CUSTOM1` (INT4/FP32), `CUSTOM2` (128-bit vector SIMD).

### Register Files
- **Scalar Registers (RV32):** 32 × 32-bit registers (x0-x31). x0 is hardwired to zero; x13-x15 are read-only special registers (`%blockIdx`, `%blockDim`, `%threadIdx`).
- **Vector Registers (Phase 7):** 16 × 128-bit registers (v0-v15). v0 is hardwired to zero; v13-v15 mirror scalar special registers.

### ALUs
Dedicated arithmetic-logic units per thread for scalar computations:
- **RV32I/M:** Full integer and multiply/divide support.
- **Custom (Phase 2/6):** `DP4A` (INT4 dot-product accumulate) and FP32 stubs.

### Vector ALUs (Phase 7)
Dedicated 128-bit vector ALUs for packed SIMD operations:
- **INT8:** 16-lane add, multiply, and multiply-accumulate.
- **INT4:** 4 × (8 × INT4 signed DP4A) for 32-bit accumulation.
- **FP32:** 4-lane add, multiply, and FMA (stubs).

### LSUs
Load-Store Units manage access to global data memory, supporting standard RV32I operations and Phase 7 vector extensions (`VLW.Q`, `VSW.Q` for 128-bit quad-word transfers).

### PCs
Dedicated program counters per thread. The PC increments by 4 for standard instructions or jumps to target addresses during branch/jump operations.

### Graphics Pipeline (Phase 6)
- **Rasterizer:** Scan-line tile rasterizer with barycentric interpolation (16.16 fixed-point).
- **Texture Unit:** Bilinear filtering with INT8 texels (8.8 fixed-point UV).
- **Framebuffer Interface:** Connects rasterizer output to display memory.

# Hardware Implementation

To move `tiny-gpu` from simulation to physical hardware, a custom carrier board has been designed. All design files, schematics, and assembly guides can be found in the [`/fpga_carrier_board_files`](/home/palontologist/Downloads/dev/tiny-gpu/fpga_carrier_board_files) directory.

### Target Platform
- **FPGA:** AMD Xilinx Artix-7 (XC7A100T-2FGG484I)
- **Memory:** DDR3L x16 (MT41K256M16TW-107:P) for high-bandwidth data access.
- **Video Output:** HDMI 1.4 via SII9022A transmitter.
- **Power:** USB-C PD input with multi-rail voltage regulation (1.0V, 1.8V, 1.35V, 3.3V).

### Design Workflow
The PCB was developed using a code-first approach via **Solder CLI**, allowing for rapid iteration of the 128-bit memory bus and signal integrity optimization. The final design is compatible with KiCad.

### Assembly & Bring-up
A detailed assembly guide (`fpga_carrier_board_GUIDE.md`) is provided, covering the 3D printing of enclosure mounts, BGA soldering of the FPGA and RAM, and the step-by-step bring-up process using a JTAG debugger.

# ISA

![ISA](/docs/images/isa.png)

The architecture implements the **RV32IM** base ISA with custom extensions for GPU and ML workloads.

## Base RV32IM
Full support for standard RISC-V integer (`I`) and multiply/divide (`M`) instructions (LUI, AUIPC, JAL, JALR, BRANCH, LOAD, STORE, OP-IMM, OP, SYSTEM, MUL, DIV, etc.).

## Custom Extensions

| Opcode | Name | Description |
|--------|------|-------------|
| `CUSTOM0` | `RET` | Return from kernel execution |
| `CUSTOM1` | `DP4A` | INT4 4-element dot product with 32-bit accumulation |
| `CUSTOM1` | `FADD` / `FMUL` / `FFMA` | Single-precision floating point arithmetic stubs |
| `CUSTOM2` | `VADD` / `VMUL` / `VMAC` | 128-bit packed INT8 vector operations |
| `CUSTOM2` | `VDP4A` | 128-bit packed INT4 dot product accumulate |
| `CUSTOM2` | `VLW.Q` / `VSW.Q` | 128-bit vector quad-word memory load/store |

## Register File

- **Scalar Registers:** 32 registers (`x0` through `x31`).
  - `x0`: Constant 0
  - `x13`: Read-only `%blockIdx`
  - `x14`: Read-only `%blockDim`
  - `x15`: Read-only `%threadIdx`
- **Vector Registers:** 16 registers (`v0` through `v15`), each 128 bits wide.

# Execution

## Pipeline Stages

The execution pipeline consists of 7 stages:
1. **FETCH:** Retrieve instruction from program memory.
2. **DECODE:** Decode instruction and identify operand registers.
3. **REQUEST:** Issue memory requests or check for ROB hazards.
4. **WAIT:** Wait for memory data or hazard clearance.
5. **EXECUTE:** Compute ALU / Vector / Branch results (or perform zero-skip).
6. **UPDATE:** Update PC, write back results to register file or ROB.
7. **COMMIT:** In-order commit from ROB to architectural state.

## Out-of-Order Execution
Supported via Tomasulo-style Reorder Buffer (ROB) tracking in-flight instructions, resolving RAW hazards, and enabling speculative result forwarding.

## Sparsity-Aware Execution
Skips the execute stage when operands are detected as zero, directly writing zero to destination registers and cutting dynamic power consumption.

## Thread
Threads execute in SIMD blocks where each lane shares instruction flow but maintains private register and cache state.

# Kernels

### Matrix Addition (RV32I)
Demonstrates standard RISC-V scalar instructions distributed across threads to compute element-wise addition over matrix buffers.

### Matrix Multiplication (RV32IM)
Leverages RV32M hardware multiplier extensions for high-throughput tile-based matrix multiplication.

### Vector DP4A (Phase 7 / CUSTOM2)
Utilizes 128-bit vector units to compute quantized INT4 dot products with 32-bit accumulation for neural network linear layers.

# Simulation

### Prerequisites
- `iverilog` (Icarus Verilog)
- Python 3 & `cocotb`
- `gnumake`

```bash
# Using Nix
nix-shell -p iverilog python3 python3Packages.cocotb gnumake
```

### Run Tests
```bash
make test_matadd    # Scalar matrix addition
make test_matmul    # Scalar matrix multiplication + vector DP4A
```

# Optimizations

### Implemented Optimizations
- **INT4 Quantization:** Efficient ML inference with reduced precision.
- **Sparsity-Aware Skip:** Dynamic power optimization for zero operands.
- **Tomasulo ROB:** Dynamic out-of-order execution with result forwarding.
- **Per-Thread L1 Cache:** Mitigates global memory latency.
- **Vector SIMD:** 128-bit data bus with packed INT8/INT4 and FP32 stubs.

### Future Optimizations
- **Warp Scheduling:** Implement multi-warp concurrency per core.
- **Branch Divergence:** Handle divergent execution paths.
- **FP32 Silicon:** Replace stubs with IEEE-754 compliant FP IP.
- **Physical Bring-up:** Finalize fabrication and test the `tiny-gpu` on the custom Artix-7 carrier board.

# Unified CPU/GPU Architecture (Approach B: RVV) & Modular Extensibility

As `tiny-gpu` evolves, the architectural roadmap moves toward a **Unified RISC-V CPU/GPU Architecture** based on the standard **RISC-V Vector Extension (RVV 1.0)** and **Simple-V** dynamic vectorization.

### Why Unified RVV (Approach B)?
- **Vector-Length Agnostic (VLA):** Binary executables automatically scale across hardware vector widths ($VLEN$) without recompilation.
- **Standard Toolchains:** Upstream LLVM and GCC support, eliminating proprietary SIMT compiler forks.
- **Vulkan / SPIR-V Support:** Seamless translation of graphics shaders directly into standard vector instructions.

### Modular Extensibility & eGPU Scaling
- **Seamless Laptop-to-eGPU Offloading:** Identical binaries run locally on a low-power laptop core ($VLEN=128\text{b}$) and scale effortlessly to an external accelerator ($VLEN=2048\text{b}\text{ to }4096\text{b}$).
- **Coherent Interconnects:** Interfacing over CXL.mem/CXL.cache or TileLink/PCIe eliminates explicit PCIe data copies (`cudaMemcpy`) in favor of unified virtual memory.

📖 **Detailed Architectural Specification:** For the complete design document, pipeline diagrams, and roadmap, see [`docs/unified-cpu-gpu-rvv.md`](docs/unified-cpu-gpu-rvv.md).

## Next Steps
Contributors are welcome to help with the TODO list or submit PRs for new optimizations!
