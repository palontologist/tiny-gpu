# ==============================================================================
# tiny-gpu Software Toolchain Makefile
# Builds bare-metal RISC-V kernels targeting RV32IM / RV32IMV
# ==============================================================================

CROSS_COMPILE ?= riscv32-unknown-elf-
CC            = $(CROSS_COMPILE)gcc
OBJCOPY       = $(CROSS_COMPILE)objcopy
OBJDUMP       = $(CROSS_COMPILE)objdump

ARCH_FLAGS    = -march=rv32imv -mabi=ilp32
CFLAGS        = $(ARCH_FLAGS) -O2 -Wall -nostdlib -ffreestanding -I.
LDFLAGS       = -T linker.ld -nostdlib -Wl,--gc-sections

BUILD_DIR     = build
KERNELS_DIR   = kernels
TOOLS_DIR     = tools

KERNEL_SRCS   = $(wildcard $(KERNELS_DIR)/*.c)
KERNEL_BINS   = $(patsubst $(KERNELS_DIR)/%.c, $(BUILD_DIR)/%.bin, $(KERNEL_SRCS))
KERNEL_HEXS   = $(patsubst $(KERNELS_DIR)/%.c, $(BUILD_DIR)/%.hex, $(KERNEL_SRCS))
KERNEL_DUMPS  = $(patsubst $(KERNELS_DIR)/%.c, $(BUILD_DIR)/%.dump, $(KERNEL_SRCS))

.PHONY: all clean

all: $(BUILD_DIR) $(KERNEL_HEXS) $(KERNEL_DUMPS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.elf: $(KERNELS_DIR)/%.c crt0.s linker.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) crt0.s $< $(LDFLAGS) -o $@

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.bin
	python3 $(TOOLS_DIR)/elf2mem.py $< $@ 4

$(BUILD_DIR)/%.dump: $(BUILD_DIR)/%.elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -rf $(BUILD_DIR)
