"""Codegen scaffolding: lower high-level ops/UOps to tiny-gpu ISA.

Targets:
- RV32IM scalar instructions
- CUSTOM1 (INT4/FP32 DP4A, stubs)
- CUSTOM2 (128-bit vector SIMD: VADD/VMUL/VMADD.I8, VDP4A.I4, etc.)

Start with hand-emitted instruction sequences (see test/helpers/rv32i.py),
then evolve toward a small IR/lowering pipeline.
"""

from __future__ import annotations

from typing import List


def emit_vector_add_i32(a_base: int, b_base: int, c_base: int, n: int) -> List[int]:
    """Placeholder: emit RV32IM/custom instruction words for C[i]=A[i]+B[i].

    TODO: generate actual words using helpers in test/helpers/rv32i.py or a local encoder.
    For now returns empty list as a scaffold marker.
    """
    _ = (a_base, b_base, c_base, n)
    return []
