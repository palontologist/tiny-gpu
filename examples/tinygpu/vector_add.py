"""End-to-end vector-add example (scaffold).

This illustrates the intended runtime flow:
  1) get device (simulator backend)
  2) allocate buffers
  3) copy inputs
  4) compile/launch kernel
  5) copy back and verify

The SimulatorDevice launch/copy paths are stubs; wire them to the RTL test
harness (test/test_matadd.py style) or a functional ISA simulator to run.
"""

from tinygpu.backends.sim import SimulatorDevice
from tinygpu import codegen


def main():
    dev = SimulatorDevice(rtl_root=".")
    print("caps:", dev.caps())

    n = 8
    # Host data (conceptual)
    a = list(range(n))
    b = list(range(n))

    # Buffers
    buf_a = dev.alloc(n * 4, dtype="i32")
    buf_b = dev.alloc(n * 4, dtype="i32")
    buf_c = dev.alloc(n * 4, dtype="i32")

    # Kernel program (instruction words) - placeholder
    program = codegen.emit_vector_add_i32(a_base=0, b_base=n, c_base=2 * n, n=n)
    kernel = dev.compile("vector_add", program)

    # TODO: dev.copy_to_device(...); dev.launch(...); dev.sync(); out = dev.copy_from_device(...)
    print("kernel:", kernel)
    print("buffers:", buf_a, buf_b, buf_c)
    print("TODO: connect SimulatorDevice to RTL sim (see test/test_matadd.py)")


if __name__ == "__main__":
    main()
