// Simple test program for trace verification
// Tests sequential execution, branches, and jumps

#include <stdio.h>
#include "mmio.h"

#define GPIO_BASE 0x10010000
#define TRACE_CTRL_BASE 0x10060000
#define PULP_REG_BASE   (TRACE_CTRL_BASE + 0x40)
#define PULP_REG(apb)   (PULP_REG_BASE + ((apb) * 4))

// GPIO registers
#define GPIO_OUTPUT_VAL   (GPIO_BASE + 0x0C)
#define GPIO_OUTPUT_EN    (GPIO_BASE + 0x08)

// Trace control registers (PULP rv_tracer via APB)
#define TRACE_STATE       PULP_REG(0x1C)
#define LOSSLESS_TRACE    PULP_REG(0x1D)
#define SHALLOW_TRACE     PULP_REG(0x1E)
#define NO_TIME           PULP_REG(0x1F)

#ifndef TRACE_LOSSLESS
#define TRACE_LOSSLESS 0
#endif

#ifndef TRACE_SHALLOW
#define TRACE_SHALLOW 0
#endif

#ifndef TRACE_NO_TIME
#define TRACE_NO_TIME 1
#endif

#ifndef TRACE_DENSE_ITERATIONS
#define TRACE_DENSE_ITERATIONS 50
#endif

volatile uint32_t global_counter = 0;

// Function with branches
int test_branches(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        if (i % 2 == 0) {
            sum += i;  // Branch taken
        } else {
            sum -= i;  // Branch not taken
        }
    }
    return sum;
}

// Function with jumps
void test_jumps(void) {
    global_counter++;
    if (global_counter > 5) {
        return;  // Early return
    }
    test_jumps();  // Recursive call
}

// Sequential instructions
int sequential_test(void) {
    int a = 10;
    int b = 20;
    int c = a + b;
    int d = c * 2;
    int e = d - a;
    return e;
}

void gpio_write(uint32_t val) {
    reg_write32(GPIO_OUTPUT_VAL, val);
}

void trace_configure(int lossless) {
    // Configure trace mode
    reg_write32(LOSSLESS_TRACE, lossless ? 1 : 0);
    reg_write32(SHALLOW_TRACE, TRACE_SHALLOW);
    reg_write32(NO_TIME, TRACE_NO_TIME);
    // Enable trace
    reg_write32(TRACE_STATE, 1);
    reg_write32(TRACE_CTRL_BASE, 3);
}

int main(void) {
    // Enable GPIO outputs
    reg_write32(GPIO_OUTPUT_EN, 0xFF);

    printf("Trace Test Starting...\n");

    trace_configure(TRACE_LOSSLESS);

    // Signal test start
    gpio_write(0x01);

    // Test 1: Sequential execution
    printf("Test 1: Sequential execution\n");
    int result1 = sequential_test();
    printf("Result: %d\n", result1);
    gpio_write(0x02);

    // Test 2: Branches
    printf("Test 2: Branch instructions\n");
    int result2 = test_branches(10);
    printf("Result: %d\n", result2);
    gpio_write(0x03);

    // Test 3: Jumps and calls
    printf("Test 3: Jump instructions\n");
    global_counter = 0;
    test_jumps();
    printf("Counter: %d\n", global_counter);
    gpio_write(0x04);

    // Test 4: Dense branches (stress test)
    printf("Test 4: Dense branches\n");
    int result4 = test_branches(TRACE_DENSE_ITERATIONS);
    printf("Result: %d\n", result4);
    gpio_write(0x05);

    printf("Trace Test Complete!\n");
    gpio_write(0xFF);

    return 0;
}
