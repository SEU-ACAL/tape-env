// Test: Lossy Mode (FIXED)
// Use printf to ensure proper linking and alignment

#include <stdio.h>
#include <stdint.h>

#define TRACE_CTRL_BASE     0x10060000UL
#define PULP_REG_BASE       (TRACE_CTRL_BASE + 0x40)
#define REG_CONTROL         (TRACE_CTRL_BASE + 0x00)
#define PULP_REG(apb)       (PULP_REG_BASE + ((apb) * 4))

static inline void write_reg(uint64_t addr, uint32_t val) {
    *(volatile uint32_t*)addr = val;
}

static inline uint32_t read_reg(uint64_t addr) {
    return *(volatile uint32_t*)addr;
}

extern volatile uint64_t tohost;

static void drain_trace_transport(void) {
    /* Keep the controller/SPI path enabled until its final frame is sent. */
    for (volatile unsigned long i = 0; i < 10000UL; ++i)
        asm volatile ("nop");
}

int main(void) {
    printf("\n=== LOSSY MODE TEST ===\n");

    // Configure LOSSY mode (lossless=0)
    printf("Setting LOSSY mode...\n");
    write_reg(PULP_REG(0x1D), 0x0);

    printf("LOSSLESS_TRACE: 0x%x (should be 0)\n", read_reg(PULP_REG(0x1D)));

    // Enable tracer
    write_reg(PULP_REG(0x1C), 0x1);
    // Enable the controller only after the PULP configuration commits.
    write_reg(REG_CONTROL, 0x3);

    // Generate HIGH instruction rate to test lossy behavior
    printf("Generating 5000 instructions...\n");

    volatile register uint64_t sum = 0;
    for (volatile int i = 0; i < 5000; i++) {
        sum = sum + i;
        sum = sum - 1;
        sum = sum + 2;
    }

    printf("Instruction burst complete, sum=0x%lx\n", sum);

    // Disable tracer
    write_reg(PULP_REG(0x1C), 0x0);

    printf("=== LOSSY MODE TEST DONE ===\n");
    printf("Check TRACE_SPI_RECONSTRUCT_SUMMARY\n");

    drain_trace_transport();
    tohost = 1;
    while (1);
    return 0;
}
