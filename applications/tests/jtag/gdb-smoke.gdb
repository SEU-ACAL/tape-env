set pagination off
set confirm off
set remotetimeout 120

file build/gdb-loop.elf
target extended-remote :3333
monitor halt
info registers pc
hbreak gdb_marker
continue
printf "GDB-SMOKE stopped at: "
info symbol $pc
print/x gdb_counter
disconnect
quit
