set pagination off
set confirm off
set remotetimeout 120
set logging file jtag-reset-halt.log
set logging overwrite on
set logging enabled on
file build/gdb-loop.elf
target extended-remote :3335
monitor halt
# This is an SBA test. Do not silently fall back to the program buffer.
monitor riscv set_mem_access sysbus
set $sba_test_address = 0x80100000
set $sba_test_value = 0x8877665544332211
set {unsigned long long}$sba_test_address = $sba_test_value
printf "SBA_BEFORE_RESET="
x/gx $sba_test_address
set $sba_before_reset = *(unsigned long long *)$sba_test_address
if $sba_before_reset != $sba_test_value
  printf "RESET_HALT_FAIL: SBA write before reset\n"
  disconnect
  quit 1
end

monitor reset halt
maintenance flush register-cache
printf "PC_AFTER_RESET_HALT="
print/x $pc
set $pc_after_reset_halt = $pc
printf "SBA_AFTER_RESET_HALT="
x/gx $sba_test_address
set $sba_after_reset = *(unsigned long long *)$sba_test_address
if $pc_after_reset_halt != 0x10000
  printf "RESET_HALT_FAIL: unexpected reset PC\n"
  disconnect
  quit 1
end
if $sba_after_reset != 0
  printf "RESET_HALT_FAIL: VCS DDR was not reset\n"
  disconnect
  quit 1
end

# VCS reset reinitializes the simulated DDR, unlike the P2E reset path. Reload
# the tiny ELF before resuming so the reset test has a valid workload image.
load
set $pc = _start

hbreak gdb_marker
# Exercise the CLINT SBA write, then clear it before entering _start directly.
# The current VCS BootROM does not observe this SBA MSIP write as an interrupt.
set {unsigned int}0x02000000 = 1
set {unsigned int}0x02000000 = 0
# Keep the sole hardware trigger for gdb_marker. A BootROM stepi may need a
# temporary breakpoint and make GDB fall back to patching read-only BootROM.
continue
printf "BREAKPOINT_AFTER_RESET_HALT="
print/x $pc
if $pc < &gdb_marker || $pc >= &main
  printf "RESET_HALT_FAIL: hardware breakpoint missed\n"
  disconnect
  quit 1
end
delete
printf "RESET_HALT_PASS\n"
disconnect
quit
