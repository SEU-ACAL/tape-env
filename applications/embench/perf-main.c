/* Measure one Embench workload after its cache warmup. */

#include <stdint.h>

#include "support.h"

int main(void)
{
  volatile int result;
  int correct;
  initialise_board();
  initialise_benchmark();
  warm_caches(WARMUP_HEAT);

  __asm__ volatile ("fence" ::: "memory");
  start_trigger();
  result = benchmark();
  stop_trigger();

  correct = verify_benchmark(result);
  return !correct;
}
