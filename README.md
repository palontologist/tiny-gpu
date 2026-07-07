# tiny-gpu

A RISC-V-based GPU implementation in Verilog designed to explore and implement high-performance GPU architectures—from scalar cores and vector SIMD to cache hierarchies and graphics rasterization.

Built with ~20 files of fully documented Verilog, the project evolves through 7 development milestones: RV32IM scalar core, INT4/FP32 ML extensions, sparsity-aware execution, out-of-order ROB, L1 cache, graphics pipeline, and 128-bit vector SIMD. It includes verified matrix addition/multiplication and vector kernels with full simulation and execution traces.

### Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [GPU](#gpu)
  - [Memory](#memory)
  - [Core](#core)
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

<p float="left">
  <img src="/docs/images/gpu.png" alt="GPU" width="48%">
  <img src="/docs/images/core.png" alt="Core" width="48%">
</p>

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

# ISA

![ISA](/docs/images/isa.png)

The architecture implements the **RV32IM** base ISA with custom extensions for GPU and ML workloads.

## Base RV32IM
Full support for standard RISC-V integer (`I`) and multiply/divide (`M`) instructions (LUI, AUIPC, JAL, JALR, BRANCH, LOAD, STORE, OP-IMM, OP, SYSTEM, MUL, DIV, etc.).

## Custom Extensions

| Opcode | Name | Description |
|--------|------|-------------|
| `CUSTOM0` | `RET` | Thread retirement |
| `CUSTOM1` | `DP4A` / `FP32` | Scalar INT4 dot-product or FP32 ops |
| `CUSTOM2` | Vector SIMD | 128-bit packed vector operations |

### Scalar Custom Operations (CUSTOM1)
- `000`: `DP4A` (Signed INT4 dot-product accumulate)
- `001`: `DP4A.U` (Unsigned INT4 dot-product accumulate)
- `010`: `FP.ADD` (FP32 add stub)
- `011`: `FP.MUL` (FP32 multiply stub)

### Vector Operations (CUSTOM2)
- `000`: `VADD.I8` (16 × INT8 packed add)
- `001`: `VMUL.I8` (16 × INT8 packed multiply-low)
- `010`: `VMADD.I8` (16 × INT8 multiply-accumulate)
- `011`: `VDP4A.I4` (4 × 8 × INT4 signed DP4A)
- `100`: `VADD.F32` (4 × FP32 add stub)
- `101`: `VMUL.F32` (4 × FP32 multiply stub)
- `110`: `VMADD.F32` (4 × FP32 FMA stub)
- `111`: `VPREFETCH` (Prefetch hint)

## Register File
- **Scalar (32 × 32-bit):** x0 (zero), x13-x15 (special registers), others general purpose.
- **Vector (16 × 128-bit):** v0 (zero), v13-v15 (broadcast special registers), others general purpose.

# Execution

### Pipeline Stages
Each core utilizes a 7-stage pipeline:
1. `IDLE` $\rightarrow$ 2. `FETCH` $\rightarrow$ 3. `DECODE` $\rightarrow$ 4. `REQUEST` $\rightarrow$ 5. `WAIT` $\rightarrow$ 6. `EXECUTE` $\rightarrow$ 7. `UPDATE`

### Out-of-Order Execution (Phase 4)
A Tomasulo-style ROB enables load-latency hiding:
- **In-order allocation/commit, out-of-order writeback.**
- **Hazard detection** and **result forwarding** to minimize pipeline stalls.

### Sparsity-Aware Execution (Phase 3)
For sparse ML tensors, the scheduler detects zero-valued operands and skips the EXECUTE stage, reducing power and increasing throughput.

### Thread
Each thread maintains its own state (PC, registers, L1 cache) while operating within a SIMD block, ensuring parallel execution of the same instruction across multiple data points.

# Kernels
The project includes verified kernels demonstrating SIMD programming and execution:

### Matrix Addition (RV32I)
Demonstrates basic RV32I load/store and the `%blockIdx / %blockDim / %threadIdx` SIMD pattern.

### Matrix Multiplication (RV32IM)
Demonstrates `mul`, `div`, and `blt` branching for accumulated dot-products.

### Vector DP4A (Phase 7 — CUSTOM2)
Demonstrates 128-bit vector SIMD using the `VDP4A.I4` instruction for high-throughput INT4 dot-products.

# Simulation

`tiny-gpu` is simulated using a modern verification stack.

### Prerequisites
**Option A: Nix (Recommended)**
```bash
nix-shell -p iverilog python3 python3Packages.cocotb gnumake
# sv2v must be installed separately
```

**Option B: Manual installation**
- Icarus Verilog (`apt install iverilog`)
- sv2v (from GitHub releases)
- cocotb (`pip3 install cocotb`)

### Run Tests
```bash
make test_matadd    #T Scalar matrix addition
make test_matmul    # Scalar matrix multiplication + vector DP4A
```

# Optimizations

## Implemented
- **L1 Data Cache (Phase 5):** 2-way set-associative, write-through policy.
- **Out-of-Order ROB (Phase 4):** Tomasulo-style hazard management.
- **Sparsity-Aware Execution (Phase 3):** Zero-detection for power saving.
- **Vector SIMD (Phase 7):** 128-bit packed operations (INT8/INT4).
- **Graphics Pipeline (Phase 6):** Rasterizer and texture unit for educational use.

## Future Work
- **Multi-level Cache:** Implement a shared L2 cache.
- **Memory Coalescing:** Combine adjacent thread requests into single transactions.
- **Warp Scheduling:** Implement multi-warp concurrency per core.
- **Branch Divergence:** Handle divergent execution paths.
- **FP32 Silicon:** Replace stubs with IEEE-754 compliant FP IP.
- **Physical Implementation:** Target an FPGA carrier board for physical bring-up.

## Next Steps
Contributors are welcome to help with the TODO list or submit PRs for new optimizations!
