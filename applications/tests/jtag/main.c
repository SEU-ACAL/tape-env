#include <stdint.h>

volatile uint64_t gdb_counter;

// FESVR requires these standard symbols to initialize the SimTSI transport.
// This smoke workload intentionally never writes tohost, so the P2E JTAG run
// remains available until the user stops it.
volatile uint64_t tohost __attribute__((section(".tohost"), aligned(64)));
volatile uint64_t fromhost __attribute__((section(".tohost"), aligned(64)));

__attribute__((noinline)) void gdb_marker(void) {
  __asm__ volatile("nop");
}

void main(void) {
  for (;;) {
    gdb_counter++;
    gdb_marker();
  }
}
