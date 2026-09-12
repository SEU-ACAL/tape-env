// Lossless transport stress without libc control flow. The IADDR filter keeps
// trace state confined to one deterministic branch loop so any decoder error
// is attributable to the trace path rather than printf/newlib execution.
#include <stdint.h>
#include <stdio.h>

#define TRACE_CTRL_BASE 0x10060000UL
#define PULP_REG_BASE (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb) (PULP_REG_BASE + ((apb) * 4))

#ifndef TEST_TRACE_ENABLE
#define TEST_TRACE_ENABLE 1
#endif

#ifndef TEST_MINIMAL_DIAGNOSTIC
#define TEST_MINIMAL_DIAGNOSTIC 0
#endif

#ifndef DENSE_LOOP_ITERATIONS
#define DENSE_LOOP_ITERATIONS 2048UL
#endif

// `dense_branch_loop` is 0x44 bytes in the checked rv64imafd image, with its
// final `ret` at offset 0x40. Keep the inclusive IADDR upper limit here so
// the configuration delay immediately following it is never traced.
#define DENSE_LOOP_LAST_PC_OFFSET 0x40UL

extern volatile uint64_t tohost;

static inline void write_reg(uint64_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

__attribute__((noinline)) static void dense_branch_loop(void) {
  volatile uint64_t value = 0;
  for (uint64_t i = 0; i < DENSE_LOOP_ITERATIONS; ++i) {
    value += i;
  }
  asm volatile("" : : "r"(value) : "memory");
}

__attribute__((noinline)) static void settle_controller(void) {
  for (volatile uint64_t i = 0; i < 4096; ++i) {
    asm volatile("nop");
  }
}

int main(void) {
#if TEST_MINIMAL_DIAGNOSTIC
  printf("LOSSLESS_MINIMAL: entry\n");
#endif
#if TEST_TRACE_ENABLE
  const uint64_t loop_start = (uint64_t)dense_branch_loop;
  const uint64_t loop_end = loop_start + DENSE_LOOP_LAST_PC_OFFSET;

  write_reg(PULP_REG(0x18), (uint32_t)loop_start);
  write_reg(PULP_REG(0x19), (uint32_t)(loop_start >> 32));
  write_reg(PULP_REG(0x16), (uint32_t)loop_end);
  write_reg(PULP_REG(0x17), (uint32_t)(loop_end >> 32));
  write_reg(PULP_REG(0x04), 1);  // IADDR range mode.
  write_reg(PULP_REG(0x1d), 1);  // Lossless transport.
  write_reg(PULP_REG(0x1e), 0);  // Retain normal branch-map behavior.
  write_reg(PULP_REG(0x1f), 1);  // No time.
  write_reg(PULP_REG(0x20), 1);  // No context.
  write_reg(PULP_REG(0x1c), 1);
  write_reg(TRACE_CTRL_BASE, 3);

  // The filter intentionally excludes this delay. It lets the decoupled
  // TL-to-APB programming path settle before the measured loop starts.
  settle_controller();
#endif
#if TEST_MINIMAL_DIAGNOSTIC
  printf("LOSSLESS_MINIMAL: loop\n");
#endif
  dense_branch_loop();
#if TEST_MINIMAL_DIAGNOSTIC
  printf("LOSSLESS_MINIMAL: complete\n");
#endif
  asm volatile(
      "li t0, 1\n"
      "la t1, tohost\n"
      "sd t0, 0(t1)\n"
      "1: j 1b\n"
      ::: "t0", "t1", "memory");
  __builtin_unreachable();
}
