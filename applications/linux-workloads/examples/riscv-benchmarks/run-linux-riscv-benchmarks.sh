#!/bin/sh

set -u

cd "$(dirname "$0")" || exit 1

passed=0
failed=0
skipped=0

run_benchmark() {
  benchmark=$1

  printf 'LINUX_BMARK_BEGIN name=%s\n' "$benchmark"
  "./bin/$benchmark"
  exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    printf 'LINUX_BMARK_RESULT name=%s status=PASS\n' "$benchmark"
    passed=$((passed + 1))
  else
    printf 'LINUX_BMARK_RESULT name=%s status=FAIL exit_code=%s\n' "$benchmark" "$exit_code"
    failed=$((failed + 1))
  fi
}

run_benchmark mm
run_benchmark spmv
run_benchmark mt-vvadd
run_benchmark median
run_benchmark multiply
run_benchmark qsort
run_benchmark rsort
printf 'LINUX_BMARK_RESULT name=pmp status=SKIP reason=requires_machine_mode\n'
skipped=$((skipped + 1))
run_benchmark towers
run_benchmark vvadd
run_benchmark dhrystone
run_benchmark mt-matmul

printf 'LINUX_RISCV_BMARK_SUITE_SUMMARY pass=%s fail=%s skip=%s\n' \
  "$passed" "$failed" "$skipped"

if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
