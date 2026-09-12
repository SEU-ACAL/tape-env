// Test: Address Range Filtering with explicit backpressure
#include <stdio.h>
#include <stdint.h>

#define TRACE_CTRL_BASE     0x10060000UL
#define PULP_REG_BASE       (TRACE_CTRL_BASE + 0x40)
#define REG_CONTROL         (TRACE_CTRL_BASE + 0x00)
#define PULP_REG(apb)       (PULP_REG_BASE + ((apb) * 4))

#define TRACE_STATUS_REG    0x2c
#define TOSTHOST_SYNC       0x80000000UL
// Verified by the test's objdump: function_b occupies 0x40 bytes.  The
// function is deliberately noinline and this window ends before the next
// symbol, so range mode can cover B even when the linker places main first.
#define FUNCTION_B_WINDOW_BYTES 0x40UL

#ifndef TRACE_DELTA_ADDRESS
#define TRACE_DELTA_ADDRESS 1u
#endif

#ifndef TRACE_FULL_ADDRESS
#define TRACE_FULL_ADDRESS 0u
#endif

static inline void write_reg(uint64_t addr, uint32_t val) {
    *(volatile uint32_t*)addr = val;
}

static inline uint32_t read_reg(uint64_t addr) {
    return *(volatile uint32_t*)addr;
}

extern volatile uint64_t tohost;

// Spin delay to let trace FIFO drain
static void drain_delay(void) {
    // The trace SPI transport runs independently of the core.  This loop is
    // executed only while the address filter matches no instruction, so it
    // provides drain time without adding more trace packets.
    for (volatile int i = 0; i < 2000; i++) {
        asm volatile("nop");
    }
}

static void set_range(uint64_t lower, uint64_t upper) {
    write_reg(PULP_REG(0x18), (uint32_t)lower);
    write_reg(PULP_REG(0x19), (uint32_t)(lower >> 32));
    write_reg(PULP_REG(0x16), (uint32_t)upper);
    write_reg(PULP_REG(0x17), (uint32_t)(upper >> 32));
    write_reg(PULP_REG(0x04), 0x1);
}

// Configure rv_tracer backpressure registers
static void config_backpressure(void) {
    // LOSSLESS_TRACE = 1: stall core when encapsulator buffer is full
    write_reg(PULP_REG(0x1D), 0x1);
    // SHALLOW_TRACE = 1: flush branch map at each packet emitted
    write_reg(PULP_REG(0x1E), 0x1);
    // NO_TIME = 1: disable timestamps (reduce packet size)
    write_reg(PULP_REG(0x1F), 0x1);
    // NO_CONTEXT = 1: disable context info (reduce packet size)
    write_reg(PULP_REG(0x20), 0x1);
    write_reg(PULP_REG(0x21), TRACE_DELTA_ADDRESS);
    write_reg(PULP_REG(0x22), TRACE_FULL_ADDRESS);
}

// Function A - should be traced
__attribute__((noinline))
void function_a(void) {
    volatile int x = 0;
    for (int i = 0; i < 5; i++) {
        x = x + i;
    }
}

// Function B - should NOT be traced (outside range)
__attribute__((noinline))
void function_b(void) {
    volatile int y = 0;
    for (int i = 0; i < 5; i++) {
        y = y + i * 2;
    }
}

int main(void) {
    printf("\n=== ADDRESS FILTER TEST ===\n");

    // Get addresses of functions
    uint64_t addr_a = (uint64_t)function_a;
    uint64_t addr_b = (uint64_t)function_b;

    printf("function_a @ 0x%lx\n", addr_a);
    printf("function_b @ 0x%lx\n", addr_b);

    // Configure backpressure and arm an empty address range before enabling
    // the controller, so setup/printf instructions cannot enter the trace.
    config_backpressure();
    set_range(0, 0);
    // Arm PULP rv_tracer before enabling its controller transport.  The
    // controller's enable alone only opens the SPI path; TRACE_STATE controls
    // architectural trace qualification.
    write_reg(PULP_REG(0x1C), 0x1);

    // Enable TraceEncoderController only after the tracer is configured.
    write_reg(REG_CONTROL, 0x3);
    drain_delay();

    // ======== TEST 1: Trace both functions ========
    printf("\n--- Test 1: Both functions ---\n");
    uint64_t addr_b_end = addr_b + FUNCTION_B_WINDOW_BYTES - 2;
    set_range(addr_a, addr_b_end);

    function_a();
    function_b();
    set_range(0, 0);
    drain_delay();
    printf("Both functions traced\n");

    // TEST 2: Filter to only trace function_a
    printf("\n--- Test 2: Filter function_a only ---\n");

    // Functions are emitted consecutively by this test image.  Use the next
    // function's entry point rather than a compiler-dependent size constant.
    // The upper bound is inclusive and instructions are at least two-byte aligned.
    uint64_t addr_a_end = addr_b - 2;

    printf("Filter range: 0x%lx - 0x%lx\n", addr_a, addr_a_end);

    // Enable range mode (0x1 = trace if LOWER <= PC <= UPPER)
    set_range(addr_a, addr_a_end);

    function_a();  // Should be traced
    function_b();  // Should NOT be traced

    set_range(0, 0);
    drain_delay();
    printf("Only function_a should be traced\n");

    // TEST 3: Range mode for function_b
    // IADDR_ENABLE_MODE bit 1 selects equality mode, not exclusion.  Use the
    // documented range mode to check that the complementary function is selected.
    printf("\n--- Test 3: Filter function_b only ---\n");
    set_range(addr_b, addr_b_end);

    function_a();  // Should NOT be traced
    function_b();  // Should be traced

    set_range(0, 0);
    drain_delay();
    printf("Only function_b should be traced\n");

    printf("\n=== ADDRESS FILTER TEST DONE ===\n");
    printf("Compare packet counts between tests\n");

    drain_delay();
    tohost = 1;
    while (1);
    return 0;
}
