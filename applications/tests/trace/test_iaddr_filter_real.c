// Focused RV64 IADDR filter test.  The filtered block has four fixed-width
// instructions so each equality/range setting has a decoder-visible boundary.
#include <stdint.h>
#include <stdio.h>

#define TRACE_CTRL_BASE 0x10060000UL
#define PULP_REG_BASE   (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb)   (PULP_REG_BASE + ((apb) * 4))

#ifndef IADDR_ENABLE_MODE
#define IADDR_ENABLE_MODE 3u
#endif

#ifndef IADDR_MATCH_OFFSET
#define IADDR_MATCH_OFFSET 0u
#endif

#ifndef IADDR_LOWER_OFFSET
#define IADDR_LOWER_OFFSET 0u
#endif

#ifndef IADDR_UPPER_OFFSET
#define IADDR_UPPER_OFFSET 12u
#endif

#ifndef LOSSLESS_TRACE
#define LOSSLESS_TRACE 0u
#endif

#ifndef PRIV_ENABLE_MODE
#define PRIV_ENABLE_MODE 0u
#endif

#ifndef PRIV_MATCH
#define PRIV_MATCH 0u
#endif

#ifndef PRIV_RANGE
#define PRIV_RANGE 0u
#endif

extern volatile uint64_t tohost;

static inline void write_reg(uint64_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

// rv64imafd has no compressed ISA extension in this test build.  Keep a
// fixed four-instruction sequence so `block + 2` is provably not an IADDR.
__attribute__((naked, noinline, aligned(4))) static void traced_block(void) {
  asm volatile(
      "nop\n"
      "nop\n"
      "nop\n"
      "ret\n");
}

static void write_iaddr64(unsigned low_word, uint64_t value) {
  write_reg(PULP_REG(low_word), (uint32_t)value);
  write_reg(PULP_REG(low_word + 1), (uint32_t)(value >> 32));
}

static void drain_unqualified(void) {
  for (volatile unsigned long i = 0; i < 10000UL; ++i)
    asm volatile("nop");
}

int main(void) {
  const uint64_t block = (uint64_t)(uintptr_t)traced_block;

  printf("IADDR_DIAG: setup block=%lx\n", block);

  // Program the complete filter before either trace state or transport is
  // enabled.  Setup instructions cannot satisfy this fixed code-address
  // filter, so the capture begins only when traced_block is called below.
  write_iaddr64(0x16, block + IADDR_UPPER_OFFSET);
  write_iaddr64(0x18, block + IADDR_LOWER_OFFSET);
  write_iaddr64(0x1a, block + IADDR_MATCH_OFFSET);
  write_reg(PULP_REG(0x04), IADDR_ENABLE_MODE);
  write_reg(PULP_REG(0x15), PRIV_MATCH);
  // PRIV_RANGE packs lower in bits [1:0] and upper in bits [3:2].
  write_reg(PULP_REG(0x14), PRIV_RANGE);
  write_reg(PULP_REG(0x03), PRIV_ENABLE_MODE);
  // IADDR qualification is tested independently of the sustained-lossless
  // stress case.  The capture has at most one tiny filtered block, so this
  // mode cannot lose data while avoiding transport-stall confounding.
  write_reg(PULP_REG(0x1d), LOSSLESS_TRACE);
  write_reg(PULP_REG(0x1c), 1);  // TRACE_STATE.
  write_reg(TRACE_CTRL_BASE, 3); // Controller/SPI enable last.

  printf("IADDR_DIAG: enabled\n");

  traced_block();

  printf("IADDR_DIAG: block complete\n");

  // No subsequent instruction matches the block address.  Retain enough
  // cycles for the final EndedRep packet to leave the SPI transport.
  drain_unqualified();
  tohost = 1;
  while (1)
    ;
}
