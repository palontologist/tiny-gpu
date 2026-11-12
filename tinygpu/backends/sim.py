from __future__ import annotations

from typing import Any, Sequence

from ..buffer import Buffer
from ..device import Device, DeviceCaps
from ..kernel import Kernel


class SimulatorDevice(Device):
    """Simulator backend stub.

    Intended to drive the RTL simulation (Icarus Verilog + cocotb tests in /test)
    or a future fast functional ISA simulator. Currently a placeholder that records
    operations for bring-up.
    """

    def __init__(self, rtl_root: str | None = None):
        self.rtl_root = rtl_root
        self._next_handle = 1
        self._mem: dict[int, bytearray] = {}

    def caps(self) -> DeviceCaps:
        # TODO: read from RTL params or sim config
        return DeviceCaps(
            name="tiny-gpu-sim",
            num_cores=2,
            threads_per_block=4,
            vector_width_bits=128,
            supported_dtypes=["i32", "i8", "i4"],
            unified_memory=True,
            has_custom_int4_dp4a=True,
            has_vector_simd=True,
        )

    def alloc(self, size_bytes: int, dtype: str = "i32") -> Buffer:
        h = self._next_handle; self._next_handle += 1
        self._mem[h] = bytearray(size_bytes)
        return Buffer(device=self, size_bytes=size_bytes, dtype=dtype, handle=h)

    def free(self, buf: Buffer) -> None:
        if buf.handle in self._mem:
            del self._mem[buf.handle]

    def copy_to_device(self, buf: Buffer, host_data: Any) -> None:
        # TODO: marshal host_data into bytearray / program memory image
        raise NotImplementedError("sim copy_to_device: wire up to cocotb/RTL memory model")

    def copy_from_device(self, buf: Buffer) -> Any:
        raise NotImplementedError("sim copy_from_device: wire up to cocotb/RTL memory model")

    def compile(self, name: str, source: Any) -> Kernel:
        # source: list of 32-bit instruction words (RV32IM/custom) or asm text
        return Kernel(name=name, binary=source, metadata={"format": "rv32_words"})

    def launch(self, kernel: Kernel, grid: Sequence[int], args: Sequence[Any]) -> Any:
        # TODO: invoke iverilog/cocotb run or functional sim with program+data
        raise NotImplementedError("sim launch: integrate with test harness / iverilog")

    def sync(self, handle: Any = None) -> None:
        return None
