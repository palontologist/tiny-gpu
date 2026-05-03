import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

# ---------------------------------------------------------------------------
# RV32I instruction encoders (32-bit little-endian word values)
# ---------------------------------------------------------------------------

def _rv32_load(rd, rs1, imm=0, funct3=0b010):
    """LW (funct3=010) or VLW.Q (funct3=011 for 128-bit quad-word)."""
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0b0000011

def _rv32_store(rs1, rs2, imm=0, funct3=0b010):
    """SW (funct3=010) or VSW.Q (funct3=011 for 128-bit quad-word)."""
    imm5 = imm & 0x1F
    imm7 = (imm >> 5) & 0x7F
    return (imm7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm5 << 7) | 0b0100011

def _rv32_addi(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b0010011

def _rv32_add(rd, rs1, rs2):
    return (rs2 << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b0110011

def _rv32_mul(rd, rs1, rs2):
    return (0b0000001 << 25) | (rs2 << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b0110011

def _rv32_ret():
    """CUSTOM0 opcode — thread done."""
    return 0b0001011

def _rv32_vlw_q(vrd, rs1, imm=0):
    """VLW.Q: LOAD with funct3=011 → decoded_mem_size=2'b11 (128-bit quad-word)."""
    return _rv32_load(vrd, rs1, imm, funct3=0b011)

def _rv32_vsw_q(vrs2, rs1, imm=0):
    """VSW.Q: STORE with funct3=011 → decoded_mem_size=2'b11 (128-bit quad-word)."""
    return _rv32_store(rs1, vrs2, imm, funct3=0b011)

def _rv32_custom2(vrd, vrs1, vrs2, funct3, funct7=0):
    """CUSTOM2 opcode (7'b1001011) — 128-bit vector SIMD operations (Phase 7).
    vrd/vrs1/vrs2 are 4-bit vector register indices (v0–v15) placed in the
    standard RV32 5-bit register fields (upper bit = 0).
    funct3 selects the vector ALU operation (matches vec_alu.sv VALU_* codes).
    """
    return ((funct7 & 0x7F) << 25) | ((vrs2 & 0xF) << 20) | ((vrs1 & 0xF) << 15) | \
           ((funct3 & 0x7) << 12) | ((vrd & 0xF) << 7) | 0b1001011

# VALU operation codes (must match vec_alu.sv)
VALU_VADD_I8   = 0b000
VALU_VMUL_I8   = 0b001
VALU_VMADD_I8  = 0b010
VALU_VDP4A_I4  = 0b011
VALU_VADD_F32  = 0b100
VALU_VMUL_F32  = 0b101
VALU_VMADD_F32 = 0b110
VALU_VPREFETCH = 0b111


# ---------------------------------------------------------------------------
# Test 1 — original scalar 2×2 matrix multiply (unchanged)
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_matadd(dut):
    # Program Memory
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        0b0101000011011110, # MUL R0, %blockIdx, %blockDim
        0b0011000000001111, # ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx
        0b1001000100000001, # CONST R1, #1                   ; increment
        0b1001001000000010, # CONST R2, #2                   ; N (matrix inner dimension)
        0b1001001100000000, # CONST R3, #0                   ; baseA (matrix A base address)
        0b1001010000000100, # CONST R4, #4                   ; baseB (matrix B base address)
        0b1001010100001000, # CONST R5, #8                   ; baseC (matrix C base address)
        0b0110011000000010, # DIV R6, R0, R2                 ; row = i // N
        0b0101011101100010, # MUL R7, R6, R2
        0b0100011100000111, # SUB R7, R0, R7                 ; col = i % N
        0b1001100000000000, # CONST R8, #0                   ; acc = 0
        0b1001100100000000, # CONST R9, #0                   ; k = 0
                            # LOOP:
        0b0101101001100010, #   MUL R10, R6, R2
        0b0011101010101001, #   ADD R10, R10, R9
        0b0011101010100011, #   ADD R10, R10, R3             ; addr(A[i]) = row * N + k + baseA
        0b0111101010100000, #   LDR R10, R10                 ; load A[i] from global memory
        0b0101101110010010, #   MUL R11, R9, R2
        0b0011101110110111, #   ADD R11, R11, R7
        0b0011101110110100, #   ADD R11, R11, R4             ; addr(B[i]) = k * N + col + baseB
        0b0111101110110000, #   LDR R11, R11                 ; load B[i] from global memory
        0b0101110010101011, #   MUL R12, R10, R11
        0b0011100010001100, #   ADD R8, R8, R12              ; acc = acc + A[i] * B[i]
        0b0011100110010001, #   ADD R9, R9, R1               ; increment k
        0b0010000010010010, #   CMP R9, R2
        0b0001100000001100, #   BRn LOOP                     ; loop while k < N
        0b0011100101010000, # ADD R9, R5, R0                 ; addr(C[i]) = baseC + i 
        0b1000000010011000, # STR R9, R8                     ; store C[i] in global memory
        0b1111000000000000  # RET                            ; end of kernel
    ]

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [
        1, 2, 3, 4, # Matrix A (2 x 2)
        1, 2, 3, 4, # Matrix B (2 x 2)
    ]

    # Device Control
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(12)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles, thread_id=1)
        
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(12)


    # Assuming the matrices are 2x2 and the result is stored starting at address 9
    matrix_a = [data[0:2], data[2:4]]  # First matrix (2x2)
    matrix_b = [data[4:6], data[6:8]]  # Second matrix (2x2)
    expected_results = [
        matrix_a[0][0] * matrix_b[0][0] + matrix_a[0][1] * matrix_b[1][0],  # C[0,0]
        matrix_a[0][0] * matrix_b[0][1] + matrix_a[0][1] * matrix_b[1][1],  # C[0,1]
        matrix_a[1][0] * matrix_b[0][0] + matrix_a[1][1] * matrix_b[1][0],  # C[1,0]
        matrix_a[1][0] * matrix_b[0][1] + matrix_a[1][1] * matrix_b[1][1],  # C[1,1]
    ]
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + 8]  # Results start at address 9
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"


