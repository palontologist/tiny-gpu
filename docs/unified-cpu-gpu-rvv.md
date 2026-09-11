# Unified RISC-V CPU/GPU Architecture: Standard Vector Extensions (RVV & Simple-V)

## 1. Executive Summary & Vision

This document outlines the architectural specification and design strategy for developing a **Unified CPU/GPU Processor** based on **RISC-V Standard Vector Extensions (Approach B)**.

Rather than relying on proprietary SIMT (Single Instruction, Multiple Threads) warp extensions or discrete accelerator blocks, this architecture leverages the standard **RISC-V Vector Extension (RVV 1.0)** and **Simple-V** dynamic vectorization paradigms to achieve scalar OS execution, general-purpose compute, and 3D graphics shading within a single unified core pipeline.

---

## 2. Core Architectural Principles (Approach B)

### 2.1 Vector Length Agnostic (VLA) Execution
The standard RISC-V `V` extension decouples software binaries from hardware implementation widths:
- **Scalable Hardware Implementations:** Hardware vector registers ($VLEN$) can scale from 128 bits (for embedded/edge profiles) up to 4096+ bits (for high-throughput compute tiles) without breaking binary compatibility.
- **Dynamic Vector Length Configuration (`vsetvl` / `vsetvli`):** Software sets Application Vector Length ($AVL$) and element width ($SEW$), while the hardware adjusts Vector Register Grouping ($LMUL$) and active vector length ($VL$) dynamically.
- **Elimination of Warp Divergence Overhead:** Vector masking and predication replace complex hardware warp divergence stacks and serialization mechanics used in traditional SIMT pipelines.

### 2.2 Simple-V / Dynamic Register Morphing
Drawing from the Libre-SOC / Simple-V paradigm:
- Standard integer and floating-point registers can be dynamically tagged as vector elements.
- Loop iterations are vectorized at hardware issue/decode level without requiring dedicated vector-only opcode decoding blocks for simple streaming operations.
- Reduces instruction decode area overhead in resource-constrained FPGA/ASIC targets.

---

## 3. Microarchitecture & Pipeline Design

### 3.1 Unified Core Pipeline Overview

```
                      +-------------------+
                      |   Instruction     |
                      |   Fetch (IF)      |
                      +---------+---------+
                                |
                      +---------v---------+
                      |   Decode & Issue  |
                      |   (RV64GC + RVV)  |
                      +----+---------+----+
                           |         |
            +--------------+         +--------------+
            |                                       |
  +---------v---------+                   +---------v---------+
  |  Scalar Pipeline  |                   |  Vector Execution |
  |  (ALU, Branch,    |                   |  Units (VPU)      |
  |   CSR, Syscalls)  |                   |  (Lanes 0..N-1)   |
  +---------+---------+                   +---------+---------+
            |                                       |
            +--------------+         +--------------+
                           |         |
                      +----v---------v----+
                      | Unified Memory /  |
                      | L1 Cache & MMU    |
                      +-------------------+
```

### 3.2 Key Subsystems

1. **Unified Register File (URF):**
   - Combines or bridges scalar registers ($x0..x31$, $f0..f31$) and vector registers ($v0..v31$).
   - Configurable banking to prevent read/write port contention during concurrent scalar memory address calculations and vector ALU operations.

2. **Vector Processing Unit (VPU):**
   - Configurable execution lanes ($DLEN$ width per cycle).
   - Supports integer operations (8-bit, 16-bit, 32-bit, 64-bit), fixed-point math, and floating-point (FP16/BF16/FP32).
   - Dedicated support for vector reductions, element-wise multiply-accumulate (FMA), and gather/scatter memory indexing.

3. **Memory Subsystem & Coherency:**
   - Unified Physical Memory Architecture (eliminates PCIe/bus transfer copies such as `cudaMemcpy`).
   - High-throughput unit-stride, strided, and indexed vector memory units interfacing directly with cache-coherent L1/L2 structures.

---

## 4. Workload Mapping: CPU, Compute & Graphics

### 4.1 CPU / OS Execution Mode
- The core acts as a standard RISC-V host (e.g., `RV64GC` or `RV32IMC`), executing OS kernels (Linux/RTOS), handling interrupts, thread scheduling, device I/O, and control flow.

### 4.2 GPGPU & Parallel Compute
- Matrix multiplications (GEMM), convolution kernels, and tensor activations (ReLU, GeLU, Softmax) are structured into RVV vector loops.
- Strip-mining loops automatically adapt to available hardware $VLEN$ without kernel recompilation.

### 4.3 3D Graphics Pipeline (Vulkan / Software-Assisted Rasterization)
- **Vertex Shading:** Transforms, lighting, and coordinate projections executed as vector floating-point operations over vertex arrays.
- **Triangle Setup & Rasterization:** Bounding-box evaluation and barycentric coordinate interpolation vectorized across pixel spans.
- **Fragment / Pixel Shading:** Color blending, texture sampling (via strided/gather memory fetches), and depth testing computed in vector lanes using active pixel mask registers.

---

## 5. Toolchain & Ecosystem Advantages

| Aspect | Approach B (Standard RVV) | Traditional Custom SIMT (Vortex / Custom ISAs) |
| :--- | :--- | :--- |
| **Compiler Support** | Native upstream LLVM & GCC | Custom compiler forks & proprietary backend targets |
| **Binary Portability** | Universal across any RVV-compliant processor | Bound to specific warp size and custom instruction sets |
| **Ecosystem Risk** | Low (backed by RISC-V International standards) | High (dependent on bespoke hardware maintenance) |
| **Graphics Toolchains** | Compiles via SPIR-V to LLVM RVV backends (e.g., Mesa / LLVMpipe / Vulkan drivers) | Requires specialized shader compiler translation passes |

---

## 6. Implementation Roadmap for Tiny-GPU

1. **Phase 1: RVV Sub-extension Specification**
   - Select baseline: `RV32IMCV` or `RV64GCV` targeting $VLEN=128$ or $256$ bits for initial FPGA synthesis.
   - Define minimal required vector instructions for integer arithmetic, logic, and strided memory loads.

2. **Phase 2: Microarchitecture Integration**
   - Integrate vector decode stage with existing tiny-gpu execution pipelines.
   - Implement vector register file ($v0..v31$) with multi-banked SRAM or distributed FPGA LUTRAM.

3. **Phase 3: Compute & Graphics Kernel Benchmarking**
   - Port basic linear algebra subprograms (BLAS) and software rasterizer fragment kernels to RVV assembly.
   - Verify execution correctness against RISC-V architectural simulators (Spike / QEMU).
