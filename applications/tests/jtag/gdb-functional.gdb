set pagination off
set confirm off
set remotetimeout 120
set logging file jtag-functional.log
set logging overwrite on
set logging enabled on

file build/gdb-loop.elf
target extended-remote :3335
monitor halt

printf "INITIAL_PC="
print/x $pc
set $a0 = 0x13579bdf
printf "GPR_A0_AFTER_WRITE="
print/x $a0

set $pc = _start
printf "PC_BEFORE_STEPI="
print/x $pc
stepi
printf "PC_AFTER_STEPI="
print/x $pc

set {unsigned long long}0x80100000 = 0x1122334455667788
printf "SBA_SCRATCH_AFTER_WRITE="
x/gx 0x80100000

hbreak gdb_marker
continue
printf "BREAKPOINT_PC="
print/x $pc
set $a0 = 0x2468ace0
printf "GPR_A0_BEFORE_RECONNECT="
print/x $a0
disconnect

# OpenOCD releases its single GDB connection asynchronously. Waiting briefly
# makes this reconnect check exercise a new connection instead of racing cleanup.
shell sleep 2

target extended-remote :3335
monitor halt
printf "PC_AFTER_RECONNECT="
print/x $pc
printf "GPR_A0_AFTER_RECONNECT="
print/x $a0
printf "SBA_SCRATCH_AFTER_RECONNECT="
x/gx 0x80100000
delete
disconnect
quit
