set pagination off
set confirm off
set remotetimeout 120
set logging file jtag-reset-stepi.log
set logging overwrite on
set logging enabled on

file build/gdb-loop.elf
target extended-remote :3335
monitor halt
monitor riscv set_mem_access sysbus

# VCS reset clears DDR. Reload the workload before single-stepping from it.
monitor reset halt
maintenance flush register-cache
load
set $pc = _start

# The default Rocket implementation has one trigger; keep it free for GDB.
delete breakpoints
set $tselect = 0
set $tdata1 = 0
maintenance flush register-cache

set $reset_stepi_pc_before = $pc
printf "RESET_STEPI_PC_BEFORE="
print/x $reset_stepi_pc_before

# Conformance check for GDB's normal single-step request. A DCSR-backed step
# must report cause=4; cause=1 exposes software-breakpoint emulation instead.
stepi
maintenance flush register-cache
set $reset_stepi_pc_after = $pc
set $reset_stepi_dcsr_cause = ($dcsr >> 6) & 0x7
printf "RESET_STEPI_PC_AFTER="
print/x $reset_stepi_pc_after
printf "RESET_STEPI_DCSR_CAUSE="
print/x $reset_stepi_dcsr_cause

if $reset_stepi_pc_after != $reset_stepi_pc_before + 4
  printf "RESET_STEPI_FAIL: unexpected PC\n"
  disconnect
  quit 1
end
if $reset_stepi_dcsr_cause != 4
  printf "RESET_STEPI_FAIL: expected DCSR single-step cause\n"
  disconnect
  quit 1
end

printf "RESET_STEPI_PASS\n"
disconnect
quit
