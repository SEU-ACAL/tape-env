#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${SYNTHESIS_WORKBENCH:?SYNTHESIS_WORKBENCH must point to Tapeout-Workbench}"
: "${CI_SYNTHESIS_RUN_ROOT:?CI_SYNTHESIS_RUN_ROOT must be set}"

SYNTHESIS_CONFIG="${SYNTHESIS_CONFIG:-TapeoutConfig}"
TOP_MODULE="${TOP_MODULE:-ChipTop}"
DC_CONTAINER="${DC_CONTAINER:-ci_env}"
DC_SHELL_BIN="${DC_SHELL_BIN:-dc_shell}"
CI_RUN_ID="${GITHUB_RUN_ID:-manual-$(date +%Y%m%d%H%M%S)}"
CI_CACHE_KEY="${RUNNER_NAME:-${HOSTNAME:-local}}"
CI_SOURCE_REVISION="${GITHUB_SHA:-$(git -C "${REPO_ROOT}" rev-parse HEAD)}"
CI_CLASSPATH_CACHE="${CI_CACHE_ROOT}/classpath/synthesis/${CI_CACHE_KEY}/${CI_SOURCE_REVISION}"
SBT_CACHE_ROOT="${CI_CACHE_ROOT}/sbt/synthesis/${CI_CACHE_KEY}"
CI_COURSIER_CACHE="${CI_CACHE_ROOT}/coursier/synthesis/${CI_CACHE_KEY}"
CI_SBT_OPTS="-Dsbt.ivy.home=${SBT_CACHE_ROOT}/ivy -Dsbt.global.base=${SBT_CACHE_ROOT}/global -Dsbt.boot.directory=${SBT_CACHE_ROOT}/boot -Dsbt.color=always -Dsbt.supershell=false -Dsbt.server.forcestart=true"
FLOW_DIR="${CI_SYNTHESIS_RUN_ROOT}/dc-flow"

