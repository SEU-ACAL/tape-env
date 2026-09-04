#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_ROOT:?CI_ARTIFACT_ROOT must be set}"
: "${CI_RESULT_ROOT:?CI_RESULT_ROOT must be set}"

CI_CONFIG="${CI_CONFIG:-TapeoutConfig}"
case "${CI_CONFIG}" in
  [A-Za-z][A-Za-z0-9_]*) ;;
  *) echo "Invalid Chipyard configuration name: ${CI_CONFIG}" >&2; exit 1 ;;
esac

CI_VCS_TEST_JOBS="${CI_VCS_TEST_JOBS:-8}"
case "${CI_VCS_TEST_JOBS}" in
  ''|*[!0-9]*|0)
    echo "CI_VCS_TEST_JOBS must be a positive integer: ${CI_VCS_TEST_JOBS}" >&2
    exit 1
    ;;
esac

testcases=()
if [[ "${CI_CONFIG}" == *Boom* ]]; then
  testcases+=("boom-asm-v3:${CI_CONFIG}" "boom-bmark-v3:${CI_CONFIG}")
else
  testcases+=("rocket-asm:${CI_CONFIG}" "rocket-bmark:${CI_CONFIG}" \
    "rocket-hello-loadmem:${CI_CONFIG}" "rocket-hello:${CI_CONFIG}" \
  )
  if [[ "${CI_CONFIG}" == QuadChannelRocketConfig ]]; then
    testcases+=("rocket-zephyr-hello:${CI_CONFIG}")
  fi
fi

rules="${CI_ARTIFACT_ROOT}/${CI_CONFIG}/test-rules.d"
generated="${REPO_ROOT}/soc-generator/sims/vcs/generated-src/chipyard.harness.TestHarness.${CI_CONFIG}/chipyard.harness.TestHarness.${CI_CONFIG}.d"
mkdir -p "$(dirname "${generated}")"
cp -f "${rules}" "${generated}"

run_testcase() {
  local testcase="$1"
  local config="$2"
  local script_testcase="${testcase}"
  case "${testcase}" in
    boom-asm-v3|boom-asm-v4) script_testcase=boom-asm ;;
    boom-bmark-v3|boom-bmark-v4) script_testcase=boom-bmark ;;
  esac

  local result_dir="${CI_RESULT_ROOT}/${testcase}"
  mkdir -p "${result_dir}"
  CI_ARTIFACT_DIR="${CI_ARTIFACT_ROOT}/${config}" \
    CI_CONFIG="${config}" \
    CI_TESTCASE="${script_testcase}" \
    CI_RESULT_DIR="${result_dir}" \
    CI_VCS_SIM_OUTPUT_DIR="${REPO_ROOT}/soc-generator/sims/vcs/output/${testcase}" \
    "${SCRIPT_DIR}/run-core-regression-vcs.sh" > "${result_dir}/workflow.log" 2>&1
}

pids=()
status=0
for entry in "${testcases[@]}"; do
  testcase="${entry%%:*}"
  config="${entry#*:}"
  while [[ ${#pids[@]} -ge ${CI_VCS_TEST_JOBS} ]]; do
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
