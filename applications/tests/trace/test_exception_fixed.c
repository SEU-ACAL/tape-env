// Test: Exception Cause Filtering (FIXED)
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
    printf("\n=== EXCEPTION FILTER TEST ===\n");

    // Configure CAUSE filter registers
    printf("\n--- Configuring CAUSE filter ---\n");

    // CAUSE_LOWER = 0 (lowest exception code)
    write_reg(PULP_REG(0x06), 0x0);

    // CAUSE_UPPER = 15 (highest exception code to trace)
    write_reg(PULP_REG(0x05), 0x0F);

    // CAUSE_MATCH = 2 (illegal instruction exception)
    write_reg(PULP_REG(0x07), 0x2);

    // Keep tracing disabled while PULP APB configuration is in flight.
    write_reg(REG_CONTROL, 0x3);

    printf("CAUSE_LOWER: 0x%x\n", read_reg(PULP_REG(0x06)));
    printf("CAUSE_UPPER: 0x%x\n", read_reg(PULP_REG(0x05)));
    printf("CAUSE_MATCH: 0x%x\n", read_reg(PULP_REG(0x07)));

    // TEST 1: No exception filtering
    printf("\n--- Test 1: No Filter ---\n");
    write_reg(PULP_REG(0x00), 0x0);  // Disable CAUSE filter
    write_reg(PULP_REG(0x1D), 0x1);  // Lossless
    write_reg(PULP_REG(0x1C), 0x1);  // Enable

    volatile int sum1 = 0;
    for (int i = 0; i < 100; i++) {
        sum1 += i;
    }

    write_reg(PULP_REG(0x1C), 0x0);
    printf("All instructions traced (no exceptions)\n");

    // TEST 2: Range mode - trace exceptions in range
    printf("\n--- Test 2: Range mode ---\n");

    // CAUSE_ENABLE_MODE = 0x1 (range mode: trace if LOWER <= cause <= UPPER)
    write_reg(PULP_REG(0x00), 0x1);

    printf("CAUSE_ENABLE: 0x%x\n", read_reg(PULP_REG(0x00)));

    write_reg(PULP_REG(0x1C), 0x1);

    volatile int sum2 = 0;
    for (int i = 0; i < 100; i++) {
        sum2 += i;
    }

    write_reg(PULP_REG(0x1C), 0x0);
    printf("Normal execution traced\n");

    // TEST 3: Match mode - only trace specific exception
    printf("\n--- Test 3: Match mode ---\n");

    // CAUSE_ENABLE_MODE = 0x2 (match mode: trace if cause == MATCH)
    write_reg(PULP_REG(0x00), 0x2);

    write_reg(PULP_REG(0x1C), 0x1);

    volatile int sum3 = 0;
    for (int i = 0; i < 100; i++) {
        sum3 += i;
    }

    write_reg(PULP_REG(0x1C), 0x0);
    printf("Only exception 2 would be traced\n");

    // Disable filtering
    write_reg(PULP_REG(0x00), 0x0);

    printf("\n=== EXCEPTION FILTER TEST DONE ===\n");
    printf("Note: No exceptions triggered in this test\n");
    printf("Filter registers are configured and readable\n");

    drain_trace_transport();
    tohost = 1;
    while (1);
    return 0;
}
