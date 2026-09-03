#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_ROOT:?CI_ARTIFACT_ROOT must be set}"
: "${CI_RESULT_ROOT:?CI_RESULT_ROOT must be set}"
: "${CI_CONFIG:=TapeoutConfig}"

case "${CI_CONFIG}" in
  [A-Za-z][A-Za-z0-9_]*) ;;
  *) echo "Invalid Chipyard configuration name: ${CI_CONFIG}" >&2; exit 1 ;;
esac

run_test() {
  local testcase="$1"
  local config="$2"
  shift 2
  local artifact_dir="${CI_ARTIFACT_ROOT}/${config}"
  local simulator="simv-chipyard.harness-${config}"
  local source_simulator="${artifact_dir}/${simulator}"
  local source_runtime="${source_simulator}.daidir"
  local result_dir="${CI_RESULT_ROOT}/${testcase}"
  local runtime_dir="${result_dir}/runtime"
  local started_at status finished_at

  for path in "$source_simulator" "$source_runtime"; do
    if [[ ! -e "$path" ]]; then
      printf 'Peripheral VCS artifact is missing: %s\n' "$path" >&2
      exit 1
    fi
  done

  mkdir -p "$result_dir"
  rm -rf "$runtime_dir"
  mkdir -p "$runtime_dir"
  cp -a "$source_simulator" "$source_runtime" "$runtime_dir/"

  started_at="$(date +%s)"
  if "$@" "${runtime_dir}/${simulator}" >"${result_dir}/workflow.log" 2>&1; then
    status=passed
    rm -rf "$runtime_dir"
  else
    status=failed
  fi
  finished_at="$(date +%s)"

  printf '{\n  "testcase": "%s",\n  "config": "%s",\n  "status": "%s",\n  "duration_seconds": %s\n}\n' \
    "$testcase" "$config" "$status" "$((finished_at - started_at))" >"${result_dir}/result.json"

  [[ "$status" == passed ]]
}

run_i2c() {
  SIMV="$1" \
    I2C_STRESS_ROUNDS="${I2C_STRESS_ROUNDS:-4}" \
    I2C_STRESS_PAGE_BYTES="${I2C_STRESS_PAGE_BYTES:-16}" \
    I2C_TIMEOUT_POLLS="${I2C_TIMEOUT_POLLS:-1000000}" \
    I2C_CI_TIMEOUT="${I2C_CI_TIMEOUT:-2000}" \
    run_in_nix './applications/tests/ci-i2c-test.sh'
}

run_spi() {
  SIMV="$1" \
    SPI_FLASH_STRESS_ROUNDS="${SPI_FLASH_STRESS_ROUNDS:-16}" \
    SPI_FLASH_STRESS_TRANSFER_BYTES="${SPI_FLASH_STRESS_TRANSFER_BYTES:-64}" \
    SPI_FLASH_TIMEOUT_POLLS="${SPI_FLASH_TIMEOUT_POLLS:-1000000}" \
    SPI_FLASH_CI_TIMEOUT="${SPI_FLASH_CI_TIMEOUT:-3000}" \
    run_in_nix './applications/tests/ci-spi-flash-test.sh'
}

run_jtag() {
  local simv="$1"
  run_in_nix 'make -C applications/tests/jtag all' || return
  (
    cd "$REPO_ROOT"
    SIMV="$simv" \
      BUILD_ELF=0 \
      STRESS_STEPS="${JTAG_STRESS_STEPS:-4}" \
      STRESS_MEMORY="${JTAG_STRESS_MEMORY:-8}" \
      JTAG_FULL_STRESS="${JTAG_FULL_STRESS:-0}" \
      STRESS_TIMEOUT="${JTAG_STRESS_TIMEOUT:-1000}" \
      CI_TIMEOUT="${JTAG_CI_TIMEOUT:-1000}" \
      "$NIX_BIN" develop .#jtag-debug --command \
      "${REPO_ROOT}/applications/tests/jtag/ci-jtag-test.sh"
  )
}

status=0
test_pids=()

# Each test gets its own copied VCS runtime directory in run_test, and the
# I2C/SPI drivers build into per-test temporary directories.  They can therefore
# run concurrently while still producing independent result.json files.
run_test spi "${CI_CONFIG}" run_spi &
test_pids+=("$!")
run_test i2c "${CI_CONFIG}" run_i2c &
test_pids+=("$!")
run_test jtag "${CI_CONFIG}" run_jtag &
test_pids+=("$!")

for pid in "${test_pids[@]}"; do
  if ! wait "$pid"; then
    status=1
  fi
done
exit "$status"
