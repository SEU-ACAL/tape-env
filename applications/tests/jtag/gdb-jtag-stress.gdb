set pagination off
set confirm off
set remotetimeout 120
set logging file jtag-stress.log
set logging overwrite on
set logging enabled on

file build/gdb-loop.elf
target extended-remote :3335
monitor halt
monitor riscv set_mem_access sysbus

# VCS reset clears DDR. Reload before stressing instruction and SBA traffic.
monitor reset halt
maintenance flush register-cache
load
set $pc = _start

# Keep the single trigger free; native RSP `s` is the step mechanism here.
delete breakpoints
set $tselect = 0
set $tdata1 = 0
maintenance flush register-cache

# These counts are intentionally visible so a longer run can be selected
# without changing the test logic.
set $step_iterations = 32
set $memory_iterations = 64
set $stress_step_start = &gdb_step_stress
set $pc = $stress_step_start

printf "JTAG_STRESS_STEP_COUNT="
print $step_iterations
set $i = 0
while $i < $step_iterations
  maintenance packet s
  set $expected_pc = $stress_step_start + (($i + 1) * 4)
  if $pc != $expected_pc
    printf "JTAG_STRESS_FAIL: step PC at iteration %d\n", $i
    disconnect
    quit 1
  end
  set $step_cause = ($dcsr >> 6) & 0x7
  if $step_cause != 4
    printf "JTAG_STRESS_FAIL: step cause at iteration %d\n", $i
    disconnect
    quit 1
  end
  set $i = $i + 1
end

printf "JTAG_STRESS_MEMORY_COUNT="
print $memory_iterations
set $stress_memory_base = 0x80102000
set $i = 0
while $i < $memory_iterations
  set $expected_value = 0xa5a5000000000000 | $i
  set {unsigned long long}($stress_memory_base + ($i * 8)) = $expected_value
  set $actual_value = *(unsigned long long *)($stress_memory_base + ($i * 8))
  if $actual_value != $expected_value
    printf "JTAG_STRESS_FAIL: memory at iteration %d\n", $i
    disconnect
    quit 1
  end
  set $i = $i + 1
end

printf "JTAG_STRESS_PASS steps=%d memory=%d\n", $step_iterations, $memory_iterations
disconnect
quit
