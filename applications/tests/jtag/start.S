.section .text.init, "ax", @progbits
.globl _start
.type _start, @function

_start:
  la sp, __stack_top
  call main
1:
  j 1b

# A fixed-width instruction stream for JTAG single-step stress.  Use explicit
# 32-bit encodings so every successful step advances PC by exactly four bytes.
.section .text.gdb_step_stress, "ax", @progbits
.align 2
.globl gdb_step_stress
.type gdb_step_stress, @function
gdb_step_stress:
.rept 256
  .4byte 0x00128293       # addi t0, t0, 1
.endr
  j gdb_step_stress
.size gdb_step_stress, .-gdb_step_stress
