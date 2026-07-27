#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${SYNTHESIS_WORKBENCH:?SYNTHESIS_WORKBENCH must point to Tapeout-Workbench}"
: "${CI_SYNTHESIS_RUN_ROOT:?CI_SYNTHESIS_RUN_ROOT must be set}"

SYNTHESIS_CONFIG="${SYNTHESIS_CONFIG:-TapeoutConfig}"
SYNTHESIS_TECH="${SYNTHESIS_TECH:-smic180}"
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
CI_SUMMARY_FILE="${CI_SYNTHESIS_RUN_ROOT}/synthesis-summary.md"

case "${SYNTHESIS_TECH}" in
  smic180)
    CLOCK_PERIOD="${CLOCK_PERIOD:-2.0}"
    ;;
  tsmc28)
    CLOCK_PERIOD="${CLOCK_PERIOD:-1.0}"
    ;;
  *)
    echo "Unsupported SYNTHESIS_TECH: ${SYNTHESIS_TECH}" >&2
    exit 1
    ;;
esac

if ! awk -v period="${CLOCK_PERIOD}" '
  BEGIN {
    valid = "^[0-9]+([.][0-9]+)?$"
    exit !(period ~ valid && period + 0 > 0)
  }
'; then
  echo "CLOCK_PERIOD must be a positive number of nanoseconds: ${CLOCK_PERIOD}" >&2
  exit 1
fi

extract_sdc_values() {
  local command="$1" sdc_file="$2"

  awk -v command="${command}" '
    $1 == command {
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) {
          print $i
          break
        }
      }
    }
  ' "${sdc_file}" | sort -nu | paste -sd ', ' -
}

clock_frequency_mhz() {
  local period="$1" time_unit="$2"

  case "${time_unit}" in
    fs) awk -v period="${period}" 'BEGIN { printf "%.3f MHz", 1000000000 / period }' ;;
    ps) awk -v period="${period}" 'BEGIN { printf "%.3f MHz", 1000000 / period }' ;;
    ns) awk -v period="${period}" 'BEGIN { printf "%.3f MHz", 1000 / period }' ;;
    us) awk -v period="${period}" 'BEGIN { printf "%.3f MHz", 1 / period }' ;;
    ms) awk -v period="${period}" 'BEGIN { printf "%.6f MHz", 0.001 / period }' ;;
    s) awk -v period="${period}" 'BEGIN { printf "%.9f MHz", 0.000001 / period }' ;;
    *) printf 'unavailable' ;;
  esac
}

write_qor_summary() {
  local report_dir area_report group_report slack constraint_sdc time_unit workbench_revision summary_file
  local clock_period clock_frequency input_delay output_delay clock_uncertainty

  summary_file="${CI_SUMMARY_FILE:-}"
  if [[ -z "${summary_file}" ]]; then
    return
  fi

  report_dir="$(find "${FLOW_DIR}/rpt" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)"
  {
    echo "## Weekly synthesis QoR"
    echo
    echo "| Metric | Value |"
    echo "| --- | ---: |"

    workbench_revision="$(git -C "${SYNTHESIS_WORKBENCH}" rev-parse --short HEAD 2>/dev/null || true)"
    echo "| Tapeout-Workbench revision | ${workbench_revision:-unavailable} |"

    constraint_sdc="$(find "${FLOW_DIR}/outputs" -type f -name "${TOP_MODULE}.sdc" -print 2>/dev/null | sort | tail -n 1 || true)"
    if [[ -n "${constraint_sdc}" ]]; then
      time_unit="$(awk '
        $1 == "set_units" {
          for (i = 2; i < NF; i++) {
            if ($i == "-time") {
              print $(i + 1)
              exit
            }
          }
        }
      ' "${constraint_sdc}")"
      clock_period="$(awk '
        $1 == "create_clock" {
          for (i = 2; i < NF; i++) {
            if ($i == "-period") {
              print $(i + 1)
              exit
            }
          }
        }
      ' "${constraint_sdc}")"
      input_delay="$(extract_sdc_values set_input_delay "${constraint_sdc}")"
      output_delay="$(extract_sdc_values set_output_delay "${constraint_sdc}")"
      clock_uncertainty="$(extract_sdc_values set_clock_uncertainty "${constraint_sdc}")"
      if [[ -n "${clock_period}" && -n "${time_unit}" ]]; then
        clock_frequency="$(clock_frequency_mhz "${clock_period}" "${time_unit}")"
      else
        clock_frequency="unavailable"
      fi

      echo "| Clock period | ${clock_period:-unavailable} ${time_unit:-} |"
      echo "| Clock frequency | ${clock_frequency} |"
      echo "| Clock uncertainty | ${clock_uncertainty:-unavailable} ${time_unit:-} |"
      echo "| Input delay | ${input_delay:-unavailable} ${time_unit:-} |"
      echo "| Output delay | ${output_delay:-unavailable} ${time_unit:-} |"
    else
      echo "| Clock period | unavailable |"
      echo "| Clock frequency | unavailable |"
      echo "| Clock uncertainty | unavailable |"
      echo "| Input delay | unavailable |"
      echo "| Output delay | unavailable |"
    fi

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
  } >> "${summary_file}"
}

