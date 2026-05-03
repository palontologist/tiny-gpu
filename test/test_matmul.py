import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger
from .helpers.rv32i import (
    rv32_mul,
    rv32_add,
    rv32_addi,
    rv32_sub,
    rv32_div,
    rv32_lw,
    rv32_sw,
    rv32_blt,
    rv32_ret,
    X_BLOCK_IDX,
    X_BLOCK_DIM,
    X_THREAD_IDX,
)


# ---------------------------------------------------------------------------
# Test 1 — Scalar 2×2 matrix multiply (RV32IM, 128-bit packed data)
# ---------------------------------------------------------------------------


@cocotb.test()
async def test_matmul_scalar(dut):
    """
    Scalar matrix multiplication (2×2) using RV32IM on the 128-bit data bus.
    Each scalar value is packed into the lower 32 bits of a 128-bit word.
    """
    # Program Memory (32-bit instructions)
    program_memory = Memory(
        dut=dut, addr_bits=8, data_bits=32, channels=1, name="program"
    )

    # Register allocation:
    # x0 = zero
    # x1 = i = blockIdx * blockDim + threadIdx
    # x2 = increment (1)
    # x3 = N (2)
    # x4 = baseA (0)
    # x5 = baseB (4)
    # x6 = baseC (8)
    # x7 = row = i // N
    # x8 = temp
    # x9 = col = i % N
    # x10 = acc
    # x11 = k
    # x12 = addr / A element
    # x13 = addr / B element
    # x14 = A * B
    # x15 = addr(C[i])

    x0, x1, x2, x3, x4, x5, x6 = 0, 1, 2, 3, 4, 5, 6
    x7, x8, x9, x10, x11 = 7, 8, 9, 10, 11
    x12, x13, x14, x15 = 12, 13, 14, 15

    # Build program (we'll insert the correct branch offset afterward)
    program = [
        # i = blockIdx * blockDim + threadIdx
        rv32_mul(x1, X_BLOCK_IDX, X_BLOCK_DIM),  # x1 = blockIdx * blockDim
        rv32_add(x1, x1, X_THREAD_IDX),  # x1 += threadIdx
        # Constants
        rv32_addi(x2, x0, 1),  # increment = 1
        rv32_addi(x3, x0, 2),  # N = 2
        rv32_addi(x4, x0, 0),  # baseA = 0
        rv32_addi(x5, x0, 4),  # baseB = 4
        rv32_addi(x6, x0, 8),  # baseC = 8
        # row = i // N, col = i % N
        rv32_div(x7, x1, x3),  # row = i // N
        rv32_mul(x8, x7, x3),  # x8 = row * N
        rv32_sub(x9, x1, x8),  # col = i - row * N
        # acc = 0, k = 0
        rv32_addi(x10, x0, 0),  # acc = 0
        rv32_addi(x11, x0, 0),  # k = 0
        # --- LOOP start (instruction index 15) ---
        # addr(A) = row * N + k + baseA
        rv32_mul(x12, x7, x3),  # x12 = row * N
        rv32_add(x12, x12, x11),  # x12 += k
        rv32_add(x12, x12, x4),  # x12 += baseA
        rv32_lw(x12, x12, 0),  # x12 = A[addr]
        # addr(B) = k * N + col + baseB
        rv32_mul(x13, x11, x3),  # x13 = k * N
        rv32_add(x13, x13, x9),  # x13 += col
        rv32_add(x13, x13, x5),  # x13 += baseB
        rv32_lw(x13, x13, 0),  # x13 = B[addr]
        # acc += A * B
        rv32_mul(x14, x12, x13),  # x14 = A * B
        rv32_add(x10, x10, x14),  # acc += x14
        # k += 1
        rv32_add(x11, x11, x2),  # k += increment
        # branch back to LOOP if k < N
        # We need to fill this in after we know the instruction count
        0,  # placeholder for blt x11, x3, LOOP
        # addr(C[i]) = baseC + i
        rv32_add(x15, x6, x1),  # x15 = baseC + i
        rv32_sw(x15, x10, 0),  # C[i] = acc
        # thread done
        rv32_ret(),
    ]

    # Compute branch offset: target is LOOP start, current is branch instruction.
    # RV32I branch immediate = target_PC - branch_PC (byte offset).
    # LOOP starts at instruction index 12, branch is at index 23.
    # target_PC = 12 * 4 = 48, branch_PC = 23 * 4 = 92
    # offset = 48 - 92 = -44
    loop_start_idx = program.index(rv32_mul(x12, x7, x3))  # first LOOP instruction
    branch_idx = program.index(0)  # placeholder
    branch_offset = (loop_start_idx - branch_idx) * 4
    program[branch_idx] = rv32_blt(x11, x3, branch_offset)

    # Data Memory (128-bit words, scalar values in lower 32 bits)
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=128, channels=4, name="data")

    def pack_scalar(val):
        return val & 0xFFFFFFFF

    data = [
        # Matrix A (2×2) at addresses 0-3
        pack_scalar(1),
        pack_scalar(2),
        pack_scalar(3),
        pack_scalar(4),
        # Matrix B (2×2) at addresses 4-7
        pack_scalar(1),
        pack_scalar(2),
        pack_scalar(3),
        pack_scalar(4),
        # Result area C at addresses 8-11
        0,
        0,
        0,
        0,
    ]

    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads,
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

    # Verify results
    # A = [[1, 2], [3, 4]], B = [[1, 2], [3, 4]]
    # C[0] = 1*1 + 2*3 = 7, C[1] = 1*2 + 2*4 = 10
    # C[2] = 3*1 + 4*3 = 15, C[3] = 3*2 + 4*4 = 22
    expected_results = [7, 10, 15, 22]
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + 8] & 0xFFFFFFFF
        assert result == expected, (
            f"Result mismatch at index {i}: expected {expected}, got {result}"
        )


