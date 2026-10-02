/*
 * FreeRTOS test with busy-wait instead of vTaskDelay
 * Tests task switching without timer interrupts
 */

#include <stdio.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"

static volatile uint32_t task1_counter = 0;
static volatile uint32_t task2_counter = 0;

static void prvTask1(void *pvParameters)
{
    (void)pvParameters;
    uint32_t local_count = 0;

    for (;;)
    {
        printf("Task 1: counter = %lu (local = %lu)\n",
               (unsigned long)task1_counter, (unsigned long)local_count);

        task1_counter++;
        local_count++;

        /* Busy wait instead of vTaskDelay */
        for (volatile uint32_t i = 0; i < 1000000; i++) {
            __asm__ volatile("nop");
        }

        /* Yield to other task */
        taskYIELD();

        if (local_count >= 5) {
            printf("Task 1: Exiting after 5 iterations\n");
            vTaskDelete(NULL);
        }
    }
}

static void prvTask2(void *pvParameters)
{
    (void)pvParameters;
    uint32_t local_count = 0;

    for (;;)
    {
        printf("Task 2: counter = %lu (local = %lu)\n",
               (unsigned long)task2_counter, (unsigned long)local_count);

        task2_counter++;
        local_count++;

        /* Busy wait instead of vTaskDelay */
        for (volatile uint32_t i = 0; i < 1000000; i++) {
            __asm__ volatile("nop");
        }

        /* Yield to other task */
        taskYIELD();

        if (local_count >= 5) {
            printf("Task 2: Exiting after 5 iterations\n");
            vTaskDelete(NULL);
        }
    }
}

int main(void)
{
    extern void freertos_risc_v_trap_handler(void);

    printf("=== FreeRTOS Busy-Wait Task Switching Test ===\n");
    printf("Testing voluntary task switching without timer interrupts\n\n");

    /* Set mtvec */
    __asm__ volatile("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));

    /* Create two tasks */
    xTaskCreate(prvTask1, "Task1", configMINIMAL_STACK_SIZE * 2, NULL,
                tskIDLE_PRIORITY + 1, NULL);
    xTaskCreate(prvTask2, "Task2", configMINIMAL_STACK_SIZE * 2, NULL,
                tskIDLE_PRIORITY + 1, NULL);

    printf("Tasks created, starting scheduler...\n\n");

    /* Start scheduler */
    vTaskStartScheduler();

    printf("ERROR: Scheduler returned!\n");
    return 1;
}

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
