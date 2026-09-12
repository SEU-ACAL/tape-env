#!/usr/bin/env bash
set -u

cases=(
  test_tval_match test_tval_exclude
  test_tval_range_high_match test_tval_range_high_exclude
  test_cause_equal_exclude test_cause_range_match test_cause_range_exclude
  test_tvec_equal_match test_tvec_equal_exclude
  test_tvec_range_match test_tvec_range_exclude
  test_iaddr_equal_match test_iaddr_equal_exclude
  test_iaddr_range_match test_iaddr_range_exclude
  test_privilege_m_equal_iaddr_match test_privilege_us_range_iaddr_exclude_m
  test_privilege_exception
)

summary=trace_verification/final_tracestatefix_regression_summary.txt
: > "$summary"

for testcase in "${cases[@]}"; do
  result_dir="trace_verification/result/tapeout_${testcase}_final_tracestatefix_20260912"
  elf="applications/tests/build/${testcase}.riscv"
  mkdir -p "$result_dir"

  nix develop .#default --command \
    soc-generator/sims/vcs/simv-chipyard.harness-TapeoutRocketConfig \
    +permissive +notimingcheck +loadmem="$elf" +max-cycles=5000000 \
    +trace_spi_nibbles="$result_dir/trace.nibbles" +permissive-off "$elf" \
    >"$result_dir/sim.log" 2>&1
  sim_rc=$?
  printf '%s\n' "$sim_rc" >"$result_dir/sim.rc"

  python3 applications/tests/trace/deframe_trace_spi.py \
    "$result_dir/trace.nibbles" "$result_dir/trace.bin" \
    >"$result_dir/deframe.log" 2>&1
  deframe_rc=$?
  printf '%s\n' "$deframe_rc" >"$result_dir/deframe.rc"

  nix develop .#default --command bash -lc \
    "cd dependencies/riscv-etrace && target/release/examples/pulp_chipyard \
../../$result_dir/trace.bin ../../$elf" \
    >"$result_dir/decode.log" 2>&1
  decode_rc=$?
  printf '%s\n' "$decode_rc" >"$result_dir/decode.rc"

  printf '%s sim=%s deframe=%s decode=%s\n' \
    "$testcase" "$sim_rc" "$deframe_rc" "$decode_rc" >> "$summary"
done