# ---------------------------------------------------------------------------
# Test 2 — Phase 7: VDP4A_I4 vector dot-product across 4 threads
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

    x0, x1, x2, x3, x4 = 0, 1, 2, 3, 4
    x_block_idx, x_block_dim, x_thread_idx = 13, 14, 15
    v0, v1, v2, v3 = 0, 1, 2, 3

    from .helpers.rv32i import rv32_vlw_q, rv32_vsw_q, rv32_custom2, VALU_VDP4A_I4

    program = [
        # i = blockIdx * blockDim + threadIdx
        rv32_mul(x1, x_block_idx, x_block_dim),  # x1 = blockIdx * blockDim
        rv32_add(x1, x1, x_thread_idx),  # x1 += threadIdx  → i
        # Load 128-bit row A[i] from address i into vector register v1
        rv32_vlw_q(v1, x1),  # v1 = mem[i] (VLW.Q)
        # Load 128-bit column B from address 4 into v2
        rv32_addi(x2, x0, 4),  # x2 = 4
        rv32_vlw_q(v2, x2),  # v2 = mem[4] (VLW.Q)
        # VDP4A_I4 v3, v1, v2, v0  (v0 = 0, no prior accumulation)
        rv32_custom2(v3, v1, v2, VALU_VDP4A_I4),  # v3 = dp4a(v1, v2, v0)
        # Compute output address = 8 + i and store 128-bit result
        rv32_addi(x3, x0, 8),  # x3 = 8 (output base)
        rv32_add(x4, x3, x1),  # x4 = 8 + i
        rv32_vsw_q(x4, v3),  # mem[x4] = v3 (VSW.Q)
        rv32_ret(),  # RET
    ]

    program_memory = Memory(
        dut=dut, addr_bits=8, data_bits=32, channels=1, name="program"
    )

    # ---- Data memory (128-bit words, VECTOR_ENABLE=1) ----
    a_row = 0x11111111_11111111_11111111_11111111  # all INT4 = 1
    b_col = 0x11111111_11111111_11111111_11111111  # all INT4 = 1

    data_memory = Memory(dut=dut, addr_bits=8, data_bits=128, channels=4, name="data")

    data = [
        a_row,  # addr 0: A row for thread 0
        a_row,  # addr 1: A row for thread 1
        a_row,  # addr 2: A row for thread 2
        a_row,  # addr 3: A row for thread 3
        b_col,  # addr 4: B column (shared)
    ]

    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads,
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
    expected_lane = 8
    expected_128 = (
        expected_lane
        | (expected_lane << 32)
        | (expected_lane << 64)
        | (expected_lane << 96)
    )

    for thread_i in range(threads):
        result = data_memory.memory[8 + thread_i]
        assert result == expected_128, (
            f"Thread {thread_i}: VDP4A result mismatch — "
            f"expected 0x{expected_128:032X}, got 0x{result:032X}"
        )

    logger.info("test_vec_dp4a: all VDP4A_I4 results verified ✓")
