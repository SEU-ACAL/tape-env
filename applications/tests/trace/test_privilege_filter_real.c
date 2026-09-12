// Focused privilege-filter test using a single M-mode ECALL (cause 11).
#include <stdint.h>
#include <stdio.h>

#define TRACE_CTRL_BASE 0x10060000UL
#define PULP_REG_BASE   (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb)   (PULP_REG_BASE + ((apb) * 4))

#ifndef PRIV_ENABLE_MODE
#define PRIV_ENABLE_MODE 3u
#endif

#ifndef PRIV_MATCH
#define PRIV_MATCH 3u
#endif

#ifndef PRIV_RANGE
#define PRIV_RANGE 0u
#endif

#ifndef LOSSLESS_TRACE
#define LOSSLESS_TRACE 0u
#endif

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

int main(void) {
  printf("PRIV_FILTER_DIAG: configure M ecall\n");
  asm volatile("csrw mtvec, %0" :: "r"(trap_handler));

  // The event must pass both filters.  CAUSE isolates the sole ECALL while
  // PRIV_ENABLE_MODE is varied by the two targets below.
  write_reg(PULP_REG(0x07), 11);           // M-mode ECALL cause
  write_reg(PULP_REG(0x00), 3);            // CAUSE equality, enabled
  write_reg(PULP_REG(0x15), PRIV_MATCH);
  write_reg(PULP_REG(0x14), PRIV_RANGE);
  write_reg(PULP_REG(0x03), PRIV_ENABLE_MODE);
  // This sparse semantic test does not pressure the transport.  Keep
  // sustained lossless backpressure validation in its dedicated workload.
  write_reg(PULP_REG(0x1d), LOSSLESS_TRACE);
  write_reg(PULP_REG(0x1c), 1);            // TRACE_STATE
  write_reg(TRACE_CTRL_BASE, 3);           // controller/SPI last
  asm volatile("ecall" ::: "memory");
  __builtin_unreachable();
}