write_sram_summary() {
  local netlist macro_counts macro_name macro_count macro_family sram_mdf total_instances summary_file

  summary_file="${CI_SUMMARY_FILE:-}"
  if [[ -z "${summary_file}" ]]; then
    return
  fi

  netlist="$(find "${FLOW_DIR}/outputs" -type f -name "${TOP_MODULE}.v" -print 2>/dev/null | sort | tail -n 1 || true)"
  {
    echo
    echo "## SRAM Macro Usage"
    echo
    if [[ -z "${netlist}" ]]; then
      echo "| Status | Value |"
      echo "| --- | ---: |"
      echo "| Result | No synthesized ${TOP_MODULE} netlist was produced |"
      return
    fi

    # Count instantiations, rather than declarations, in the final DC netlist.
    macro_counts="$(rg -o -P '^\s*\Kchipyard_sram_\d+x\d+(?=\s+[A-Za-z_]\w*\s*\()' "${netlist}" | sort | uniq -c || true)"
    if [[ -z "${macro_counts}" ]]; then
      echo "| Status | Value |"
      echo "| --- | ---: |"
      echo "| Result | No chipyard SRAM instances found |"
      return
    fi

    case "${SYNTHESIS_TECH}" in
      smic180)
        sram_mdf="${SMIC180_SRAM_MDF:-${REPO_ROOT}/soc-generator/generator/chipyard/vlsi/smic180_sram_library.mdf.json}"
        ;;
      tsmc28)
        sram_mdf="${TSMC28_SRAM_MDF:-${REPO_ROOT}/soc-generator/generator/chipyard/vlsi/tsmc28_sram_library.mdf.json}"
        ;;
    esac

    echo "| Macro | Port family | Instances |"
    echo "| --- | --- | ---: |"
    total_instances=0
    while read -r macro_count macro_name; do
      [[ -n "${macro_name:-}" ]] || continue
      macro_family=""
      if [[ -f "${sram_mdf}" ]] && command -v jq >/dev/null 2>&1; then
        macro_family="$(jq -r --arg name "${macro_name}" '.[] | select(.name == $name) | .family' "${sram_mdf}" | head -n 1)"
      fi
      echo "| \`${macro_name}\` | \`${macro_family:-unavailable}\` | ${macro_count} |"
      total_instances=$((total_instances + macro_count))
    done <<< "${macro_counts}"
    echo "| Total | ${total_instances} |"
  } >> "${summary_file}"
}

write_ci_summary() {
  mkdir -p "$(dirname "${CI_SUMMARY_FILE}")"
  : > "${CI_SUMMARY_FILE}"
  write_qor_summary
  write_sram_summary
}

trap write_ci_summary EXIT

