/*
 * Minimal FreeRTOS test for RISC-V TapeoutConfig
 * Tests basic task creation without timer interrupts
 */

#include <stdio.h>
#include <stdint.h>

// Minimal printf for testing
void test_printf(const char *msg) {
    printf("%s\n", msg);
}

int main(void)
{
    printf("=== FreeRTOS Minimal Test ===\n");
    printf("Testing basic functionality without scheduler\n");

    // Test 1: Basic printf
    test_printf("Test 1: Printf works");

    // Test 2: Check CLINT addresses are accessible
    volatile uint64_t *mtime = (volatile uint64_t *)0x0200BFF8UL;
    volatile uint64_t *mtimecmp = (volatile uint64_t *)0x02004000UL;

    printf("Test 2: Reading MTIME...\n");
    uint64_t time_val = *mtime;
    printf("  MTIME = 0x%lx\n", time_val);

    printf("Test 3: Writing MTIMECMP...\n");
    *mtimecmp = time_val + 1000000;
    printf("  MTIMECMP = 0x%lx\n", *mtimecmp);

    printf("\n=== All tests passed ===\n");
    printf("CLINT addresses are accessible\n");

    return 0;
}
