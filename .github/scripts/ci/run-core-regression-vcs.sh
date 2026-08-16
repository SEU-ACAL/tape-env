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
  common_args=(-j1 -C "${sim_dir}" SIM=vcs CONFIG="${CI_CONFIG}" RISCV="${riscv_tests_root}" sim="${simulator}" BREAK_SIM_PREREQ=1 output_dir="${CI_VCS_SIM_OUTPUT_DIR}")

  case "${CI_TESTCASE}" in
    rocket-asm|boom-asm)
      make -j"${CI_VCS_SIM_TEST_JOBS:-1}" "${common_args[@]:1}" run-asm-tests-fast LOADMEM=1
      ;;
    rocket-bmark|boom-bmark)
      make -j"${CI_VCS_SIM_TEST_JOBS:-1}" "${common_args[@]:1}" run-bmark-tests-fast LOADMEM=1
      ;;
    rocket-hello-loadmem)
      make "${common_args[@]}" run-binary-fast BINARY="${CI_WORKLOAD_ROOT}/hello.riscv" LOADMEM=1
      ;;
    rocket-hello)
      make "${common_args[@]}" run-binary-fast BINARY="${CI_WORKLOAD_ROOT}/hello.riscv"
      ;;
    rocket-zephyr-hello)
      make "${common_args[@]}" run-binary-fast BINARY="${CI_WORKLOAD_ROOT}/zephyr/zephyr.elf" LOADMEM=1
      grep -Fq "Hello World! chipyard_riscv64" "${CI_VCS_SIM_OUTPUT_DIR}/zephyr.log"
      ;;
  esac
'