if [[ ! -d "${SYNTHESIS_WORKBENCH}/2-SYN" ]]; then
  echo "Tapeout-Workbench does not contain 2-SYN: ${SYNTHESIS_WORKBENCH}" >&2
  exit 1
fi
if [[ ! -f "${SYNTHESIS_WORKBENCH}/2-SYN/scripts/tech/${SYNTHESIS_TECH}.tcl" ]]; then
  echo "Tapeout-Workbench does not provide the ${SYNTHESIS_TECH} technology setup" >&2
  exit 1
fi

git -C "${REPO_ROOT}" submodule sync --recursive
git -C "${REPO_ROOT}" submodule update --init soc-generator/generator/gemmini

mkdir -p "${CI_CLASSPATH_CACHE}" "${CI_COURSIER_CACHE}" \
  "${SBT_CACHE_ROOT}/ivy" "${SBT_CACHE_ROOT}/global" "${SBT_CACHE_ROOT}/boot"

export CI_CLASSPATH_CACHE CI_COURSIER_CACHE SBT_CACHE_ROOT CI_SBT_OPTS SYNTHESIS_CONFIG SYNTHESIS_TECH
JAVA_TMP_DIR="${CI_SHARED_ROOT}/java/synthesis-${CI_RUN_ID}"
export JAVA_TMP_DIR
mkdir -p "${JAVA_TMP_DIR}"
trap 'write_ci_summary; rm -rf "${JAVA_TMP_DIR}"' EXIT

run_in_nix '
  export COURSIER_CACHE="${CI_COURSIER_CACHE}"
  export CLASSPATH_CACHE="${CI_CLASSPATH_CACHE}"
  export SBT_OPTS="${CI_SBT_OPTS}"
  ./init-submodules.sh
  case "${SYNTHESIS_TECH}" in
    smic180)
      make -C soc-generator SIM=vcs CONFIG="${SYNTHESIS_CONFIG}" \
        USE_SMIC180_SRAM=1 \
        SMIC180_SRAM_ROOT="${SMIC180_SRAM_ROOT:-/data2/smic180/SRAM/S018SP_v0p1pc_CDK/SMIC180_S018SP_v0p1c_20260722}" \
        verilog
      ;;
    tsmc28)
      make -C soc-generator SIM=vcs CONFIG="${SYNTHESIS_CONFIG}" \
        USE_TSMC28_SRAM=1 \
        TSMC28_SRAM_ROOT="${TSMC28_SRAM_ROOT:-/data2/TSMC28/Memory/SRAM}" \
        verilog
      ;;
  esac
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

rm -rf "${FLOW_DIR}"
mkdir -p "${FLOW_DIR}"
cp -a "${SYNTHESIS_WORKBENCH}/2-SYN/." "${FLOW_DIR}/"

tcl_escape() {
  printf '%s' "$1" | sed 's/[\\{}]/\\&/g'
}

run_label="$(date +%m%d)_$(date +%H%M)"
tcl_command="set data {$(tcl_escape "${run_label}")}; set SOURCE_CODE_HOME {$(tcl_escape "${SOURCE_CODE_HOME}")}; set HDL_FILELIST {$(tcl_escape "${HDL_FILELIST}")}; set TOP_MODULE {$(tcl_escape "${TOP_MODULE}")}; set SRAM_WRAPPER_FILE {$(tcl_escape "${SRAM_WRAPPER_FILE}")}; set TECH_CONFIG {$(tcl_escape "${SYNTHESIS_TECH}")}; set CLOCK_PERIOD {$(tcl_escape "${CLOCK_PERIOD}")}"

pushd "${FLOW_DIR}" >/dev/null
mkdir -p alib elab log "outputs/${run_label}" "rpt/${run_label}"
if [[ "$(docker inspect --format '{{.State.Running}}' "${DC_CONTAINER}" 2>/dev/null || true)" != "true" ]]; then
  echo "The Design Compiler container is not running: ${DC_CONTAINER}" >&2
  exit 1
fi
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

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "CI_SYNTHESIS_RUN_LABEL=${run_label}" >> "${GITHUB_ENV}"
fi
