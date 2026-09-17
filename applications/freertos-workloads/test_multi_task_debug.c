/*
 * Multi-task debug test with interrupt status checking
 */

#include <stdio.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"

/* Counters to verify tasks are actually running */
static volatile uint32_t task1_count = 0;
static volatile uint32_t task2_count = 0;

/* Check and print interrupt status */
static void print_interrupt_status(const char *label)
{
    unsigned long mstatus, mie, mip;

    __asm__ volatile("csrr %0, mstatus" : "=r"(mstatus));
    __asm__ volatile("csrr %0, mie" : "=r"(mie));
    __asm__ volatile("csrr %0, mip" : "=r"(mip));

    printf("[%s] mstatus=0x%lx (MIE=%lu) mie=0x%lx mip=0x%lx\n",
           label, mstatus, (mstatus >> 3) & 1, mie, mip);
}

static void prvTask1(void *pvParameters)
{
    (void)pvParameters;

    printf("[Task1] Started\n");
    print_interrupt_status("Task1-start");

    for (int i = 0; i < 5; i++)
    {
        task1_count++;
        printf("[Task1] Running iteration %d (count=%lu, tick=%lu)\n",
               i, task1_count, (unsigned long)xTaskGetTickCount());

        /* Use vTaskDelay to test timer interrupt */
        vTaskDelay(pdMS_TO_TICKS(500));
    }

    printf("[Task1] Exiting\n");
    vTaskDelete(NULL);
}

static void prvTask2(void *pvParameters)
{
    (void)pvParameters;

    printf("[Task2] Started\n");
    print_interrupt_status("Task2-start");

    for (int i = 0; i < 5; i++)
    {
        task2_count++;
        printf("[Task2] Running iteration %d (count=%lu, tick=%lu)\n",
               i, task2_count, (unsigned long)xTaskGetTickCount());

        vTaskDelay(pdMS_TO_TICKS(500));
    }

    printf("[Task2] Exiting\n");
    vTaskDelete(NULL);
}

int main(void)
{
    extern void freertos_risc_v_trap_handler(void);

    printf("=== FreeRTOS Multi-Task Debug Test ===\n");
    printf("CPU Frequency: %lu Hz\n", (unsigned long)configCPU_CLOCK_HZ);
    printf("Tick Rate: %lu Hz\n", (unsigned long)configTICK_RATE_HZ);

    /* Check CLINT addresses */
    volatile uint64_t *mtime = (volatile uint64_t *)configMTIME_BASE_ADDRESS;
    volatile uint64_t *mtimecmp = (volatile uint64_t *)configMTIMECMP_BASE_ADDRESS;

    printf("\nCLINT Configuration:\n");
    printf("  MTIME addr: 0x%lx, value: 0x%llx\n",
           (unsigned long)configMTIME_BASE_ADDRESS, (unsigned long long)*mtime);
    printf("  MTIMECMP addr: 0x%lx\n", (unsigned long)configMTIMECMP_BASE_ADDRESS);

    /* Check interrupt status before starting */
    print_interrupt_status("Before-mtvec");

    /* Set mtvec */
    __asm__ volatile("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));

    unsigned long mtvec_val;
    __asm__ volatile("csrr %0, mtvec" : "=r"(mtvec_val));
    printf("mtvec set to: 0x%lx\n", mtvec_val);

    print_interrupt_status("After-mtvec");

    /* Create two tasks */
    printf("\nCreating tasks...\n");

    BaseType_t ret1 = xTaskCreate(prvTask1,
                                   "Task1",
                                   configMINIMAL_STACK_SIZE * 2,
                                   NULL,
                                   tskIDLE_PRIORITY + 1,
                                   NULL);

    BaseType_t ret2 = xTaskCreate(prvTask2,
                                   "Task2",
                                   configMINIMAL_STACK_SIZE * 2,
                                   NULL,
                                   tskIDLE_PRIORITY + 1,
                                   NULL);

    printf("Task1 creation: %s\n", ret1 == pdPASS ? "SUCCESS" : "FAILED");
    printf("Task2 creation: %s\n", ret2 == pdPASS ? "SUCCESS" : "FAILED");

    if (ret1 != pdPASS || ret2 != pdPASS) {
        printf("ERROR: Failed to create tasks!\n");
        return 1;
    }

    printf("Free heap: %u bytes\n", (unsigned)xPortGetFreeHeapSize());
    printf("\nStarting scheduler...\n");

    print_interrupt_status("Before-scheduler");

    /* Start the scheduler */
    vTaskStartScheduler();

    /* Should never reach here */
    printf("ERROR: Scheduler returned!\n");
    return 1;
}

/* FreeRTOS hook functions */
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
    if (idle_count++ < 10) {
        printf("[IDLE] Idle hook called (count=%d, tick=%lu)\n",
               idle_count, (unsigned long)xTaskGetTickCount());
    }
}

void vApplicationTickHook(void)
{
    static int tick_count = 0;
    if (tick_count++ < 10) {
        printf("[TICK] Tick hook called (tick=%d)\n", tick_count);
    }
}
