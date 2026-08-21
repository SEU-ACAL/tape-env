#!/usr/bin/env bash
set -euo pipefail

gdb_bin="${GDB:-riscv64-unknown-elf-gdb}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
results_dir="$(mktemp -d)"
trap 'rm -rf -- "$results_dir"' EXIT

run_pass() {
  local script="$1"
  local marker="$2"
  local log_file="$results_dir/$script.log"

  "$gdb_bin" -batch -x "$script_dir/$script" | tee "$log_file"
  grep -Fqx "$marker" "$log_file"
  printf 'PASS %s\n' "$script"
}

run_xfail() {
  local script="$1"
  local marker="$2"
  local log_file="$results_dir/$script.log"

  if "$gdb_bin" -batch -x "$script_dir/$script" >"$log_file" 2>&1; then
    printf 'XPASS %s\n' "$script" >&2
    cat "$log_file" >&2
    return 1
  fi
  cat "$log_file"
  grep -Fqx "$marker" "$log_file"
  printf 'XFAIL %s\n' "$script"
}

run_pass gdb-reset-halt.gdb RESET_HALT_PASS
run_pass gdb-reset-dcsr-step.gdb DCSR_STEP_PASS
run_pass gdb-reset-rsp-step.gdb RSP_STEP_PASS
run_xfail gdb-reset-stepi.gdb 'RESET_STEPI_FAIL: expected DCSR single-step cause'
