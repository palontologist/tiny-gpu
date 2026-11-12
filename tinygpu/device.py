from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Sequence

from .buffer import Buffer
from .kernel import Kernel


@dataclass
class DeviceCaps:
    """Runtime-reported capabilities (query, don't hardcode)."""
    name: str = "unknown"
    num_cores: int = 1
    threads_per_block: int = 1
    vector_width_bits: int = 32
    supported_dtypes: list[str] = field(default_factory=lambda: ["i32"])
    unified_memory: bool = True
    has_custom_int4_dp4a: bool = False
    has_vector_simd: bool = False


class Device(ABC):
    """Abstract device interface. Implementations: sim, fpga, (future) native."""

    @abstractmethod
    def caps(self) -> DeviceCaps:
        ...

    @abstractmethod
    def alloc(self, size_bytes: int, dtype: str = "i32") -> Buffer:
        ...

    @abstractmethod
    def free(self, buf: Buffer) -> None:
        ...

    @abstractmethod
    def copy_to_device(self, buf: Buffer, host_data: Any) -> None:
        ...

    @abstractmethod
    def copy_from_device(self, buf: Buffer) -> Any:
        ...

    @abstractmethod
    def compile(self, name: str, source: Any) -> Kernel:
        """Compile/load a kernel. `source` may be ISA words, asm, or IR (backend-defined)."""
        ...

    @abstractmethod
    def launch(self, kernel: Kernel, grid: Sequence[int], args: Sequence[Any]) -> Any:
        """Launch kernel; returns a handle/token for sync (backend-defined)."""
        ...

    @abstractmethod
    def sync(self, handle: Any = None) -> None:
        """Wait for completion."""
        ...
