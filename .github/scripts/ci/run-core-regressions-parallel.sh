#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${CI_ARTIFACT_ROOT:?CI_ARTIFACT_ROOT must be set}"
: "${CI_RESULT_ROOT:?CI_RESULT_ROOT must be set}"

CI_TEST_JOBS="${CI_TEST_JOBS:-8}"
case "${CI_TEST_JOBS}" in
  ''|*[!0-9]*|0)
    echo "CI_TEST_JOBS must be a positive integer: ${CI_TEST_JOBS}" >&2
    exit 1
    ;;
esac

testcases=(
  'rocket-asm:QuadChannelRocketConfig'
  'rocket-bmark:QuadChannelRocketConfig'
  'rocket-hello-loadmem:QuadChannelRocketConfig'
  'rocket-hello:QuadChannelRocketConfig'
  'boom-asm-v3:MediumBoomV3CosimConfig'
  'boom-bmark-v3:MediumBoomV3CosimConfig'
  'boom-asm-v4:MediumBoomV4CosimConfig'
  'boom-bmark-v4:MediumBoomV4CosimConfig'
)

run_testcase() {
  local testcase="$1"
  local config="$2"
  local script_testcase

  case "${testcase}" in
    boom-asm-v3|boom-asm-v4) script_testcase=boom-asm ;;
    boom-bmark-v3|boom-bmark-v4) script_testcase=boom-bmark ;;
    *) script_testcase="${testcase}" ;;
  esac

  local result_dir="${CI_RESULT_ROOT}/${testcase}"
  mkdir -p "${result_dir}"
  CI_ARTIFACT_DIR="${CI_ARTIFACT_ROOT}/${config}" \
    CI_CONFIG="${config}" \
    CI_TESTCASE="${script_testcase}" \
    CI_RESULT_DIR="${result_dir}" \
    CI_SIM_OUTPUT_DIR="${REPO_ROOT}/soc-generator/sims/verilator/output/${testcase}" \
    "${SCRIPT_DIR}/run-core-regression.sh" > "${result_dir}/workflow.log" 2>&1
}

pids=()
status=0
for entry in "${testcases[@]}"; do
  testcase="${entry%%:*}"
  config="${entry#*:}"

  while [[ ${#pids[@]} -ge ${CI_TEST_JOBS} ]]; do
    pid="${pids[0]}"
    wait "${pid}" || status=1
    pids=("${pids[@]:1}")
  done

  run_testcase "${testcase}" "${config}" &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "${pid}" || status=1
done

exit "${status}"
