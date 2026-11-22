/*
 * FreeRTOS Blinky Demo for RISC-V TapeoutConfig
 *
 * This demo creates two tasks that toggle between each other,
 * simulating a "blinky LED" pattern via HTIF printf output.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "FreeRTOS.h"
#include "task.h"

/* Task priorities */
#define mainBLINKY_TASK_PRIORITY    (tskIDLE_PRIORITY + 1)
#define mainBLINKY_DELAY_MS         100
#define mainBLINKY_ITERATIONS       10

/* Task handles */
static TaskHandle_t xTask1Handle = NULL;
static TaskHandle_t xTask2Handle = NULL;
static volatile BaseType_t xTask2Finished = pdFALSE;

/*-----------------------------------------------------------*/

static void prvTask1(void *pvParameters)
{
    (void)pvParameters;

    for (uint32_t iteration = 0; iteration < mainBLINKY_ITERATIONS; iteration++)
    {
        printf("Task 1: Running (tick = %lu)\n", (unsigned long)xTaskGetTickCount());
        vTaskDelay(pdMS_TO_TICKS(mainBLINKY_DELAY_MS));
    }

    while (xTask2Finished == pdFALSE)
    {
        vTaskDelay(pdMS_TO_TICKS(mainBLINKY_DELAY_MS));
    }

    printf("FreeRTOS Blinky workload complete\n");
    exit(0);
}

/*-----------------------------------------------------------*/

static void prvTask2(void *pvParameters)
{
    (void)pvParameters;

    for (uint32_t iteration = 0; iteration < mainBLINKY_ITERATIONS; iteration++)
    {
        printf("Task 2: Running (tick = %lu)\n", (unsigned long)xTaskGetTickCount());
        vTaskDelay(pdMS_TO_TICKS(mainBLINKY_DELAY_MS));
    }

    xTask2Finished = pdTRUE;
    vTaskDelete(NULL);
}

/*-----------------------------------------------------------*/

int main(void)
{
    extern void freertos_risc_v_trap_handler(void);

    printf("FreeRTOS Blinky Demo for RISC-V TapeoutConfig\n");
    printf("CPU Frequency: %lu Hz\n", (unsigned long)configCPU_CLOCK_HZ);
    printf("Tick Rate: %lu Hz\n", (unsigned long)configTICK_RATE_HZ);
    printf("\nStarting FreeRTOS scheduler...\n\n");

    /* Create the two tasks */
    xTaskCreate(prvTask1,                   /* Task function */
                "Task1",                    /* Task name */
                configMINIMAL_STACK_SIZE,   /* Stack size */
                NULL,                       /* Parameters */
                mainBLINKY_TASK_PRIORITY,   /* Priority */
                &xTask1Handle);             /* Task handle */

    xTaskCreate(prvTask2,
                "Task2",
                configMINIMAL_STACK_SIZE,
                NULL,
                mainBLINKY_TASK_PRIORITY,
                &xTask2Handle);

    /* Set mtvec to FreeRTOS trap handler before starting scheduler */
    __asm__ volatile("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));

    /* Start the scheduler */
    vTaskStartScheduler();

    /* Should never reach here */
    printf("ERROR: FreeRTOS scheduler failed to start!\n");
    for (;;);

    return 0;
}

/*-----------------------------------------------------------*/

/* FreeRTOS hook functions (if enabled in FreeRTOSConfig.h) */
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
