#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* RISC-V specific definitions */
#define configMTIME_BASE_ADDRESS    0x0200bff8
#define configMTIMECMP_BASE_ADDRESS 0x02004000
#define configMTIME_CLOCK_HZ         5000

/* Scheduler configuration */
#define configUSE_PREEMPTION                    1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configUSE_TICKLESS_IDLE                 0
#define configCPU_CLOCK_HZ                      100000000  // 100MHz for TapeoutConfig
#define configTICK_RATE_HZ                      ((TickType_t)1000)
#define configMAX_PRIORITIES                    5
#define configMINIMAL_STACK_SIZE                ((unsigned short)512)  // Increased for safety
#define configMAX_TASK_NAME_LEN                 16
#define configUSE_16_BIT_TICKS                  0
#define configIDLE_SHOULD_YIELD                 0
#define configUSE_TASK_NOTIFICATIONS            1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES   3
#define configUSE_MUTEXES                       1
#define configUSE_RECURSIVE_MUTEXES             0
#define configUSE_COUNTING_SEMAPHORES           1
#define configQUEUE_REGISTRY_SIZE               10
#define configUSE_QUEUE_SETS                    0
#define configUSE_TIME_SLICING                  0
#define configUSE_NEWLIB_REENTRANT              0
#define configENABLE_BACKWARD_COMPATIBILITY     0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 5

/* Memory allocation related definitions */
#define configSUPPORT_STATIC_ALLOCATION         0
#define configSUPPORT_DYNAMIC_ALLOCATION        1
#define configTOTAL_HEAP_SIZE                   ((size_t)(64 * 1024))  // 64KB heap
#define configAPPLICATION_ALLOCATED_HEAP        0

/* Hook function related definitions */
#define configUSE_IDLE_HOOK                     1  // Enable idle hook for debugging
#define configUSE_TICK_HOOK                     1  // Enable tick hook for debugging
#define configCHECK_FOR_STACK_OVERFLOW          2  // Enable stack overflow checking
#define configUSE_MALLOC_FAILED_HOOK            1  // Enable malloc failed hook
#define configUSE_DAEMON_TASK_STARTUP_HOOK      0

/* Run time and task stats gathering related definitions */
#define configGENERATE_RUN_TIME_STATS           0
#define configUSE_TRACE_FACILITY                0
#define configUSE_STATS_FORMATTING_FUNCTIONS    0

/* Co-routine related definitions */
#define configUSE_CO_ROUTINES                   0
#define configMAX_CO_ROUTINE_PRIORITIES         1

/* Software timer related definitions */
#define configUSE_TIMERS                        1
#define configTIMER_TASK_PRIORITY               (configMAX_PRIORITIES - 1)
#define configTIMER_QUEUE_LENGTH                10
#define configTIMER_TASK_STACK_DEPTH            configMINIMAL_STACK_SIZE

/* Define to trap errors during development */
#define configASSERT(x) if((x) == 0) {taskDISABLE_INTERRUPTS(); for(;;);}

/* Optional functions - most excluded to save code size */
#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet               1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskSuspend                    1
#define INCLUDE_xResumeFromISR                  1
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_xTaskGetSchedulerState          1
#define INCLUDE_xTaskGetCurrentTaskHandle       1
#define INCLUDE_uxTaskGetStackHighWaterMark     0
#define INCLUDE_xTaskGetIdleTaskHandle          0
#define INCLUDE_eTaskGetState                   0
#define INCLUDE_xEventGroupSetBitFromISR        1
#define INCLUDE_xTimerPendFunctionCall          0
#define INCLUDE_xTaskAbortDelay                 0
#define INCLUDE_xTaskGetHandle                  0
#define INCLUDE_xTaskResumeFromISR              1

/* RISC-V definitions */
#define configISR_STACK_SIZE_WORDS              (512)

/* Install the trap handler on scheduler start */
extern void freertos_risc_v_trap_handler( void );
#define configSETUP_MTVEC() \
    do { \
        __asm__ volatile( "csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler) ); \
    } while(0)

/* Use minimal printf */
#define configUSE_MINIMAL_PRINTF                1

#endif /* FREERTOS_CONFIG_H */
