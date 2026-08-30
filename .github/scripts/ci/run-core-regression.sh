#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_DIR:?CI_ARTIFACT_DIR must be set}"
: "${CI_CONFIG:?CI_CONFIG must be set}"
: "${CI_RESULT_DIR:?CI_RESULT_DIR must be set}"
: "${CI_TESTCASE:?CI_TESTCASE must be set}"
: "${CI_WORKLOAD_ROOT:?CI_WORKLOAD_ROOT must be set}"

case "${CI_CONFIG}" in
  [A-Za-z][A-Za-z0-9_]*) ;;
  *)
    echo "Invalid Chipyard configuration name: ${CI_CONFIG}" >&2
    exit 1
    ;;
esac

case "${CI_TESTCASE}" in
  rocket-asm|rocket-bmark|rocket-hello-loadmem|rocket-hello|rocket-zephyr-hello|boom-asm|boom-bmark) ;;
  *)
    echo "Unsupported core regression testcase: ${CI_TESTCASE}" >&2
    exit 1
    ;;
esac

if [[ "${CI_TESTCASE}" == rocket-zephyr-hello && "${CI_CONFIG}" != QuadChannelRocketConfig ]]; then
  echo "rocket-zephyr-hello requires QuadChannelRocketConfig" >&2
  exit 1
fi

mkdir -p "${CI_RESULT_DIR}"
started_at="$(date +%s)"
CI_SIM_OUTPUT_DIR="${CI_SIM_OUTPUT_DIR:-${REPO_ROOT}/soc-generator/sims/verilator/output/${CI_TESTCASE}}"
export CI_SIM_OUTPUT_DIR
sim_output="${CI_SIM_OUTPUT_DIR}"
timeout_cycles="${CI_TIMEOUT_CYCLES:-200000000}"
case "${timeout_cycles}" in
  ''|*[!0-9]*)
    echo "CI_TIMEOUT_CYCLES must be a non-negative integer: ${timeout_cycles}" >&2
    exit 1
    ;;
esac
export timeout_cycles

write_result() {
  local status="$1"
  local finished_at
  finished_at="$(date +%s)"
  if [[ -d "${sim_output}" ]]; then
    rm -rf "${CI_RESULT_DIR}/sim-output"
    cp -a "${sim_output}" "${CI_RESULT_DIR}/sim-output"
  fi
  printf '{\n  "testcase": "%s",\n  "config": "%s",\n  "status": "%s",\n  "duration_seconds": %s\n}\n' \
    "${CI_TESTCASE}" "${CI_CONFIG}" "${status}" "$((finished_at - started_at))" \
    > "${CI_RESULT_DIR}/result.json"
}

trap 'status=$?; if [[ ${status} -eq 0 ]]; then write_result passed; else write_result failed; fi; exit ${status}' EXIT

rm -rf "${sim_output}"
run_in_nix '
  sim_dir="soc-generator/sims/verilator"
  test_rules="${CI_ARTIFACT_DIR}/test-rules.d"
  if [[ ! -f "${test_rules}" ]]; then
    echo "Generated regression rules are missing: ${test_rules}" >&2
    exit 1
  fi
  generated_rules="${sim_dir}/generated-src/chipyard.harness.TestHarness.${CI_CONFIG}/chipyard.harness.TestHarness.${CI_CONFIG}.d"
  if [[ ! -f "${generated_rules}" ]]; then
    echo "Prepared regression rules are missing: ${generated_rules}" >&2
    exit 1
  fi
  simulator="${CI_ARTIFACT_DIR}/simulator-chipyard.harness-${CI_CONFIG}"
  if [[ ! -x "${simulator}" ]]; then
    echo "Built Verilator simulator is missing or not executable: ${simulator}" >&2
    exit 1
  fi
  riscv_tests_root="${CI_WORKLOAD_ROOT}/riscv-tests"
  common_args=(-j1 -C "${sim_dir}" CONFIG="${CI_CONFIG}" RISCV="${riscv_tests_root}" sim="${simulator}" BREAK_SIM_PREREQ=1 output_dir="${CI_SIM_OUTPUT_DIR}" TIMEOUT_CYCLES="${timeout_cycles}")

  case "${CI_TESTCASE}" in
    rocket-asm|boom-asm)
      if [[ ! -d "${riscv_tests_root}/riscv64-unknown-elf/share/riscv-tests" ]]; then
        echo "Prebuilt RISC-V ISA and benchmark tests are missing: ${riscv_tests_root}" >&2
        exit 1
      fi
      make -j"${CI_SIM_TEST_JOBS:-1}" "${common_args[@]:1}" run-asm-tests-fast LOADMEM=1
      ;;
    rocket-bmark|boom-bmark)
      if [[ ! -d "${riscv_tests_root}/riscv64-unknown-elf/share/riscv-tests" ]]; then
        echo "Prebuilt RISC-V ISA and benchmark tests are missing: ${riscv_tests_root}" >&2
        exit 1
      fi
      make -j"${CI_SIM_TEST_JOBS:-1}" "${common_args[@]:1}" run-bmark-tests-fast LOADMEM=1
      ;;
    rocket-hello-loadmem)
      hello_binary="${CI_WORKLOAD_ROOT}/hello.riscv"
      if [[ ! -x "${hello_binary}" ]]; then
        echo "Prebuilt hello test is missing or not executable: ${hello_binary}" >&2
        exit 1
      fi
      make "${common_args[@]}" run-binary-fast \
        BINARY="${hello_binary}" LOADMEM=1
      ;;
    rocket-hello)
      hello_binary="${CI_WORKLOAD_ROOT}/hello.riscv"
      if [[ ! -x "${hello_binary}" ]]; then
        echo "Prebuilt hello test is missing or not executable: ${hello_binary}" >&2
        exit 1
      fi
      make "${common_args[@]}" run-binary-fast \
        BINARY="${hello_binary}" LOADMEM=1
      ;;
    rocket-zephyr-hello)
      zephyr_binary="${CI_WORKLOAD_ROOT}/zephyr/zephyr.elf"
      if [[ ! -x "${zephyr_binary}" ]]; then
        echo "Prebuilt Zephyr hello test is missing or not executable: ${zephyr_binary}" >&2
        exit 1
      fi
      make "${common_args[@]}" run-binary-fast \
        BINARY="${zephyr_binary}" LOADMEM=1
      zephyr_log="${CI_SIM_OUTPUT_DIR}/zephyr.log"
      if ! grep -Fq "Hello World! chipyard_riscv64" "${zephyr_log}"; then
        echo "Zephyr hello output is missing from simulation log: ${zephyr_log}" >&2
        exit 1
      fi
      ;;
  esac
'
