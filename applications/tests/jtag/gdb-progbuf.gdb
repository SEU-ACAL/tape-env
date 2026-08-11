set pagination off
set confirm off
set remotetimeout 120

file build/gdb-loop.elf
target extended-remote :3335
monitor halt

# Clear any prior abstract-command error before touching progbuf/data.
monitor riscv dmi_write 0x16 0x00000700

# addi a0, zero, 42; ebreak
monitor riscv dmi_write 0x20 0x02a00513
monitor riscv dmi_write 0x21 0x00100073

printf "PROGBUF0="
monitor riscv dmi_read 0x20
printf "PROGBUF1="
monitor riscv dmi_read 0x21

# Access Register: RV64, transfer, write x0, postexec.
# 0x00371000 = aarsize=3 | postexec | transfer | write | regno=x0.
monitor riscv dmi_write 0x17 0x00371000

# The DMI command launches asynchronously; wait before checking completion.
shell sleep 1
printf "ABSTRACTCS="
monitor riscv dmi_read 0x16
maintenance flush register-cache
printf "PROGBUF_A0="
print/x $a0

disconnect
quit
