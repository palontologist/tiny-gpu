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
    rv32_lw,
    rv32_sw,
    rv32_ret,
    X_BLOCK_IDX,
    X_BLOCK_DIM,
    X_THREAD_IDX,
)


@cocotb.test()
async def test_matadd(dut):
    """
    Scalar matrix addition (1×8) using RV32I on the 128-bit data bus.
    Each scalar value is packed into the lower 32 bits of a 128-bit word.
    """
    # Program Memory (32-bit instructions)
    program_memory = Memory(
        dut=dut, addr_bits=8, data_bits=32, channels=1, name="program"
    )

    # Register allocation:
    # x0 = zero, x1 = i, x2 = baseA, x3 = baseB, x4 = baseC
    # x5 = addr(A[i]) / A[i], x6 = addr(B[i]) / B[i]
    # x7 = C[i], x8 = addr(C[i])
    x0, x1, x2, x3, x4 = 0, 1, 2, 3, 4
    x5, x6, x7, x8 = 5, 6, 7, 8

    program = [
        # i = blockIdx * blockDim + threadIdx
        rv32_mul(x1, X_BLOCK_IDX, X_BLOCK_DIM),  # x1 = blockIdx * blockDim
        rv32_add(x1, x1, X_THREAD_IDX),  # x1 += threadIdx
        # base addresses
        rv32_addi(x2, x0, 0),  # baseA = 0
        rv32_addi(x3, x0, 8),  # baseB = 8
        rv32_addi(x4, x0, 16),  # baseC = 16
        # load A[i]
        rv32_add(x5, x2, x1),  # addr(A[i]) = baseA + i
        rv32_lw(x5, x5, 0),  # x5 = A[i]
        # load B[i]
        rv32_add(x6, x3, x1),  # addr(B[i]) = baseB + i
        rv32_lw(x6, x6, 0),  # x6 = B[i]
        # C[i] = A[i] + B[i]
        rv32_add(x7, x5, x6),  # x7 = x5 + x6
        # store C[i]
        rv32_add(x8, x4, x1),  # addr(C[i]) = baseC + i
        rv32_sw(x8, x7, 0),  # mem[addr(C[i])] = C[i]
        # thread done
        rv32_ret(),
    ]

    # Data Memory (128-bit words, scalar values in lower 32 bits)
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=128, channels=4, name="data")

    # Pack 8-bit values into lower 32 bits of each 128-bit word
    def pack_scalar(val):
        return val & 0xFFFFFFFF

    data = []
    # Matrix A (addresses 0-7)
    for i in range(8):
        data.append(pack_scalar(i))
    # Matrix B (addresses 8-15)
    for i in range(8):
        data.append(pack_scalar(i))
    # Result area C (addresses 16-23) - initialized to 0
    for i in range(8):
        data.append(0)

    threads = 8

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads,
    )

    data_memory.display(24)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)

        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(24)

    # Verify results (lower 32 bits of each 128-bit word)
    expected_results = [a + b for a, b in zip(range(8), range(8))]
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + 16] & 0xFFFFFFFF
        assert result == expected, (
            f"Result mismatch at index {i}: expected {expected}, got {result}"
        )
