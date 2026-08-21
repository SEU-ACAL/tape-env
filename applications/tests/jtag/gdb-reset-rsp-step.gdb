set pagination off
set confirm off
set remotetimeout 120
set logging file jtag-reset-rsp-step.log
set logging overwrite on
set logging enabled on

file build/gdb-loop.elf
target extended-remote :3335
monitor halt
monitor riscv set_mem_access sysbus

# VCS reset clears DDR. Reload before executing from the ELF entry point.
monitor reset halt
maintenance flush register-cache
load
set $pc = _start
delete breakpoints
set $tselect = 0
set $tdata1 = 0
maintenance flush register-cache

set $rsp_step_pc_before = $pc
printf "RSP_STEP_PC_BEFORE="
print/x $rsp_step_pc_before

# Send the RSP single-step packet directly. Unlike GDB's stepi in this setup,
# this bypasses GDB's software-next-PC breakpoint emulation.
maintenance packet s
maintenance flush register-cache
set $rsp_step_pc_after = $pc
set $rsp_step_dcsr_cause = ($dcsr >> 6) & 0x7
printf "RSP_STEP_PC_AFTER="
print/x $rsp_step_pc_after
printf "RSP_STEP_DCSR_CAUSE="
print/x $rsp_step_dcsr_cause

if $rsp_step_pc_after != $rsp_step_pc_before + 4
  printf "RSP_STEP_FAIL: unexpected PC\n"
  disconnect
  quit 1
end
if $rsp_step_dcsr_cause != 4
  printf "RSP_STEP_FAIL: expected DCSR single-step cause\n"
  disconnect
  quit 1
end

printf "RSP_STEP_PASS\n"
disconnect
quit
