import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from .helpers.logger import logger


@cocotb.test()
async def test_rasterizer_triangle(dut):
    """
    Test Phase 6 Graphics Rasterizer.
    Submits a 2D triangle in 16.16 fixed-point screen space:
      v0 = (10.0, 10.0) -> 0x000A0000
      v1 = (30.0, 10.0) -> 0x001E0000
      v2 = (10.0, 30.0) -> 0x000A0000, 0x001E0000
    Verifies that covered fragments are emitted with valid barycentric coordinates.
    """
    # Start clock if rasterizer is top-level or clocked
    if hasattr(dut, "clk"):
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    if hasattr(dut, "reset"):
        dut.reset.value = 1
        if hasattr(dut, "enable"):
            dut.enable.value = 1
        if hasattr(dut, "tri_valid"):
            dut.tri_valid.value = 0
        if hasattr(dut, "frag_ready"):
            dut.frag_ready.value = 1

        for _ in range(5):
            await RisingEdge(dut.clk)
        dut.reset.value = 0
        await RisingEdge(dut.clk)

    # If this is the standalone rasterizer DUT
    if hasattr(dut, "tri_valid"):
        # 16.16 fixed point helper
        def fp16_16(val):
            return int(val * 65536) & 0xFFFFFFFF

        v0_x, v0_y = fp16_16(10), fp16_16(10)
        v1_x, v1_y = fp16_16(30), fp16_16(10)
        v2_x, v2_y = fp16_16(10), fp16_16(30)

        dut.v0_x.value = v0_x
        dut.v0_y.value = v0_y
        dut.v1_x.value = v1_x
        dut.v1_y.value = v1_y
        dut.v2_x.value = v2_x
        dut.v2_y.value = v2_y
        dut.tri_valid.value = 1
        dut.frag_ready.value = 1

        await RisingEdge(dut.clk)
        dut.tri_valid.value = 0

        fragments = []
        timeout = 2000
        cycles = 0

        while cycles < timeout:
            await RisingEdge(dut.clk)
            cycles += 1
            if dut.frag_valid.value == 1:
                fx = int(dut.frag_x.value)
                fy = int(dut.frag_y.value)
                w0 = int(dut.frag_w0.value)
                w1 = int(dut.frag_w1.value)
                w2 = int(dut.frag_w2.value)
                fragments.append((fx, fy, w0, w1, w2))
            if dut.tri_ready.value == 1 and cycles > 10:
                break

        logger.info(f"Rasterization completed in {cycles} cycles, produced {len(fragments)} fragments.")
        assert len(fragments) > 0, "Rasterizer should have produced at least one fragment"

        # Verify all fragments are inside the bounding box [10, 30] x [10, 30]
        for fx, fy, w0, w1, w2 in fragments:
            assert 10 <= fx <= 30, f"Fragment X {fx} outside bounding box"
            assert 10 <= fy <= 30, f"Fragment Y {fy} outside bounding box"
            assert w0 >= 0 and w1 >= 0 and w2 >= 0, f"Negative barycentric weight at ({fx}, {fy})"
