#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_DIR:?CI_ARTIFACT_DIR must be set}"
: "${CI_CONFIG:?CI_CONFIG must be set}"
: "${CI_RESULT_DIR:?CI_RESULT_DIR must be set}"
: "${CI_TESTCASE:?CI_TESTCASE must be set}"
: "${CI_WORKLOAD_ROOT:?CI_WORKLOAD_ROOT must be set}"

case "${CI_TESTCASE}" in
  rocket-asm|rocket-bmark|rocket-hello-loadmem|rocket-hello|rocket-zephyr-hello|boom-asm|boom-bmark) ;;
  *)
    echo "Unsupported VCS core regression testcase: ${CI_TESTCASE}" >&2
    exit 1
    ;;
esac

mkdir -p "${CI_RESULT_DIR}"
started_at="$(date +%s)"
CI_VCS_SIM_OUTPUT_DIR="${CI_VCS_SIM_OUTPUT_DIR:-${REPO_ROOT}/soc-generator/sims/vcs/output/${CI_TESTCASE}}"
export CI_VCS_SIM_OUTPUT_DIR
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
  if [[ -d "${CI_VCS_SIM_OUTPUT_DIR}" ]]; then
    rm -rf "${CI_RESULT_DIR}/sim-output"
    cp -a "${CI_VCS_SIM_OUTPUT_DIR}" "${CI_RESULT_DIR}/sim-output"
  fi
  printf '{\n  "testcase": "%s",\n  "config": "%s",\n  "status": "%s",\n  "duration_seconds": %s\n}\n' \
    "${CI_TESTCASE}" "${CI_CONFIG}" "${status}" "$((finished_at - started_at))" \
    > "${CI_RESULT_DIR}/result.json"
}

trap 'status=$?; if [[ ${status} -eq 0 ]]; then write_result passed; else write_result failed; fi; exit ${status}' EXIT

rm -rf "${CI_VCS_SIM_OUTPUT_DIR}"
run_in_nix '
  sim_dir="soc-generator/sims/vcs"
  test_rules="${CI_ARTIFACT_DIR}/test-rules.d"
  generated_rules="${sim_dir}/generated-src/chipyard.harness.TestHarness.${CI_CONFIG}/chipyard.harness.TestHarness.${CI_CONFIG}.d"
  simulator="${CI_ARTIFACT_DIR}/simv-chipyard.harness-${CI_CONFIG}"
  runtime_dir="${simulator}.daidir"
  if [[ ! -f "${test_rules}" || ! -f "${generated_rules}" || ! -x "${simulator}" || ! -d "${runtime_dir}" ]]; then
    echo "Prepared VCS regression artifact is incomplete for ${CI_CONFIG}" >&2
    exit 1
  fi

  riscv_tests_root="${CI_WORKLOAD_ROOT}/riscv-tests"
  common_args=(-j1 -C "${sim_dir}" SIM=vcs CONFIG="${CI_CONFIG}" RISCV="${riscv_tests_root}" sim="${simulator}" BREAK_SIM_PREREQ=1 output_dir="${CI_VCS_SIM_OUTPUT_DIR}" TIMEOUT_CYCLES="${timeout_cycles}")

  # Keep Make BINARY.run.fast completion stamps in the testcase result tree.
  # It must stay outside output_dir because common.mk rewrites output_dir children
  # as RISC-V ISA test paths.
  stage_binary() {
    local source="$1"
    local name="$2"
    local staged="${CI_RESULT_DIR}/.ci-inputs/${name}"
    mkdir -p "$(dirname "${staged}")"
    cp -f "${source}" "${staged}"
    chmod a+rx "${staged}"
  }

  case "${CI_TESTCASE}" in
    rocket-asm|boom-asm)
      make -j"${CI_VCS_SIM_TEST_JOBS:-1}" "${common_args[@]:1}" run-asm-tests-fast LOADMEM=1
      ;;
    rocket-bmark|boom-bmark)
      make -j"${CI_VCS_SIM_TEST_JOBS:-1}" "${common_args[@]:1}" run-bmark-tests-fast LOADMEM=1
      ;;
    rocket-hello-loadmem)
      hello_binary="${CI_WORKLOAD_ROOT}/hello.riscv"
      if [[ ! -x "${hello_binary}" ]]; then
        echo "Prebuilt hello test is missing or not executable: ${hello_binary}" >&2
        exit 1
      fi
      stage_binary "${hello_binary}" hello.riscv
      hello_binary="${CI_RESULT_DIR}/.ci-inputs/hello.riscv"
      if [[ ! -f "${hello_binary}" ]]; then
        echo "Staged hello test is missing: ${hello_binary}" >&2
        exit 1
      fi
      make "${common_args[@]}" run-binary-fast BINARY="${hello_binary}" LOADMEM=1
      ;;
    rocket-hello)
      hello_binary="${CI_WORKLOAD_ROOT}/hello.riscv"
      if [[ ! -x "${hello_binary}" ]]; then
        echo "Prebuilt hello test is missing or not executable: ${hello_binary}" >&2
        exit 1
      fi
      stage_binary "${hello_binary}" hello.riscv
      hello_binary="${CI_RESULT_DIR}/.ci-inputs/hello.riscv"
      if [[ ! -f "${hello_binary}" ]]; then
        echo "Staged hello test is missing: ${hello_binary}" >&2
        exit 1
      fi
      make "${common_args[@]}" run-binary-fast BINARY="${hello_binary}" LOADMEM=1
      ;;
    rocket-zephyr-hello)
      zephyr_binary="${CI_WORKLOAD_ROOT}/zephyr/zephyr.elf"
      if [[ ! -x "${zephyr_binary}" ]]; then
        echo "Prebuilt Zephyr hello test is missing or not executable: ${zephyr_binary}" >&2
        exit 1
      fi
      stage_binary "${zephyr_binary}" zephyr.elf
      zephyr_binary="${CI_RESULT_DIR}/.ci-inputs/zephyr.elf"
      if [[ ! -f "${zephyr_binary}" ]]; then
        echo "Staged Zephyr hello test is missing: ${zephyr_binary}" >&2
        exit 1
      fi
      make "${common_args[@]}" run-binary-fast BINARY="${zephyr_binary}" LOADMEM=1
      grep -Fq "Hello World! chipyard_riscv64" "${CI_VCS_SIM_OUTPUT_DIR}/zephyr.log"
      ;;
  esac
'
