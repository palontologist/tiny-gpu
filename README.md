# tiny-gpu

A RISC-V-based GPU implementation in Verilog optimized for learning GPU architecture from the ground up — from scalar cores to vector SIMD, cache hierarchies, and graphics rasterization.

Built with ~20 files of fully documented Verilog spanning 7 development phases: RV32IM scalar core, INT4/FP32 ML extensions, sparsity-aware execution, out-of-order ROB, L1 cache, graphics pipeline, and 128-bit vector SIMD. Includes working matrix addition/multiplication/vector kernels with full simulation and execution traces.

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
  - [Out-of-Order Execution](#out-of-order-execution-phase-4)
  - [Sparsity Skip](#sparsity-skip-phase-3)
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

If you want to learn how a CPU works all the way from architecture to control signals, there are many resources online to help you.

GPUs are not the same.

Because the GPU market is so competitive, low-level technical details for all modern architectures remain proprietary.

While there are lots of resources to learn about GPU programming, there's almost nothing available to learn about how GPU's work at a hardware level.

The best option is to go through open-source GPU implementations like [Miaow](https://github.com/VerticalResearchGroup/miaow) and [VeriGPU](https://github.com/hughperkins/VeriGPU/tree/main) and try to figure out what's going on. This is challenging since these projects aim at being feature complete and functional, so they're quite complex.

This is why I built `tiny-gpu`!

## What is tiny-gpu?

> [!IMPORTANT]
>
> **tiny-gpu** is a RISC-V-based GPU implementation optimized for learning about how GPUs work from the ground up — from scalar cores to vector SIMD, cache hierarchies, and graphics rasterization.
>
> Specifically, with the trend toward general-purpose GPUs (GPGPUs) and ML-accelerators like Google's TPU, tiny-gpu focuses on highlighting the general principles of all of these architectures, rather than on the details of graphics-specific hardware.

Built with ~20 files of fully documented Verilog spanning 7 development phases:

- **Phase 1**: RV32IM scalar core (RISC-V base ISA)
- **Phase 2**: INT4/FP32 custom extensions for ML inference
- **Phase 3**: Sparsity-aware execution (zero-skip for power saving)
- **Phase 4**: Out-of-order execution with Tomasulo-style ROB
- **Phase 5**: Per-thread L1 data cache (2-way set-associative)
- **Phase 6**: Graphics pipeline (rasterizer + texture unit + framebuffer)
- **Phase 7**: 128-bit vector extensions (INT8/INT4 SIMD, FP32 stubs)

This project is primarily focused on exploring:

1. **Architecture** - What does the architecture of a GPU look like? What are the most important elements?
2. **Parallelization** - How is the SIMD programming model implemented in hardware?
3. **Memory** - How does a GPU work around the constraints of limited memory bandwidth?
4. **ML Acceleration** - How do vector units and INT4/INT8 quantization enable efficient inference?

After understanding the fundamentals laid out in this project, you can checkout the [advanced functionality section](#advanced-functionality) to understand some of the most important optimizations made in production grade GPUs (that are more challenging to implement) which improve performance.

# Architecture

<p float="left">
  <img src="/docs/images/gpu.png" alt="GPU" width="48%">
  <img src="/docs/images/core.png" alt="Core" width="48%">
</p>

## GPU

tiny-gpu is built to execute a single kernel at a time.

In order to launch a kernel, we need to do the following:

1. Load global program memory with the kernel code (32-bit RV32IM instructions)
2. Load data memory with the necessary data (32-bit words, or 128-bit with VECTOR_ENABLE=1)
3. Specify the number of threads to launch in the device control register
4. Launch the kernel by setting the start signal to high.

The GPU itself consists of the following units:

1. Device control register
2. Dispatcher
3. Variable number of compute cores (each with ROB, L1 cache, vector units)
4. Memory controllers for data memory & program memory
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

The device control register usually stores metadata specifying how kernels should be executed on the GPU.

In this case, the device control register just stores the `thread_count` - the total number of threads to launch for the active kernel.

### Dispatcher

Once a kernel is launched, the dispatcher is the unit that actually manages the distribution of threads to different compute cores.

The dispatcher organizes threads into groups that can be executed in parallel on a single core called **blocks** and sends these blocks off to be processed by available cores.

Once all blocks have been processed, the dispatcher reports back that the kernel execution is done.

## Memory

The GPU is built to interface with an external global memory. Here, data memory and program memory are separated out for simplicity.

### Global Memory

tiny-gpu data memory has the following specifications:

- 8 bit addressability (256 word-addressable rows of data memory)
- 32 bit scalar data (stores 32-bit values for each row)
- 128 bit vector data when `VECTOR_ENABLE=1` (stores four 32-bit lanes or sixteen 8-bit lanes)

tiny-gpu program memory has the following specifications:

- 8 bit addressability (256 word-addressable rows of program memory)
- 32 bit instructions (each instruction is a 32-bit RV32IM word as specified by the ISA)

### Memory Controllers

Global memory has fixed read/write bandwidth, but there may be far more incoming requests across all cores to access data from memory than the external memory is actually able to handle.

The memory controllers keep track of all the outgoing requests to memory from the compute cores, throttle requests based on actual external memory bandwidth, and relay responses from external memory back to the proper resources.

Each memory controller has a fixed number of channels based on the bandwidth of global memory.

### L1 Data Cache

The same data is often requested from global memory by multiple cores. Constantly accessing global memory is expensive, and since the data has already been fetched once, it would be more efficient to store it on device in SRAM to be retrieved much quicker on later requests.

Each thread has a **private L1 data cache** (Phase 5) with the following features:

- **2-way set-associative** organization (SET=16 sets by default)
- **Write-through** policy (no dirty bits needed)
- **Hit latency**: 1 cycle (tag look-up registered, data presented next cycle)
- **Miss latency**: memory-controller round-trip + 1 fill cycle
- **LRU replacement** policy per set

Data retrieved from external memory is stored in cache and can be retrieved from there on later requests, freeing up memory bandwidth to be used for new data.

## Core

Each core has a number of compute resources, often built around a certain number of threads it can support. In order to maximize parallelization, these resources need to be managed optimally to maximize resource utilization.

In this GPU, each core processes one **block** at a time, and for each thread in a block, the core has a dedicated ALU, LSU, PC, scalar register file, vector register file, and L1 cache. Managing the execution of thread instructions on these resources is one of the most challenging problems in GPUs.

### Scheduler

Each core has a single scheduler that manages the execution of threads through a 7-stage pipeline.

The tiny-gpu scheduler executes instructions for a single block to completion before picking up a new block, and it executes instructions for all threads in-sync and sequentially.

**Phase 3 — Sparsity Skip:** If all threads in a warp have zero-valued operands for an ALU operation, the scheduler skips the EXECUTE stage and writes zero directly, saving power on sparse ML workloads.

**Phase 4 — ROB Hazard Stall:** Before advancing past the REQUEST stage, the scheduler checks whether either source register has an unresolved in-flight write in the ROB. If so, the pipeline stalls until the hazard clears or the value is forwarded.

In more advanced schedulers, techniques like **pipelining** are used to stream the execution of multiple instructions subsequent instructions to maximize resource utilization before previous instructions are fully complete. Additionally, **warp scheduling** can be use to execute multiple batches of threads within a block in parallel.

The main constraint the scheduler has to work around is the latency associated with loading & storing data from global memory. While most instructions can be executed synchronously, these load-store operations are asynchronous, meaning the rest of the instruction execution has to be built around these long wait times.

### Reorder Buffer (ROB)

**Phase 4** introduces a lightweight Tomasulo-style reorder buffer for out-of-order execution:

- **In-order allocation** at the tail, **in-order commit** at the head
- **Out-of-order writeback**: any in-flight entry can be marked done once its execution unit finishes
- **Hazard detection**: stalls issue when a source register has a pending in-flight write
- **Result forwarding**: if an in-flight entry is already done (written back but not yet committed), the value can be forwarded directly

Each ROB entry covers one warp-level instruction and holds per-thread result data, since all threads in a warp execute the same instruction (SIMD).

### Fetcher

Asynchronously fetches the 32-bit instruction at the current program counter from program memory.

### Decoder

Decodes the fetched 32-bit RV32IM instruction into control signals for thread execution, including:
- Standard RV32I opcodes (LUI, AUIPC, JAL, JALR, BRANCH, LOAD, STORE, OP-IMM, OP, SYSTEM)
- RV32M multiply/divide extensions
- Custom opcodes: `CUSTOM0` (RET), `CUSTOM1` (INT4/FP32), `CUSTOM2` (128-bit vector SIMD)

### Register Files

**Scalar Registers (RV32):** Each thread has 32 × 32-bit scalar registers (x0-x31), following the RISC-V convention:
- x0 is hardwired to zero
- x13-x15 are read-only GPU special registers: `%blockIdx`, `%blockDim`, `%threadIdx`
- The rest are general-purpose read/write registers

**Vector Registers (Phase 7):** Each thread has 16 × 128-bit vector registers (v0-v15):
- v0 is hardwired to zero
- v13-v15 mirror the scalar special registers (broadcast to all lanes)
- Used for packed SIMD operations (INT8/INT4/FP32)

The register files hold the data that each thread is performing computations on, which enables the same-instruction multiple-data (SIMD) pattern.

### ALUs

Dedicated arithmetic-logic unit for each thread to perform scalar computations. Supports full RV32IM integer operations:

- **RV32I**: `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`, `LUI`
- **RV32M**: `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`
- **Custom (Phase 2/6)**: `DP4A` (signed/unsigned INT4 dot-product accumulate), `FP_ADD`, `FP_MUL` (stubs)

Also handles branch condition evaluation for `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`.

### Vector ALUs (Phase 7)

Dedicated 128-bit vector ALU for each thread to perform packed SIMD operations:

- `VADD_I8`: 16 × INT8 packed add
- `VMUL_I8`: 16 × INT8 packed multiply-low
- `VMADD_I8`: 16 × INT8 multiply-accumulate
- `VDP4A_I4`: 4 × (8 × INT4 signed DP4A) — 4 parallel 32-bit accumulators
- `VADD_F32`: 4 × FP32 add (stub, integer approximation)
- `VMUL_F32`: 4 × FP32 multiply (stub, placeholder)
- `VMADD_F32`: 4 × FP32 fused multiply-add (stub)
- `VPREFETCH`: Prefetch hint

Intel DSP inference hint: `(* use_dsp = "yes" *)` on multiply paths encourages Quartus to infer DSP blocks.

### LSUs

Dedicated load-store unit for each thread to access global data memory.

Handles standard RV32I memory operations (`LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`) and Phase 7 vector extensions (`VLW.Q`, `VSW.Q` for 128-bit quad-word transfers).

Manages async wait times for memory requests, with L1 cache hits returning in 1 cycle and misses requiring a memory-controller round-trip.

### PCs

Dedicated program-counter for each thread to determine the next instruction to execute.

By default, the PC increments by 4 after every 32-bit instruction.

With branch instructions (`BEQ`, `BNE`, `BLT`, etc.), the ALU evaluates the branch condition and the PC updates to the target address if taken. With `JAL`/`JALR`, the PC jumps to a new address and the link register (rd) is set to PC+4.

Since threads are processed in parallel, tiny-gpu assumes that all threads "converge" to the same program counter after each instruction — which is a naive assumption for the sake of simplicity.

In real GPUs, individual threads can branch to different PCs, causing **branch divergence** where a group of threads initially being processed together has to split out into separate execution.

### Graphics Pipeline (Phase 6)

Optional graphics hardware components:

**Rasterizer:** Scan-line tile rasterizer with barycentric interpolation. Converts triangle primitives into a stream of covered fragments (pixels). Vertex inputs use 16.16 fixed-point format.

**Texture Unit:** Bilinear filtering with INT8 texels. Inputs are 8.8 fixed-point UV coordinates. Supports greyscale textures (RGBA stub).

**Framebuffer Interface:** Connects the rasterizer output to the display/framebuffer memory.

# ISA

![ISA](/docs/images/isa.png)

tiny-gpu implements a 32-bit **RISC-V RV32IM** base ISA with custom extensions for GPU workloads, ML inference, and vector SIMD.

## Base RV32IM

Standard RISC-V integer (`I`) and multiply/divide (`M`) instructions are fully supported:

- **LUI/AUIPC**: Load upper immediate / add upper immediate to PC
- **JAL/JALR**: Jump and link (function calls, loops)
- **BRANCH**: Conditional branches (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`)
- **LOAD/STORE**: Memory access (`LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`)
- **OP-IMM**: Immediate arithmetic (`ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI`)
- **OP**: Register arithmetic (`ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`)
- **RV32M**: `MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`

## Custom Extensions

| Opcode | Name | Description |
|--------|------|-------------|
| `CUSTOM0` (`0001011`) | `RET` | Thread retirement |
| `CUSTOM1` (`0101011`) | `DP4A` / `FP32` | Scalar INT4 dot-product or FP32 ops |
| `CUSTOM2` (`1001011`) | Vector SIMD | 128-bit packed vector operations |

### Scalar Custom Operations (CUSTOM1)

| funct3 | Operation | Description |
|--------|-----------|-------------|
| `000` | `DP4A` | Signed INT4 dot-product accumulate (8× INT4 pairs) |
| `001` | `DP4A.U` | Unsigned INT4 dot-product accumulate |
| `010` | `FP.ADD` | FP32 add (stub — integer approximation) |
| `011` | `FP.MUL` | FP32 multiply (stub — placeholder) |

### Vector Operations (CUSTOM2)

| funct3 | Operation | Description | Lanes |
|--------|-----------|-------------|-------|
| `000` | `VADD.I8` | 16 × INT8 packed add | 16 × 8-bit |
| `001` | `VMUL.I8` | 16 × INT8 packed multiply-low | 16 × 8-bit |
| `010` | `VMADD.I8` | 16 × INT8 multiply-accumulate | 16 × 8-bit |
| `011` | `VDP4A.I4` | 4 × (8 × INT4 signed DP4A) | 4 × 32-bit |
| `100` | `VADD.F32` | 4 × FP32 add (stub) | 4 × 32-bit |
| `101` | `VMUL.F32` | 4 × FP32 multiply (stub) | 4 × 32-bit |
| `110` | `VMADD.F32` | 4 × FP32 FMA (stub) | 4 × 32-bit |
| `111` | `VPREFETCH` | Prefetch hint | — |

## Register File

### Scalar Registers (32 × 32-bit)

Following the RISC-V convention:
- `x0` — Hardwired zero
- `x1-x12` — General-purpose read/write
- `x13` — `%blockIdx` (read-only GPU special register)
- `x14` — `%blockDim` (read-only GPU special register)
- `x15` — `%threadIdx` (read-only GPU special register)
- `x16-x31` — General-purpose read/write

### Vector Registers (16 × 128-bit per thread)

- `v0` — Hardwired zero
- `v1-v12` — General-purpose read/write
- `v13` — `%blockIdx` (broadcast to all lanes)
- `v14` — `%blockDim` (broadcast to all lanes)
- `v15` — `%threadIdx` (broadcast to all lanes)

# Execution

### Pipeline Stages

Each core follows a 7-stage pipeline to execute each instruction:

1. `IDLE` — Wait for block dispatch from the scheduler
2. `FETCH` — Fetch the 32-bit instruction at the current PC from program memory
3. `DECODE` — Decode the instruction into control signals and allocate a ROB entry
4. `REQUEST` — Read register files (scalar + vector); check ROB hazards; request L1 cache/memory if needed
5. `WAIT` — Wait for L1 cache (hit = 1 cycle) or memory controller (miss = round-trip + fill)
6. `EXECUTE` — Perform ALU/vector ALU computations; ROB writeback
7. `UPDATE` — Commit ROB entry to register file in-order; update PC

The control flow is laid out like this for the sake of clarity and understandability.

### Out-of-Order Execution (Phase 4)

The ROB allows instructions to complete out-of-order while committing in-order:

- **Allocation**: In-order at the tail when instruction enters DECODE
- **Writeback**: Out-of-order when execution unit finishes (ALU, LSU, vector ALU)
- **Commit**: In-order at the head when all prior instructions have completed
- **Forwarding**: If a source register's value is in the ROB and already written back, it can be forwarded directly without waiting for commit
- **Stalling**: If a source register has a pending in-flight write, the scheduler stalls in REQUEST until the hazard clears

This enables load-latency hiding: while one instruction waits for memory, subsequent independent instructions can execute.

### Sparsity Skip (Phase 3)

For ML workloads with sparse tensors, if all threads in a warp have zero-valued operands for an ALU operation, the scheduler skips the EXECUTE stage entirely and writes zero directly to the destination register. This saves power and cycles on sparse operations.

### Thread

![Thread](/docs/images/thread.png)

Each thread within each core follows the above execution path to perform computations on the data in its dedicated register file.

This resembles a standard CPU diagram, and is quite similar in functionality as well. The main difference is that the `%blockIdx`, `%blockDim`, and `%threadIdx` values lie in the read-only registers for each thread, enabling SIMD functionality.

# Kernels

I wrote matrix addition, matrix multiplication, and vector dot-product kernels using RV32IM as a proof of concept to demonstrate SIMD programming and execution with the GPU. The test files in this repository are capable of fully simulating the execution of these kernels, producing data memory states and a complete execution trace.

### Matrix Addition (RV32I)

This kernel adds two 1×8 matrices by performing 8 element-wise additions across separate threads. It demonstrates basic RV32I load/store, arithmetic, and the `%blockIdx` / `%blockDim` / `%threadIdx` SIMD pattern.

```asm
# Matrix A at data[0..7], Matrix B at data[8..15], Result at data[16..23]
# Scalar values are packed into the lower 32 bits of each 128-bit word

mul     x10, x13, x14        # x10 = blockIdx * blockDim
add     x10, x10, x15        # i = blockIdx * blockDim + threadIdx

li      x11, 0               # baseA = 0
li      x12, 8               # baseB = 8
li      x13, 16              # baseC = 16

add     x14, x11, x10        # addr(A[i]) = baseA + i
lw      x14, 0(x14)          # x14 = A[i]

add     x15, x12, x10        # addr(B[i]) = baseB + i
lw      x15, 0(x15)          # x15 = B[i]

add     x16, x14, x15        # C[i] = A[i] + B[i]

add     x17, x13, x10        # addr(C[i]) = baseC + i
sw      x16, 0(x17)          # store C[i]

ret                          # thread done
```

### Matrix Multiplication (RV32IM)

Multiplies two 2×2 matrices using scalar RV32IM with a loop. Demonstrates `mul`, `div`, `blt` branching, and accumulated dot-products.

```asm
# A = [[1,2],[3,4]] at data[0..3], B = [[1,2],[3,4]] at data[4..7]
# Result C at data[8..11]

mul     x1, x13, x14         # i = blockIdx * blockDim + threadIdx
add     x1, x1, x15

li      x2, 1                # increment = 1
li      x3, 2                # N = 2
li      x4, 0                # baseA = 0
li      x5, 4                # baseB = 4
li      x6, 8                # baseC = 8

div     x7, x1, x3           # row = i // N
mul     x8, x7, x3
sub     x9, x1, x8           # col = i % N

li      x10, 0               # acc = 0
li      x11, 0               # k = 0

LOOP:
  mul   x12, x7, x3          # addr(A) = row * N + k + baseA
  add   x12, x12, x11
  add   x12, x12, x4
  lw    x12, 0(x12)          # x12 = A[row*N + k]

  mul   x13, x11, x3         # addr(B) = k * N + col + baseB
  add   x13, x13, x9
  add   x13, x13, x5
  lw    x13, 0(x13)          # x13 = B[k*N + col]

  mul   x14, x12, x13        # x14 = A * B
  add   x10, x10, x14        # acc += A * B

  add   x11, x11, x2         # k++
  blt   x11, x3, LOOP        # loop while k < N

add     x15, x6, x1          # addr(C[i]) = baseC + i
sw      x10, 0(x15)          # store C[i]

ret                          # thread done
```

### Vector DP4A (Phase 7 — CUSTOM2)

Demonstrates 128-bit vector SIMD using the `VDP4A.I4` instruction. Each thread computes a 4-lane INT4 dot-product across 128-bit vectors.

```asm
# Memory layout (128-bit words):
# addr 0-3: Row vectors A (one per thread)
# addr 4:   Column vector B (shared)
# addr 8-11: Output C (one per thread)

mul     x1, x13, x14         # i = blockIdx * blockDim + threadIdx
add     x1, x1, x15

vlw.q   v1, x1               # v1 = A[i] (128-bit row vector)

li      x2, 4
vlw.q   v2, x2               # v2 = B (128-bit column vector)

vdp4a.i4 v3, v1, v2          # v3 = dp4a(v1, v2, v0) ; v0 = 0

li      x3, 8
add     x4, x3, x1           # output address = 8 + i
vsw.q   v3, x4               # store 128-bit result

ret                          # thread done
```

# Simulation

tiny-gpu is setup to simulate the execution of all three kernel types (scalar RV32I, scalar RV32IM, and vector SIMD). Before simulating, you'll need to install [iverilog](https://steveicarus.github.io/iverilog/usage/installation.html), [sv2v](https://github.com/zachjs/sv2v), and [cocotb](https://docs.cocotb.org/en/stable/install.html):

### Prerequisites

**Option A: Nix (recommended for NixOS/Linux)**
```bash
nix-shell -p iverilog python3 python3Packages.cocotb gnumake
# sv2v must be installed separately (download from GitHub releases)
```

**Option B: Manual installation**
- Install Icarus Verilog: `brew install icarus-verilog` (macOS) or `apt install iverilog` (Ubuntu)
- Install sv2v: Download from https://github.com/zachjs/sv2v/releases, unzip and put the binary in `$PATH`
- Install cocotb: `pip3 install cocotb`
- Run `mkdir -p build` in the root directory of this repository

### Run Tests

Once you've installed the pre-requisites, run the kernel simulations:

```bash
make test_matadd    # Scalar matrix addition (RV32I)
make test_matmul    # Scalar matrix multiplication + vector DP4A (RV32IM + CUSTOM2)
```

Executing the simulations will output a log file in `test/logs` with the initial data memory state, complete execution trace of the kernel, and final data memory state.

### Execution Traces

Below is a sample of the execution traces, showing on each cycle the execution of every thread within every core, including the current instruction, PC, register values, states, etc.

![execution trace](docs/images/trace.png)

**Note:** The test suite encodes RV32IM instructions as binary literals loaded into program memory. The hardware decoder expects 32-bit RISC-V instructions. The `format.py` debug utility can disassemble both legacy 16-bit and new 32-bit instructions for readable traces.

**For anyone trying to run the simulation or play with this repo, please feel free to open an issue if you run into any issues - I want you to get this running!**

# Optimizations

tiny-gpu implements several production-grade GPU features. This section distinguishes between what is already implemented and what remains future work.

## Implemented Optimizations

### L1 Data Cache (Phase 5)

Each thread has a private 2-way set-associative L1 data cache with LRU replacement and write-through policy. This reduces global memory bandwidth pressure by storing recently accessed data in SRAM.

### Out-of-Order Execution / ROB (Phase 4)

The Tomasulo-style reorder buffer enables load-latency hiding through:
- In-order allocation and commit with out-of-order writeback
- Hazard detection and result forwarding
- Stalling only when dependencies are truly unresolved

### Sparsity-Aware Execution (Phase 3)

For sparse ML tensors, zero-valued operations are detected and skipped, saving power and cycles by bypassing the ALU entirely.

### Vector SIMD (Phase 7)

128-bit packed operations accelerate ML inference:
- INT8: 16-lane add, multiply, multiply-accumulate
- INT4: 4-lane DP4A (dot-product accumulate) — critical for quantized neural networks
- FP32: 4-lane stubs (awaiting Intel FP IP)

### Graphics Pipeline (Phase 6)

Basic graphics hardware for educational rasterization:
- Scan-line rasterizer with barycentric interpolation
- Bilinear texture filtering with INT8 texels
- Framebuffer interface

## Future Optimizations

### Multi-level Cache Hierarchy

Implement an L2 cache shared across cores to further reduce global memory bandwidth. Add shared memory within blocks for thread-to-thread data exchange.

### Memory Coalescing

Combine memory requests from adjacent threads into a single transaction. Currently each thread issues separate requests even when accessing sequential addresses.

### Pipelining

Stream execution of multiple sequential instructions simultaneously while respecting dependencies. The current implementation waits for each instruction to complete before starting the next.

### Warp Scheduling

Break blocks into warps (subgroups of threads) and execute multiple warps concurrently on a single core. While one warp waits for memory, another warp can execute.

### Branch Divergence

Handle threads that branch to different PCs within the same warp. This requires tracking divergent paths and reconvergence points.

### Synchronization & Barriers

Implement barrier instructions so threads within a block can synchronize at specific points. Useful for shared memory exchange and ensuring all threads have reached a checkpoint.

### FP32 Silicon

Replace current FP32 stubs with Intel Floating-Point IP (`alt_fp_add` / `alt_fp_mult`) for correct IEEE-754 floating-point operations.

# Next Steps

Updates I want to make in the future to improve the design. Anyone else is welcome to contribute as well:

## Completed ✓

- [x] Add L1 data cache (Phase 5 — per-thread, 2-way set-associative)
- [x] Add out-of-order ROB (Phase 4 — Tomasulo-style with forwarding)
- [x] Add vector extensions (Phase 7 — 128-bit INT8/INT4 SIMD)
- [x] Add graphics rasterizer + texture unit (Phase 6)
- [x] Add sparsity skip (Phase 3 — zero-detection power saving)
- [x] Migrate to RV32IM base ISA (Phase 1)
- [x] Add INT4/FP32 custom extensions (Phase 2/6)

## In Progress / TODO

- [ ] Update test suite to fully exercise all RV32IM instructions
- [ ] Fix sv2v compatibility for `rasterizer.sv` (automatic keyword in procedural blocks)
- [ ] Add branch divergence handling
- [ ] Add memory coalescing
- [ ] Add warp scheduling
- [ ] Replace FP32 stubs with Intel FP IP (alt_fp_add / alt_fp_mult)
- [ ] Add L2 cache
- [ ] Add shared memory / barriers
- [ ] Build an adapter for Tiny Tapeout
- [ ] Optimize control flow and cycle time
- [ ] Write a basic graphics kernel demo

**For anyone curious to play around or make a contribution, feel free to put up a PR with any improvements you'd like to add!**
