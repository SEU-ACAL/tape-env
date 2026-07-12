#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_RESULT_DIR:?CI_RESULT_DIR must be set}"

mkdir -p "${CI_RESULT_DIR}"
started_at="$(date +%s)"
sim_output="${REPO_ROOT}/soc-generator/sims/verilator/output"

write_result() {
  local status="$1"
  local finished_at
  finished_at="$(date +%s)"
  if [[ -d "${sim_output}" ]]; then
    rm -rf "${CI_RESULT_DIR}/sim-output"
    cp -a "${sim_output}" "${CI_RESULT_DIR}/sim-output"
  fi
  printf '{\n  "testcase": "hello",\n  "status": "%s",\n  "duration_seconds": %s\n}\n' \
    "${status}" "$((finished_at - started_at))" > "${CI_RESULT_DIR}/result.json"
}

trap 'status=$?; if [[ ${status} -eq 0 ]]; then write_result passed; else write_result failed; fi; exit ${status}' EXIT

rm -rf "${sim_output}"
run_in_nix '
  cmake -S applications/tests -B "${CI_RESULT_DIR}/tests-build"
  cmake --build "${CI_RESULT_DIR}/tests-build" --target hello
  make -C soc-generator CONFIG=RocketConfig BREAK_SIM_PREREQ=1 run \
    BINARY="${CI_RESULT_DIR}/tests-build/hello.riscv"
'
