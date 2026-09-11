// Test: Privilege Level Filtering (FIXED)
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

// Read current privilege level from mstatus
static inline uint32_t read_mstatus(void) {
    uint64_t mstatus;
    asm volatile ("csrr %0, mstatus" : "=r"(mstatus));
    return (uint32_t)mstatus;
}

int main(void) {
    printf("\n=== PRIVILEGE FILTER TEST ===\n");

    // Check current privilege (should be Machine mode = 3)
    uint32_t mstatus = read_mstatus();
    printf("mstatus: 0x%x\n", mstatus);
    printf("Current mode: Machine (priv=3)\n");

    // Enable TraceEncoderController
    write_reg(REG_CONTROL, 0x3);

    // TEST 1: No privilege filtering
    printf("\n--- Test 1: No Filter ---\n");
    write_reg(PULP_REG(0x03), 0x0);  // Disable PRIV filter
    write_reg(PULP_REG(0x1D), 0x1);  // Lossless
    write_reg(PULP_REG(0x1C), 0x1);  // Enable

    volatile int sum1 = 0;
    for (int i = 0; i < 100; i++) {
        sum1 += i;
    }

    write_reg(PULP_REG(0x1C), 0x0);
    printf("All instructions traced\n");

    // TEST 2: Match mode - only trace Machine mode (priv=3)
    printf("\n--- Test 2: Match Machine mode ---\n");

    // PRIV_MATCH = 3 (Machine mode)
    write_reg(PULP_REG(0x15), 0x3);

    // PRIV_ENABLE_MODE = 0x2 (match mode: trace if priv == MATCH)
    write_reg(PULP_REG(0x03), 0x2);

    printf("PRIV_MATCH: 0x%x\n", read_reg(PULP_REG(0x15)));
    printf("PRIV_ENABLE: 0x%x\n", read_reg(PULP_REG(0x03)));

    write_reg(PULP_REG(0x1C), 0x1);

    volatile int sum2 = 0;
    for (int i = 0; i < 100; i++) {
        sum2 += i;
    }

    write_reg(PULP_REG(0x1C), 0x0);
    printf("Machine mode traced (should match Test 1)\n");

    // TEST 3: Range mode - trace User to Supervisor (0-1)
    printf("\n--- Test 3: Range U/S mode ---\n");

    // PRIV_RANGE = 0x1 (User=0, Supervisor=1)
    write_reg(PULP_REG(0x14), 0x1);

    // PRIV_ENABLE_MODE = 0x1 (range mode: trace if priv <= RANGE)
    write_reg(PULP_REG(0x03), 0x1);

    printf("PRIV_RANGE: 0x%x\n", read_reg(PULP_REG(0x14)));

    write_reg(PULP_REG(0x1C), 0x1);

    volatile int sum3 = 0;
    for (int i = 0; i < 100; i++) {
        sum3 += i;
    }

    write_reg(PULP_REG(0x1C), 0x0);
    printf("U/S mode traced (should be 0 packets)\n");
    printf("because we're in M mode\n");

    // Disable filtering
    write_reg(PULP_REG(0x03), 0x0);

    printf("\n=== PRIVILEGE FILTER TEST DONE ===\n");
    printf("Expected packet counts:\n");
    printf("Test 1: ~100+ packets\n");
    printf("Test 2: ~100+ packets (same as Test 1)\n");
    printf("Test 3: 0 packets (filtered out)\n");

    tohost = 1;
    while (1);
    return 0;
}
