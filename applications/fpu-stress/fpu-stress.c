// Sustained scalar FP64 FMA workload for power characterization.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Eight independent dependency chains keep a pipelined scalar FPU busy.
// This executes 8000 FP64 FMAs for a compact FPU-sensitive smoke workload.
#define FPU_STRESS_ITERATIONS 1000ULL

static volatile double fpu_stress_checksum;

int main(void)
{
  double a0 = 0.1000000, a1 = 0.2000000;
  double a2 = 0.3000000, a3 = 0.4000000;
  double a4 = 0.5000000, a5 = 0.6000000;
  double a6 = 0.7000000, a7 = 0.8000000;

  for (uint64_t i = 0; i < FPU_STRESS_ITERATIONS; ++i) {
    a0 = __builtin_fma(a0, 0.9999990, 0.0000001);
    a1 = __builtin_fma(a1, 0.9999991, 0.0000002);
    a2 = __builtin_fma(a2, 0.9999992, 0.0000003);
    a3 = __builtin_fma(a3, 0.9999993, 0.0000004);
    a4 = __builtin_fma(a4, 0.9999994, 0.0000005);
    a5 = __builtin_fma(a5, 0.9999995, 0.0000006);
    a6 = __builtin_fma(a6, 0.9999996, 0.0000007);
    a7 = __builtin_fma(a7, 0.9999997, 0.0000008);
  }

  // The volatile store makes every FMA result observable after the loop.
  fpu_stress_checksum = (((a0 + a1) + (a2 + a3)) + ((a4 + a5) + (a6 + a7)));
  printf("fpu-stress checksum: %d\\n", (int)(fpu_stress_checksum * 1000000.0));
  exit(0);
}
