"""tinygpu: lightweight runtime/codegen scaffold for tiny-gpu.

Targets: RTL simulator (cocotb/iverilog), FPGA, and future unified RISC-V CPU/GPU.
"""

from .device import Device, DeviceCaps
from .buffer import Buffer
from .kernel import Kernel

__all__ = ["Device", "DeviceCaps", "Buffer", "Kernel"]
