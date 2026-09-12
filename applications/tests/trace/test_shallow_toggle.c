#include <stdint.h>
#include <stdio.h>

#define TRACE_CTRL_BASE 0x10060000UL
#define PULP_REG_BASE (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb) (PULP_REG_BASE + ((apb) * 4))

static inline void wr(uint64_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

__attribute__((noinline)) static void branch_window(uint64_t rounds) {
  volatile uint64_t acc = 0;
  for (uint64_t i = 0; i < rounds; ++i) {
    if (i & 1) {
      acc += i;
    } else {
      acc ^= i + 3;
    }
  }
  asm volatile("" : : "r"(acc) : "memory");
}

extern volatile uint64_t tohost;

int main(void) {
  // Keep the address filter disabled so APB setup cannot accidentally exclude
  // the completion path. The only behavior varied between phases is the
  // SHALLOW_TRACE bit itself.
  wr(PULP_REG(0x04), 0);
  wr(PULP_REG(0x1d), 1);  // lossless.
  wr(PULP_REG(0x1f), 1);  // no time.
  wr(PULP_REG(0x20), 1);  // no context.
  wr(PULP_REG(0x1e), 0);  // phase A: ordinary branch-map behavior.
  wr(PULP_REG(0x1c), 1);
  wr(TRACE_CTRL_BASE, 3);

  branch_window(256);

  // The same ELF/function is executed again after changing only the
  // SHALLOW_TRACE bit. This APB write is outside the IADDR filter window.
  wr(PULP_REG(0x1e), 1);  // phase B: flush branch map on each packet.
  branch_window(256);

  wr(PULP_REG(0x1c), 0);
  asm volatile(
      "li t0, 1\n"
      "la t1, tohost\n"
      "sd t0, 0(t1)\n"
      "1: j 1b\n"
      ::: "t0", "t1", "memory");
  __builtin_unreachable();
}
