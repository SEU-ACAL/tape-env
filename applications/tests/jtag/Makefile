CROSS_COMPILE ?= riscv64-unknown-elf-
GDB ?= riscv64-unknown-elf-gdb
PYTHON ?= python3
STRESS_STEPS ?= 32
STRESS_MEMORY ?= 64
CC := $(CROSS_COMPILE)gcc
OBJDUMP := $(CROSS_COMPILE)objdump

BUILD_DIR := build
ELF := $(BUILD_DIR)/gdb-loop.elf

CFLAGS := -march=rv64gc -mabi=lp64d -mcmodel=medany -msmall-data-limit=0 \
	-ffreestanding -fno-builtin -fno-pic -fno-pie -g -O0 \
	-nostdlib -nostartfiles -Wall -Wextra
LDFLAGS := -T link.ld -Wl,--build-id=none -Wl,-Map,$(BUILD_DIR)/gdb-loop.map

.PHONY: all clean ci-jtag-test vcs-gdb-regress vcs-gdb-stress vcs-jtag-stress

all: $(ELF)

$(BUILD_DIR):
	mkdir -p $@

$(ELF): start.S main.c link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) start.S main.c -o $@
	$(OBJDUMP) -d -S $@ > $(BUILD_DIR)/gdb-loop.dump

clean:
	rm -rf $(BUILD_DIR)

ci-jtag-test: $(ELF)
	./ci-jtag-test.sh

vcs-gdb-regress: $(ELF)
	GDB="$(GDB)" ./run-vcs-gdb-regressions.sh

vcs-gdb-stress: $(ELF)
	$(GDB) -batch -x gdb-jtag-stress.gdb

vcs-jtag-stress: $(ELF)
	$(PYTHON) jtag-rsp-stress.py --elf $(ELF) --steps $(STRESS_STEPS) --memory $(STRESS_MEMORY)
