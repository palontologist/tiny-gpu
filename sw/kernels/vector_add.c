// ==============================================================================
// Standard Vector Addition Kernel targeting RV32IMV
// Demonstrates upstream Vector-Length Agnostic (VLA) execution on tiny-gpu
// ==============================================================================

#include <stdint.h>

#define N 16

// Global memory input and output arrays
volatile int32_t a[N] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
volatile int32_t b[N] = {10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160};
volatile int32_t c[N] = {0};

void vector_add_rvv(const int32_t *src_a, const int32_t *src_b, int32_t *dst_c, size_t n) {
    size_t vl;
    while (n > 0) {
        // Dynamic vector length configuration: e32 (32-bit elements), m1 (1 register per vector group)
        __asm__ volatile (
            "vsetvli %0, %1, e32, m1, ta, ma"
            : "=r"(vl)
            : "r"(n)
        );

        // Vector unit-stride load, vector add, and vector unit-stride store
        __asm__ volatile (
            "vle32.v v1, (%0)\n\t"
            "vle32.v v2, (%1)\n\t"
            "vadd.vv v3, v1, v2\n\t"
            "vse32.v v3, (%2)\n\t"
            :
            : "r"(src_a), "r"(src_b), "r"(dst_c)
            : "memory"
        );

        src_a += vl;
        src_b += vl;
        dst_c += vl;
        n -= vl;
    }
}

int main(void) {
    vector_add_rvv((const int32_t *)a, (const int32_t *)b, (int32_t *)c, N);
    return 0;
}
