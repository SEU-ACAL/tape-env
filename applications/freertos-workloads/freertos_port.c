#include "FreeRTOSConfig.h"

#undef configCPU_CLOCK_HZ
#define configCPU_CLOCK_HZ configMTIME_CLOCK_HZ

#include "freertos-kernel/portable/GCC/RISC-V/port.c"
