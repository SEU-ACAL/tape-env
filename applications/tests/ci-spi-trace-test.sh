#!/usr/bin/env bash
set -euo pipefail

# Run inside the default Nix shell, using the selected CI simulator artifact.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
simv="${SIMV:-$repo_root/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig}"
sim_timeout="${SPI_TRACE_CI_TIMEOUT:-1000}"

for required in cmake cargo python3 timeout riscv64-unknown-elf-nm riscv64-unknown-elf-objdump; do
  if ! command -v "$required" >/dev/null 2>&1; then
    printf 'CI SPI trace error: required command not found: %s\n' "$required" >&2
    exit 2
  fi
done
if [[ ! -x "$simv" ]]; then
  printf 'CI SPI trace error: simulator not found: %s\n' "$simv" >&2
  exit 2
fi

if [[ -n "${SPI_TRACE_RESULT_DIR:-}" ]]; then
  work_dir="$SPI_TRACE_RESULT_DIR"
  mkdir -p "$work_dir"
else
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/chipyard-spi-trace-ci.XXXXXX")"
fi
work_dir="$(cd -- "$work_dir" && pwd)"
build_dir="$work_dir/build"
decoder_target="$work_dir/decoder-target"

cleanup() {
  local exit_code=$?
  trap - EXIT
  if [[ "$exit_code" -ne 0 ]]; then
    printf 'CI SPI trace diagnostics: %s\n' "$work_dir" >&2
    tail -80 "$work_dir"/*.log 2>/dev/null || true
  elif [[ -z "${SPI_TRACE_RESULT_DIR:-}" ]]; then
    rm -rf "$work_dir"
  else
    rm -rf "$build_dir" "$decoder_target"
  fi
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cases=(
  test_iaddr_equal_match test_iaddr_equal_exclude
  test_iaddr_range_match test_iaddr_range_exclude
  test_privilege_m_equal_iaddr_match test_privilege_us_range_iaddr_exclude_m
  test_privilege_exception_trace
)

cmake -S "$script_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release \
  >"$work_dir/build.log" 2>&1
cmake --build "$build_dir" --target "${cases[@]}" -j2 \
  >>"$work_dir/build.log" 2>&1
cargo build --manifest-path "$repo_root/dependencies/riscv-etrace/Cargo.toml" \
  --target-dir "$decoder_target" --release --example pulp_chipyard --features elf,alloc \
  >"$work_dir/decoder-build.log" 2>&1
decoder="$decoder_target/release/examples/pulp_chipyard"

status=0
for testcase in "${cases[@]}"; do
  result_dir="$work_dir/$testcase"
  elf="$build_dir/$testcase.riscv"
  mkdir -p "$result_dir"
  printf 'CI SPI trace: %s\n' "$testcase"

  if timeout "$sim_timeout" "$simv" \
    +permissive +notimingcheck +loadmem="$elf" +max-cycles=5000000 \
    +trace_spi_nibbles="$result_dir/trace.nibbles" +permissive-off "$elf" \
    >"$result_dir/sim.log" 2>&1; then
    sim_rc=0
  else
    sim_rc=$?
  fi
  printf '%s\n' "$sim_rc" >"$result_dir/sim.rc"
  if [[ "$sim_rc" -ne 0 ]]; then
    tail -40 "$result_dir/sim.log" >&2
    status=1
    continue
  fi

  if ! python3 "$script_dir/trace/deframe_trace_spi.py" \
    "$result_dir/trace.nibbles" "$result_dir/trace.bin" \
    >"$result_dir/deframe.log" 2>&1; then
    cat "$result_dir/deframe.log" >&2
    status=1
    continue
  fi
  if "$decoder" "$result_dir/trace.bin" "$elf" >"$result_dir/decode.log" 2>&1; then
    decode_rc=0
  else
    decode_rc=$?
  fi
  printf '%s\n' "$decode_rc" >"$result_dir/decode.rc"

  if python3 "$script_dir/trace/check_spi_trace.py" "$testcase" "$elf" "$result_dir" \
    >"$result_dir/check.log" 2>&1; then
    cat "$result_dir/check.log"
  else
    cat "$result_dir/check.log" >&2
    tail -40 "$result_dir/decode.log" >&2
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi
printf 'CI SPI trace PASS: workloads=%s\n' "${#cases[@]}"