# ---------------------------------------------------------------------------
# Test 2 — Phase 7: VDP4A_I4 vector dot-product across 4 threads
#
# Kernel (encoded as RV32I + CUSTOM2):
#
#   Each thread computes a 4-lane INT4 dot-product of a 128-bit row vector A
#   and a 128-bit column vector B using VDP4A_I4, which simultaneously
#   accumulates 4 independent 32-bit dot-products (each over 8 × INT4 pairs).
#
#   Memory layout (128-bit addresses, VECTOR_ENABLE=1):
#     addr 0 → row A₀  (128 bits, 32 nibbles: a₀…a₃₁)
#     addr 1 → row A₁  (thread 1 uses this row)
#     addr 2 → row A₂
#     addr 3 → row A₃
#     addr 4 → col B   (128 bits, shared by all threads)
#     addr 8 → output C₀  (result for thread 0)
#     addr 9 → output C₁
#     …
#
#   RV32I registers:
#     x13 = %blockIdx, x14 = %blockDim, x15 = %threadIdx
#     x1  = thread index i = blockIdx*blockDim + threadIdx
#     x2  = base address of B column (4)
#     x3  = output base address (8)
#     x4  = output address for this thread
#
#   Vector registers:
#     v1  = loaded row A[i]     (128 bits)
#     v2  = loaded column B     (128 bits)
#     v3  = accumulator / result (VDP4A_I4 output, 4 × 32-bit lanes)
#
#   Expected:
#     Every element of A and B is packed as INT4 = 1 (nibble 0x1).
#     Each 32-bit lane = sum of 8 × (1 × 1) = 8.
#     Result 128-bit word = 0x00000008_00000008_00000008_00000008.
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_vec_dp4a(dut):
    # ---- Program (RV32I + CUSTOM2) ----
    # x1  = i = blockIdx * blockDim + threadIdx
    # x2  = 4   (B column address)
    # x3  = 8   (output base)
    # x4  = output address = 8 + i
    # v1  = A[i] (128-bit row, VLW.Q)
    # v2  = B    (128-bit column, VLW.Q)
    # v3  = VDP4A_I4(v1, v2, v0)  ; v0 = 0 accumulator
    # store v3 to output[i]       (VSW.Q)

    x0, x1, x2, x3, x4 = 0, 1, 2, 3, 4  # scalar register aliases
    # blockIdx/blockDim/threadIdx in scalar register file (GPU convention)
    x_block_idx, x_block_dim, x_thread_idx = 13, 14, 15
    v0, v1, v2, v3 = 0, 1, 2, 3          # vector register aliases

    program = [
        # i = blockIdx * blockDim + threadIdx
        _rv32_mul(x1, x_block_idx, x_block_dim),  # x1 = blockIdx * blockDim
        _rv32_add(x1, x1, x_thread_idx),          # x1 += threadIdx  → i

        # Load 128-bit row A[i] from address i into vector register v1
        _rv32_vlw_q(v1, x1),                      # v1 = mem[i] (VLW.Q)

        # Load 128-bit column B from address 4 into v2
        _rv32_addi(x2, x0, 4),                    # x2 = 4
        _rv32_vlw_q(v2, x2),                      # v2 = mem[4] (VLW.Q)

        # VDP4A_I4 v3, v1, v2, v0  (v0 = 0, no prior accumulation)
        _rv32_custom2(v3, v1, v2, VALU_VDP4A_I4), # v3 = dp4a(v1, v2, v0)

        # Compute output address = 8 + i and store 128-bit result
        _rv32_addi(x3, x0, 8),                    # x3 = 8 (output base)
        _rv32_add(x4, x3, x1),                    # x4 = 8 + i
        _rv32_vsw_q(v3, x4),                      # mem[x4] = v3 (VSW.Q)

        _rv32_ret(),                               # RET
    ]

    program_memory = Memory(dut=dut, addr_bits=8, data_bits=32,
                            channels=1, name="program")

    # ---- Data memory (128-bit words, VECTOR_ENABLE=1) ----
    # Pack 32 nibbles of value 1 into a 128-bit word: 0x11111111...11
    a_row = 0x11111111_11111111_11111111_11111111   # all INT4 = 1
    b_col = 0x11111111_11111111_11111111_11111111   # all INT4 = 1

    data_memory = Memory(dut=dut, addr_bits=8, data_bits=128,
                         channels=4, name="data")

    data = [
        a_row,   # addr 0: A row for thread 0
        a_row,   # addr 1: A row for thread 1
        a_row,   # addr 2: A row for thread 2
        a_row,   # addr 3: A row for thread 3
        b_col,   # addr 4: B column (shared)
    ]

    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(16)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()
        await cocotb.triggers.ReadOnly()
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"test_vec_dp4a completed in {cycles} cycles")
    data_memory.display(16)

    # ---- Verify results ----
    # VDP4A_I4: 4 lanes × (8 × INT4 dot product).
    # A and B both have all nibbles = 1 (signed INT4 = +1).
    # Each lane: sum_{k=0}^{7} 1 * 1 = 8 → 32-bit lane value = 8.
    # 128-bit word = {8, 8, 8, 8} packed as four 32-bit little-endian lanes.
    expected_lane = 8
    expected_128 = (expected_lane | (expected_lane << 32) |
                    (expected_lane << 64) | (expected_lane << 96))

    for thread_i in range(threads):
        # Each thread stored its 128-bit result at address (8 + thread_i)
        result = data_memory.memory[8 + thread_i]
        assert result == expected_128, (
            f"Thread {thread_i}: VDP4A result mismatch — "
            f"expected 0x{expected_128:032X}, got 0x{result:032X}"
        )

    logger.info("test_vec_dp4a: all VDP4A_I4 results verified ✓")

