/* ==============================================================================
 * tiny-gpu Linker Script for Bare-Metal RISC-V Compilation
 * Architecture: RV32IM / RV32IMV
 * ============================================================================== */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    /* Program Memory: 256 words x 32-bit = 1024 Bytes */
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 1K
    /* Global Data Memory: 256 rows x 128-bit = 4096 Bytes */
    RAM (rwx) : ORIGIN = 0x00001000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        . = ALIGN(4);
        *(.text.init)
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
        _etext = .;
    } > ROM

    .data : {
        . = ALIGN(16);
        _sdata = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(16);
        _edata = .;
    } > RAM AT > ROM

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Stack pointer initialization */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
}
