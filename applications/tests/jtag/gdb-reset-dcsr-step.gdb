set pagination off
set confirm off
set remotetimeout 120
set logging file jtag-reset-dcsr-step.log
set logging overwrite on
set logging enabled on

file build/gdb-loop.elf
target extended-remote :3335
monitor halt
monitor riscv set_mem_access sysbus

# VCS reset clears DDR, so reload the workload before executing from _start.
monitor reset halt
maintenance flush register-cache
load
set $pc = _start

# The Rocket configuration has one trigger. Leave it unused for DCSR stepping.
delete breakpoints
set $tselect = 0
set $tdata1 = 0
maintenance flush register-cache

set $dcsr_step_pc_before = $pc
set $dcsr_step_armed = $dcsr | (1 << 2)
set $dcsr = $dcsr_step_armed
printf "DCSR_STEP_PC_BEFORE="
print/x $dcsr_step_pc_before
printf "DCSR_STEP_DCSR_ARMED="
print/x $dcsr

# Do not use GDB `continue` here: OpenOCD's normal resume path owns the
# single-step state and can replace the dcsr value just programmed above.
# DMCONTROL.resumereq is bit 30; dmactive is bit 0.  This is the raw
# Debug-Module resume request, so the hart resumes with dcsr.step still set.
monitor riscv dmi_write 0x10 0x40000001
shell sleep 1
maintenance flush register-cache
set $dcsr_step_pc_after = $pc
set $dcsr_step_cause = ($dcsr >> 6) & 0x7
printf "DCSR_STEP_PC_AFTER="
print/x $dcsr_step_pc_after
printf "DCSR_STEP_CAUSE="
print/x $dcsr_step_cause

# Disable step before returning control to any later GDB client.
set $dcsr = $dcsr & ~(1 << 2)

if $dcsr_step_pc_after != $dcsr_step_pc_before + 4
  printf "DCSR_STEP_FAIL: unexpected PC\n"
  disconnect
  quit 1
end
if $dcsr_step_cause != 4
  printf "DCSR_STEP_FAIL: unexpected DCSR cause\n"
  disconnect
  quit 1
end

printf "DCSR_STEP_PASS\n"
disconnect
quit
