# ==============================================================================
# tiny-gpu Bare-Metal CRT0 Startup Assembly
# ==============================================================================

.section .text.init
.global _start
.type _start, @function

_start:
    # Set up global pointer (if needed) and stack pointer
    .option push
    .option norelax
    la sp, _stack_top
    .option pop

    # Clear BSS section
    la t0, _sbss
    la t1, _ebss
bss_clear_loop:
    bge t0, t1, bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j bss_clear_loop

bss_done:
    # Call kernel entry point
    jal ra, main

    # Signal kernel done / thread retirement (CUSTOM0 / RET: opcode 0001011)
    .word 0x0000000B

hang:
    j hang

.size _start, . - _start
