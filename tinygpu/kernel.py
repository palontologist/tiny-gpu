from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional


@dataclass
class Kernel:
    """Compiled/loaded kernel."""
    name: str
    binary: Any = None        # backend-specific (instruction words, ELF, bitstream handle)
    metadata: Optional[dict] = None
