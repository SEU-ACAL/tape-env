set pagination off
set confirm off
set remotetimeout 120

file build/gdb-loop.elf
target extended-remote :3335
monitor halt

# RV64 Rocket type-2 controls: dmode=1, action=1, M-mode enabled.
set $ctl_x_eq    = 0x2800000000001044
set $ctl_x_napot = 0x28000000000010c4
set $ctl_x_ge    = 0x2800000000001144
set $ctl_x_lt    = 0x28000000000011c4
set $ctl_r_eq    = 0x2800000000001041
set $ctl_w_eq    = 0x2800000000001042

set $tselect = 0
set $tdata1 = 0

printf "TRIGGER_EXACT\n"
set $tdata2 = &gdb_marker
set $tdata1 = $ctl_x_eq
set $pc = _start
continue
print/x $pc
print/x $dcsr
set $tdata1 = 0

printf "TRIGGER_NAPOT_16B\n"
# 0x80000007 encodes [0x80000000, 0x8000000f].
set $tdata2 = 0x80000007
set $tdata1 = $ctl_x_napot
set $pc = _start
continue
print/x $pc
print/x $dcsr
set $tdata1 = 0

printf "TRIGGER_UNSIGNED_GE\n"
set $tdata2 = &main
set $tdata1 = $ctl_x_ge
set $pc = _start
continue
print/x $pc
print/x $dcsr
set $tdata1 = 0

printf "TRIGGER_UNSIGNED_LT\n"
set $tdata2 = &main
set $tdata1 = $ctl_x_lt
set $pc = _start
continue
print/x $pc
print/x $dcsr
set $tdata1 = 0

printf "TRIGGER_LOAD_ADDRESS\n"
set $tdata2 = &gdb_counter
set $tdata1 = $ctl_r_eq
set $pc = main
continue
print/x $pc
print/x $dcsr
set $tdata1 = 0

printf "TRIGGER_STORE_ADDRESS\n"
set $tdata2 = &gdb_counter
set $tdata1 = $ctl_w_eq
set $pc = main
continue
print/x $pc
print/x $dcsr
set $tdata1 = 0

printf "TRIGGER_UNSUPPORTED_MASK_LOW\n"
set $tdata2 = &gdb_marker
# match=4 occupies standard tdata1[10:7]. Rocket reads it back as match=0.
set $tdata1 = $ctl_x_eq + 0x200
print/x $tdata1
set $tdata1 = 0

disconnect
quit
