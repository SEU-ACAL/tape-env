#include "common.h"
#include "util.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
  const int repeats = 8;
  const int m = CBM;
  const int n = CBN;
  const int p = CBK;
  uint64_t seed = UINT64_C(0xdeadbeef);
  t a[m * p];
  t b[p * n];
  t c[m * n];
  uint64_t start_ns;
  uint64_t elapsed_ns;

  for (size_t i = 0; i < (size_t)m; i++)
    for (size_t j = 0; j < (size_t)p; j++)
      a[i * p + j] = (t)(seed = lfsr(seed));
  for (size_t i = 0; i < (size_t)p; i++)
    for (size_t j = 0; j < (size_t)n; j++)
      b[i * n + j] = (t)(seed = lfsr(seed));
  memset(c, 0, sizeof(c));

  start_ns = linux_benchmark_now_ns();
  for (int repeat = 0; repeat < repeats; repeat++)
    mm(m, n, p, a, p, b, n, c, n);
  elapsed_ns = linux_benchmark_now_ns() - start_ns;

  printf("LINUX_BMARK_TIMING operation=mm elapsed_ns=%" PRIu64 " repeats=%d\n",
         elapsed_ns, repeats);

  for (size_t i = 0; i < (size_t)m; i++) {
    for (size_t j = 0; j < (size_t)n; j++) {
      t expected = 0;

      for (size_t k = 0; k < (size_t)p; k++)
        expected += a[i * p + k] * b[k * n + j];
      expected *= repeats;
      if (fabs(c[i * n + j] - expected) > fabs(1e-6 * expected)) {
        fprintf(stderr, "mm verification failed at [%zu][%zu]\n", i, j);
        return 1;
      }
    }
  }

  return 0;
}
