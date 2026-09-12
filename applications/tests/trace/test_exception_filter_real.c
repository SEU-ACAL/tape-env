// Exercise the real CAUSE and 64-bit TVAL equality filters with a U-mode
// ECALL.  The two CMake targets differ only in TVAL_MATCH_LOW: zero selects
// the trap, while one must exclude it.
#include <stdint.h>
#include <stdio.h>

#define TRACE_CTRL_BASE 0x10060000UL
#define PULP_REG_BASE   (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb)   (PULP_REG_BASE + ((apb) * 4))

#ifndef TVAL_MATCH_LOW
#define TVAL_MATCH_LOW 0u
#endif

#ifndef CAUSE_MATCH
#define CAUSE_MATCH 8u
#endif

#ifndef CAUSE_LOWER
#define CAUSE_LOWER 0u
#endif

#ifndef CAUSE_UPPER
#define CAUSE_UPPER 0u
#endif

// bit0 enables the filter; bit1 selects equality (1) over range (0).
#ifndef CAUSE_ENABLE_MODE
#define CAUSE_ENABLE_MODE 3u
#endif

#ifndef PRIV_ENABLE_MODE
#define PRIV_ENABLE_MODE 0u
#endif

#ifndef PRIV_MATCH
#define PRIV_MATCH 0u
#endif

#ifndef TVEC_ENABLE_MODE
#define TVEC_ENABLE_MODE 0u
#endif

#ifndef TVEC_LOWER_OFFSET
#define TVEC_LOWER_OFFSET 0u
#endif

#ifndef TVEC_UPPER_OFFSET
#define TVEC_UPPER_OFFSET 0u
#endif

#ifndef TVEC_MATCH_OFFSET
#define TVEC_MATCH_OFFSET 0u
#endif

extern volatile uint64_t tohost;

static inline void write_reg(uint64_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

__attribute__((naked, noreturn)) static void user_block(void);
__attribute__((noreturn)) static void enter_user(void (*entry)(void));

// End directly from the handler after the wire drain.  Exception-return
// behaviour is deliberately not coupled to this filter test.
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

int main(void) {
  printf("TVAL_DIAG: begin\n");
  asm volatile("csrw mtvec, %0" :: "r"(trap_handler));
  // CSR delegation registers are not reset by this TapeoutRocketConfig
  // implementation.  The U-mode ECALL below must exercise the explicitly
  // installed M-mode handler, rather than a random delegated stvec path.
  asm volatile("csrw medeleg, zero" ::: "memory");

  // Permit the bare U-mode block before trace configuration is enabled.
  asm volatile(
      "li t0, -1\n"
      "csrw pmpaddr0, t0\n"
      "li t0, 0x1f\n"
      "csrw pmpcfg0, t0\n"
      ::: "t0", "memory");
  printf("TVAL_DIAG: pmp ready\n");

  // An ECALL from U-mode is cause 8 with TVAL=0.  Both low and high TVAL
  // halves are programmed on RV64; target-specific defines select CAUSE
  // equality/range and their include/exclude cases.
  write_reg(PULP_REG(0x05), CAUSE_UPPER);
  write_reg(PULP_REG(0x06), CAUSE_LOWER);
  write_reg(PULP_REG(0x07), CAUSE_MATCH);
  write_reg(PULP_REG(0x00), CAUSE_ENABLE_MODE);
  write_reg(PULP_REG(0x15), PRIV_MATCH);
  write_reg(PULP_REG(0x03), PRIV_ENABLE_MODE);
  const uint64_t handler = (uint64_t)(uintptr_t)trap_handler;
  const uint64_t tvec_lower = handler + TVEC_LOWER_OFFSET;
  const uint64_t tvec_upper = handler + TVEC_UPPER_OFFSET;
  const uint64_t tvec_match = handler + TVEC_MATCH_OFFSET;
  write_reg(PULP_REG(0x08), (uint32_t)tvec_upper);
  write_reg(PULP_REG(0x09), (uint32_t)(tvec_upper >> 32));
  write_reg(PULP_REG(0x0a), (uint32_t)tvec_lower);
  write_reg(PULP_REG(0x0b), (uint32_t)(tvec_lower >> 32));
  write_reg(PULP_REG(0x0c), (uint32_t)tvec_match);
  write_reg(PULP_REG(0x0d), (uint32_t)(tvec_match >> 32));
  write_reg(PULP_REG(0x01), TVEC_ENABLE_MODE);
  printf("TVAL_DIAG: cause configured\n");
  write_reg(PULP_REG(0x12), TVAL_MATCH_LOW);    // TVAL_MATCH_L
  write_reg(PULP_REG(0x13), 0);                 // TVAL_MATCH_M (RV64)
  write_reg(PULP_REG(0x02), 3);                 // TVAL equality, enabled
  printf("TVAL_DIAG: tval configured\n");
  write_reg(PULP_REG(0x1D), 1);                 // lossless
  write_reg(PULP_REG(0x1C), 1);                 // trace state
  write_reg(TRACE_CTRL_BASE, 3);                // controller/SPI last
  printf("TVAL_DIAG: trace enabled\n");

  printf("TVAL_DIAG: entering user\n");
  enter_user(user_block);
}

// No stack or data access is performed after MRET.  The short integer loop
// gives the privilege transition several retired instructions before ECALL.
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
      "li t1, -6145\n"
      "and t0, t0, t1\n"
      "csrw mstatus, t0\n"
      "mret\n"
      :: "r"(entry) : "t0", "t1", "memory");
  __builtin_unreachable();
}
