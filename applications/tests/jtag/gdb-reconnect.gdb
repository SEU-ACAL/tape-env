set pagination off
set confirm off
set remotetimeout 120
set logging file jtag-reconnect.log
set logging overwrite on
set logging enabled on

file build/gdb-loop.elf
target extended-remote :3335
monitor halt
printf "PC_AFTER_NEW_CONNECTION="
print/x $pc
printf "GPR_A0_AFTER_NEW_CONNECTION="
print/x $a0
printf "SBA_SCRATCH_AFTER_NEW_CONNECTION="
x/gx 0x80100000
disconnect
quit
