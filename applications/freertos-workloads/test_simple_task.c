/*
 * Minimal FreeRTOS test - single task, no delay
 */

#include <stdio.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"

static void prvSimpleTask(void *pvParameters)
{
    (void)pvParameters;

    printf("Task is running!\n");
    printf("Task tick count: %lu\n", (unsigned long)xTaskGetTickCount());

    /* Exit cleanly */
    vTaskDelete(NULL);
}

int main(void)
{
    extern void freertos_risc_v_trap_handler(void);

    printf("=== FreeRTOS Minimal Single Task Test ===\n");

    /* Set mtvec before creating tasks */
    __asm__ volatile("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));

    /* Create one simple task */
    xTaskCreate(prvSimpleTask,
                "Simple",
                configMINIMAL_STACK_SIZE * 2,  /* Double stack size */
                NULL,
                tskIDLE_PRIORITY + 1,
                NULL);

    printf("Task created, starting scheduler...\n");

    /* Start the scheduler */
    vTaskStartScheduler();

    /* Should never reach here */
    printf("ERROR: Scheduler returned!\n");
    return 1;
}

/* FreeRTOS hook functions */
void vApplicationMallocFailedHook(void)
{
    printf("ERROR: Malloc failed!\n");
    taskDISABLE_INTERRUPTS();
    for (;;);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    printf("ERROR: Stack overflow in task: %s\n", pcTaskName);
    taskDISABLE_INTERRUPTS();
    for (;;);
}

void vApplicationIdleHook(void)
{
    /* Idle hook - can be empty */
}

void vApplicationTickHook(void)
{
    /* Tick hook - can be empty */
}
