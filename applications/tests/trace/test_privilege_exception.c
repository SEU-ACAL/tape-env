// End-to-end PULP trace stimulus: execute a real U-mode block, take an ecall
// exception (mcause=8), and return to M-mode.  This avoids treating APB
// register readback as proof of privilege or exception filtering.
#include <stdint.h>
#include <stdio.h>

#define TRACE_CTRL_BASE 0x10060000UL
#define PULP_REG_BASE   (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb)   (PULP_REG_BASE + ((apb) * 4))

extern volatile uint64_t tohost;

static inline void write_reg(uint64_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

__attribute__((naked, noreturn)) static void trap_handler(void) {
  asm volatile(
      "li t2, 10000\n"
      "1: addi t2, t2, -1\n"
      "bnez t2, 1b\n"
      "li t0, 1\n"
      "la t1, tohost\n"
      "sd t0, 0(t1)\n"
      "2: j 2b\n");
}

// Do not use a C frame, stack, or data access in U-mode: this bare-metal
// test has no U-mode PMP mapping.  Its first and only exception must be the
// intended ECALL from U-mode (mcause=8).
__attribute__((naked, noreturn)) static void user_block(void) {
  asm volatile(
      "li t0, 4\n"
      "1: addi t0, t0, -1\n"
      "bnez t0, 1b\n"
      "ecall\n"
      "2: j 2b\n");
}

__attribute__((noreturn)) static void enter_user(void (*entry)(void)) {
  asm volatile(
      "csrw mepc, %0\n"
      "csrr t0, mstatus\n"
      "li t1, -6145\n"            // clear MPP[12:11]
      "and t0, t0, t1\n"          // MPP=U for the first mret
      "csrw mstatus, t0\n"
      "mret\n"
      :: "r"(entry) : "t0", "t1", "memory");
  __builtin_unreachable();
}

int main(void) {
  printf("TRACE_PRIV_EXCEPTION_BEGIN\n");
  asm volatile("csrw mtvec, %0" :: "r"(trap_handler));

  // Keep the U-mode ECALL in M-mode so the selected mtvec handler observes
  // the intended return path.  Otherwise a reset-default medeleg can send it
  // to an uninitialized stvec and turn this focused mret test into an access
  // fault test.
  asm volatile("csrw medeleg, zero" ::: "memory");

  // The bare-metal image runs in M-mode by default.  Allow the intended
  // U-mode code/data accesses before mret so its first trap is the ecall.
  asm volatile(
      "li t0, -1\n"
      "csrw pmpaddr0, t0\n"
      "li t0, 0x1f\n"  // NAPOT, R/W/X
      "csrw pmpcfg0, t0\n"
      ::: "t0", "memory");

  // Program every PULP register before enabling the controller.  Each write
  // crosses a decoupled TL-to-APB bridge, so enabling first can trace the
  // setup instructions while the filters are still being applied.
  // Match only U mode and match U-mode ecall cause 8.
  write_reg(PULP_REG(0x15), 0);     // PRIV_MATCH = U
  write_reg(PULP_REG(0x03), 3);     // enable privilege equality mode
  write_reg(PULP_REG(0x07), 8);     // CAUSE_MATCH = ecall from U
  write_reg(PULP_REG(0x00), 3);     // enable cause equality mode
  write_reg(PULP_REG(0x1D), 1);     // lossless: retain the F3/SF1 trap packet
  write_reg(PULP_REG(0x1C), 1);     // TRACE_STATE
  write_reg(TRACE_CTRL_BASE, 3);    // enable after all PULP settings commit
  enter_user(user_block);
}
