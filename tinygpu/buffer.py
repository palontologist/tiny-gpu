from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional


@dataclass
class Buffer:
    """Device buffer handle."""
    device: Any
    size_bytes: int
    dtype: str = "i32"
    handle: Optional[Any] = None  # backend-specific (address/id/object)

    def __repr__(self) -> str:
        return f"Buffer(dtype={self.dtype}, size={self.size_bytes}, handle={self.handle!r})"
