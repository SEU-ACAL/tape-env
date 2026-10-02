/*
 * FreeRTOS debug test with detailed printf tracing
 */

#include <stdio.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"

static void prvDebugTask(void *pvParameters)
{
    (void)pvParameters;

    printf("[TASK] Task function started!\n");
    printf("[TASK] pvParameters = %p\n", pvParameters);
    printf("[TASK] Stack pointer = %p\n", (void*)__builtin_frame_address(0));

    for (int i = 0; i < 3; i++)
    {
        printf("[TASK] Loop iteration %d\n", i);

        /* Busy wait */
        for (volatile uint32_t j = 0; j < 500000; j++);
    }

    printf("[TASK] Task exiting\n");
    vTaskDelete(NULL);
}

int main(void)
{
    extern void freertos_risc_v_trap_handler(void);
    extern void xPortStartFirstTask(void);

    printf("=== FreeRTOS Debug Test ===\n");
    printf("[MAIN] Starting FreeRTOS debug test\n");

    /* Set mtvec */
    printf("[MAIN] Setting mtvec to %p\n", (void*)freertos_risc_v_trap_handler);
    __asm__ volatile("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));

    /* Read back mtvec to confirm */
    unsigned long mtvec_val;
    __asm__ volatile("csrr %0, mtvec" : "=r"(mtvec_val));
    printf("[MAIN] mtvec readback = 0x%lx\n", mtvec_val);

    /* Create task */
    printf("[MAIN] Creating task with stack size = %u words\n", configMINIMAL_STACK_SIZE * 2);

    TaskHandle_t xHandle = NULL;
    BaseType_t xReturn = xTaskCreate(
        prvDebugTask,
        "Debug",
        configMINIMAL_STACK_SIZE * 2,
        (void*)0xDEADBEEF,  /* Recognizable parameter */
        tskIDLE_PRIORITY + 1,
        &xHandle
    );

    printf("[MAIN] xTaskCreate returned %d\n", (int)xReturn);
    printf("[MAIN] Task handle = %p\n", (void*)xHandle);

    if (xReturn != pdPASS) {
        printf("[MAIN] ERROR: Failed to create task!\n");
        return 1;
    }

    /* Check scheduler state before starting */
    printf("[MAIN] About to start scheduler\n");
    printf("[MAIN] Heap free bytes = %u\n", (unsigned)xPortGetFreeHeapSize());

    /* Add a hook to trace scheduler start */
    printf("[MAIN] Calling vTaskStartScheduler()...\n");

    vTaskStartScheduler();

    /* Should never reach here */
    printf("[MAIN] ERROR: Scheduler returned!\n");
    return 1;
}

void vApplicationMallocFailedHook(void)
{
    printf("[HOOK] ERROR: Malloc failed!\n");
    taskDISABLE_INTERRUPTS();
    for (;;);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    printf("[HOOK] ERROR: Stack overflow in task: %s\n", pcTaskName);
    taskDISABLE_INTERRUPTS();
    for (;;);
}

void vApplicationIdleHook(void)
{
    static int idle_count = 0;
    if (idle_count++ < 5) {
        printf("[IDLE] Idle task running (count=%d)\n", idle_count);
    }
}

void vApplicationTickHook(void)
{
    /* Tick hook - can be empty */
}