write_qor_summary() {
  local report_dir area_report group_report slack

  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return
  fi

  report_dir="$(find "${FLOW_DIR}/rpt" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)"
  {
    echo "## Weekly synthesis QoR"
    echo
    echo "| Metric | Value |"
    echo "| --- | ---: |"

    if [[ -z "${report_dir}" ]]; then
      echo "| Status | No Design Compiler report was produced |"
      return
    fi

    area_report="${report_dir}/${TOP_MODULE}_mapped_area.rpt"
    if [[ -f "${area_report}" ]]; then
      slack="$(awk '/^Total cell area:/ { print $4; exit }' "${area_report}")"
      echo "| Total cell area | ${slack:-unavailable} |"
    else
      echo "| Total cell area | unavailable |"
    fi

    for group in I2R R2R R2O I2O; do
      group_report="${report_dir}/${TOP_MODULE}_${group}_setup.rpt"
      if [[ -f "${group_report}" ]]; then
        # Each report can contain many paths. The minimum is the group's WNS.
        slack="$(awk '
          /slack \(/ {
            value = $NF
            if (value ~ /^-?[0-9]+(\.[0-9]+)?$/ && (!found || value + 0 < minimum)) {
              minimum = value + 0
              found = 1
            }
          }
          END { if (found) printf "%.4f", minimum }
        ' "${group_report}")"
        echo "| ${group} setup slack | ${slack:-unavailable} |"
      else
        echo "| ${group} setup slack | unavailable |"
      fi
    done

    echo
    echo "Configuration: \`${SYNTHESIS_CONFIG}\`; top module: \`${TOP_MODULE}\`."
  } >> "${GITHUB_STEP_SUMMARY}"
}

trap write_qor_summary EXIT

if [[ ! -d "${SYNTHESIS_WORKBENCH}/2-SYN" ]]; then
  echo "Tapeout-Workbench does not contain 2-SYN: ${SYNTHESIS_WORKBENCH}" >&2
  exit 1
fi

if [[ "$(docker inspect --format '{{.State.Running}}' "${DC_CONTAINER}" 2>/dev/null || true)" != "true" ]]; then
  echo "The Design Compiler container is not running: ${DC_CONTAINER}" >&2
  exit 1
fi

git -C "${REPO_ROOT}" submodule sync --recursive
git -C "${REPO_ROOT}" submodule update --init soc-generator/generator/gemmini

mkdir -p "${CI_CLASSPATH_CACHE}" "${CI_COURSIER_CACHE}" \
  "${SBT_CACHE_ROOT}/ivy" "${SBT_CACHE_ROOT}/global" "${SBT_CACHE_ROOT}/boot"

export CI_CLASSPATH_CACHE CI_COURSIER_CACHE SBT_CACHE_ROOT CI_SBT_OPTS SYNTHESIS_CONFIG
JAVA_TMP_DIR="${CI_SHARED_ROOT}/java/synthesis-${CI_RUN_ID}"
export JAVA_TMP_DIR
mkdir -p "${JAVA_TMP_DIR}"
trap 'write_qor_summary; rm -rf "${JAVA_TMP_DIR}"' EXIT

run_in_nix '
  export COURSIER_CACHE="${CI_COURSIER_CACHE}"
  export CLASSPATH_CACHE="${CI_CLASSPATH_CACHE}"
  export SBT_OPTS="${CI_SBT_OPTS}"
  ./init-submodules.sh
  make -C soc-generator SIM=vcs CONFIG="${SYNTHESIS_CONFIG}" \
    USE_TSMC28_SRAM=1 \
    verilog
'

SOURCE_CODE_HOME="${REPO_ROOT}/soc-generator/sims/vcs/generated-src/chipyard.harness.TestHarness.${SYNTHESIS_CONFIG}"
HDL_FILELIST="${SOURCE_CODE_HOME}/chipyard.harness.TestHarness.${SYNTHESIS_CONFIG}.top.f"
SRAM_WRAPPER_FILE="${SOURCE_CODE_HOME}/gen-collateral/chipyard.harness.TestHarness.${SYNTHESIS_CONFIG}.top.mems.v"

for required_file in "${HDL_FILELIST}" "${SRAM_WRAPPER_FILE}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Missing generated synthesis input: ${required_file}" >&2
    exit 1
  fi
done

# The Workbench DC setup pins the SRAM timing libraries. Fail before synthesis
# if a generated wrapper uses a macro not represented in that pinned library set.
while IFS= read -r macro; do
  if ! grep -Fq "${macro}" "${SYNTHESIS_WORKBENCH}/2-SYN/scripts/dc_setup.tcl"; then
    echo "Missing SRAM timing library in Tapeout-Workbench dc_setup.tcl: ${macro}" >&2
    exit 1
  fi
done < <(sed -nE 's/^[[:space:]]*(chipyard_sram_[[:alnum:]_]+)[[:space:]]+[[:alnum:]_]+[[:space:]]*\(.*/\1/p' "${SRAM_WRAPPER_FILE}" | sort -u)

rm -rf "${FLOW_DIR}"
mkdir -p "${FLOW_DIR}"
cp -a "${SYNTHESIS_WORKBENCH}/2-SYN/." "${FLOW_DIR}/"

tcl_escape() {
  printf '%s' "$1" | sed 's/[\\{}]/\\&/g'
}

run_label="$(date +%m%d)_$(date +%H%M)"
tcl_command="set data {$(tcl_escape "${run_label}")}; set SOURCE_CODE_HOME {$(tcl_escape "${SOURCE_CODE_HOME}")}; set HDL_FILELIST {$(tcl_escape "${HDL_FILELIST}")}; set TOP_MODULE {$(tcl_escape "${TOP_MODULE}")}; set SRAM_WRAPPER_FILE {$(tcl_escape "${SRAM_WRAPPER_FILE}")}"

pushd "${FLOW_DIR}" >/dev/null
mkdir -p alib elab log "outputs/${run_label}" "rpt/${run_label}"
set +e
# GitHub Actions has no TTY, so use -i instead of the interactive equivalent
# `docker exec -it ci_env bash`. The actual Design Compiler process runs here.
docker exec -i \
  -e FLOW_DIR="${FLOW_DIR}" \
  -e DC_SHELL_BIN="${DC_SHELL_BIN}" \
  -e RUN_LABEL="${run_label}" \
  -e TCL_COMMAND="${tcl_command}" \
  "${DC_CONTAINER}" bash -lc '
    set -euo pipefail
    cd "${FLOW_DIR}"
    mkdir -p alib elab log "outputs/${RUN_LABEL}" "rpt/${RUN_LABEL}"
    "${DC_SHELL_BIN}" -f ./scripts/core.tcl -x "${TCL_COMMAND}"
  ' 2>&1 | tee "log/core_${run_label}.log"
dc_status=${PIPESTATUS[0]}
set -e
popd >/dev/null

if [[ "${dc_status}" -ne 0 ]]; then
  echo "Design Compiler failed with exit status ${dc_status}" >&2
  exit "${dc_status}"
fi
