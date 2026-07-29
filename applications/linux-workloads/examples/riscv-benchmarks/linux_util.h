#ifndef TAPE_ENV_LINUX_RISCV_BENCHMARK_UTIL_H
#define TAPE_ENV_LINUX_RISCV_BENCHMARK_UTIL_H

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static inline uint64_t linux_benchmark_now_ns(void)
{
  struct timespec now;

  clock_gettime(CLOCK_MONOTONIC, &now);
  return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}

static uint64_t linux_benchmark_stats_start_ns;

static inline void setStats(int enable)
{
  if (enable) {
    linux_benchmark_stats_start_ns = linux_benchmark_now_ns();
    return;
  }

  printf("LINUX_BMARK_TIMING elapsed_ns=%" PRIu64 "\n",
         linux_benchmark_now_ns() - linux_benchmark_stats_start_ns);
}

/* The original sources use these helpers for functional result checking. */
static int verify(int n, const volatile int* test, const int* expected)
{
  int i;

  for (i = 0; i < n / 2 * 2; i += 2) {
    int test0 = test[i];
    int test1 = test[i + 1];
    int expected0 = expected[i];
    int expected1 = expected[i + 1];

    if (test0 != expected0) return i + 1;
    if (test1 != expected1) return i + 2;
  }
  if (n % 2 != 0 && test[n - 1] != expected[n - 1]) return n;
  return 0;
}

static int verifyDouble(int n, const volatile double* test, const double* expected)
{
  int i;

  for (i = 0; i < n / 2 * 2; i += 2) {
    int equal0 = test[i] == expected[i];
    int equal1 = test[i + 1] == expected[i + 1];

    if (!(equal0 & equal1)) return i + 1 + equal0;
  }
  if (n % 2 != 0 && test[n - 1] != expected[n - 1]) return n;
  return 0;
}

static int verifyFloat(int n, const volatile float* test, const float* expected)
{
  int i;

  for (i = 0; i < n / 2 * 2; i += 2) {
    int equal0 = test[i] == expected[i];
    int equal1 = test[i + 1] == expected[i + 1];

    if (!(equal0 & equal1)) return i + 1 + equal0;
  }
  if (n % 2 != 0 && test[n - 1] != expected[n - 1]) return n;
  return 0;
}

static void __attribute__((noinline)) barrier(int ncores)
{
  static volatile int sense;
  static volatile int count;
  static __thread int thread_sense;

  __sync_synchronize();
  thread_sense = !thread_sense;
  if (__sync_fetch_and_add(&count, 1) == ncores - 1) {
    count = 0;
    sense = thread_sense;
  } else {
    while (sense != thread_sense) {
    }
  }
  __sync_synchronize();
}

static uint64_t lfsr(uint64_t value)
{
  uint64_t bit = (value ^ (value >> 1)) & 1;

  return (value >> 1) | (bit << 62);
}

#define static_assert(condition) switch (0) { case 0: case !!(long)(condition): ; }

/* Linux does not expose a stable architectural cycle counter to every task. */
#define read_csr(counter) linux_benchmark_now_ns()

#define stringify_1(value) #value
#define stringify(value) stringify_1(value)
#define stats(code, iterations) do { \
    uint64_t start_ns = linux_benchmark_now_ns(); \
    code; \
    uint64_t elapsed_ns = linux_benchmark_now_ns() - start_ns; \
    printf("LINUX_BMARK_TIMING operation=%s elapsed_ns=%" PRIu64 " iterations=%zu\n", \
           stringify(code), elapsed_ns, (size_t)(iterations)); \
  } while (0)

#endif
