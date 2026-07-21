#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${SYNTHESIS_WORKBENCH:?SYNTHESIS_WORKBENCH must point to Tapeout-Workbench}"
: "${CI_SYNTHESIS_RUN_ROOT:?CI_SYNTHESIS_RUN_ROOT must be set}"

SYNTHESIS_CONFIG="${SYNTHESIS_CONFIG:-TapeoutConfig}"
TOP_MODULE="${TOP_MODULE:-ChipTop}"
DC_CONTAINER="${DC_CONTAINER:-ci_env}"
PT_SHELL_BIN="${PT_SHELL_BIN:-/data0/tools/Synopsys/ptpx/prime/W-2024.09-SP1/bin/pt_shell}"
POWER_WORKLOAD="${POWER_WORKLOAD:-/data2/ci-workloads/hello.riscv}"
POWER_RANDOM_SEED="${POWER_RANDOM_SEED:-1}"
POWER_START_NS="${POWER_START_NS:-1000}"
STD_CELL_MODEL="${STD_CELL_MODEL:-/data2/TSMC28/logic/tcbn28hpcplusbwp7t40p140lvt_180b/AN61001_20180509/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp7t40p140lvt_110a/tcbn28hpcplusbwp7t40p140lvt.v}"
STD_CELL_DB="${STD_CELL_DB:-/data2/TSMC28/logic/tcbn28hpcplusbwp7t40p140lvt_180b/AN61001_20180509/TSMCHOME/digital/Front_End/timing_power_noise/CCS/tcbn28hpcplusbwp7t40p140lvt_180a/tcbn28hpcplusbwp7t40p140lvtssg0p81v125c_ccs.db}"
SRAM_ROOT="${SRAM_ROOT:-/data2/TSMC28/Memory/SRAM}"
SRAM_CORNER="${SRAM_CORNER:-ssg0p81v125c}"
FLOW_DIR="${CI_SYNTHESIS_RUN_ROOT}/dc-flow"
POWER_FLOW_DIR="${CI_SYNTHESIS_RUN_ROOT}/power-flow"
POWER_GLS_DIR="${POWER_FLOW_DIR}/3-Pre_PR_NETSIM"
POWER_PT_DIR="${POWER_FLOW_DIR}/4-Pre_PR_STA_POWER"

run_label="${CI_SYNTHESIS_RUN_LABEL:-}"
if [[ -z "${run_label}" ]]; then
  netlist="$(find "${FLOW_DIR}/outputs" -mindepth 2 -maxdepth 2 -type f -name "${TOP_MODULE}.v" -print 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -z "${netlist}" ]]; then
    echo "No synthesized ${TOP_MODULE} netlist found in ${FLOW_DIR}/outputs" >&2
    exit 1
  fi
  run_label="$(basename "$(dirname "${netlist}")")"
else
  netlist="${FLOW_DIR}/outputs/${run_label}/${TOP_MODULE}.v"
fi
constraint_sdc="${FLOW_DIR}/outputs/${run_label}/${TOP_MODULE}.sdc"
power_report="${POWER_PT_DIR}/outputs/${run_label}/zero-fsdb/power_total.rpt"

write_power_summary() {
  local internal_power switching_power leakage_power total_power

  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return
  fi

  {
    echo "## PrimeTime Power"
    echo
    echo "| Metric | Value |"
    echo "| --- | ---: |"
    echo "| Workload | \`${POWER_WORKLOAD##*/}\` |"
    echo "| Activity source | Zero-delay GLS FSDB after ${POWER_START_NS} ns |"
    if [[ -f "${power_report}" ]]; then
      internal_power="$(awk -F= '/^  Cell Internal Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      switching_power="$(awk -F= '/^  Net Switching Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      leakage_power="$(awk -F= '/^  Cell Leakage Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      total_power="$(awk -F= '/^Total Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      echo "| Internal power | ${internal_power:-unavailable} mW |"
      echo "| Switching power | ${switching_power:-unavailable} mW |"
      echo "| Leakage power | ${leakage_power:-unavailable} mW |"
      echo "| Total power | ${total_power:-unavailable} mW |"
    else
      echo "| Status | No PrimeTime power report was produced |"
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
}

trap write_power_summary EXIT

for required_directory in 3-Pre_PR_NETSIM 4-Pre_PR_STA_POWER; do
  if [[ ! -d "${SYNTHESIS_WORKBENCH}/${required_directory}" ]]; then
    echo "Tapeout-Workbench does not contain ${required_directory}: ${SYNTHESIS_WORKBENCH}" >&2
    exit 1
  fi
done

for required_file in "${netlist}" "${constraint_sdc}" "${POWER_WORKLOAD}" "${STD_CELL_MODEL}" "${STD_CELL_DB}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Missing PrimeTime power input: ${required_file}" >&2
    exit 1
  fi
done

if [[ ! -d "${SRAM_ROOT}" ]]; then
  echo "Missing SRAM library root for PrimeTime power: ${SRAM_ROOT}" >&2
  exit 1
fi

rm -rf "${POWER_FLOW_DIR}"
mkdir -p "${POWER_FLOW_DIR}"
cp -a "${SYNTHESIS_WORKBENCH}/3-Pre_PR_NETSIM" "${POWER_GLS_DIR}"
cp -a "${SYNTHESIS_WORKBENCH}/4-Pre_PR_STA_POWER" "${POWER_PT_DIR}"

power_sim_config="chipyard.harness.TestHarness.${SYNTHESIS_CONFIG}"
power_gls_gen_dir="${POWER_GLS_DIR}/gen/${power_sim_config}/${run_label}"
power_fsdb="${power_gls_gen_dir}/run-zero.fsdb"
power_report_dir="${POWER_PT_DIR}/outputs/${run_label}/zero-fsdb"

if [[ "$(docker inspect --format '{{.State.Running}}' "${DC_CONTAINER}" 2>/dev/null || true)" != "true" ]]; then
  echo "The PrimeTime container is not running: ${DC_CONTAINER}" >&2
  exit 1
fi

export POWER_GLS_DIR POWER_PT_DIR POWER_WORKLOAD POWER_RANDOM_SEED POWER_START_NS
export STD_CELL_MODEL STD_CELL_DB SRAM_ROOT SRAM_CORNER PT_SHELL_BIN
export REPO_ROOT SYNTHESIS_CONFIG power_sim_config netlist constraint_sdc run_label

set +e
run_in_nix '
  dramsim_dir="${REPO_ROOT}/dependencies/tools/DRAMSim2"

  make -C "${dramsim_dir}" libdramsim.a
  test -f "${dramsim_dir}/libdramsim.a"

  make -C "${POWER_GLS_DIR}" \
    TAPE_ENV="${REPO_ROOT}" \
    CONFIG="${power_sim_config}" \
    NETLIST_RUN="${run_label}" \
    NETLIST="${netlist}" \
    STD_CELL_MODEL="${STD_CELL_MODEL}" \
    SRAM_ROOT="${SRAM_ROOT}" \
    SRAM_CORNER="${SRAM_CORNER}" \
    RANDOM_SEED="${POWER_RANDOM_SEED}" \
    WAVEFORM=1 \
    gls_zero

  make -C "${POWER_GLS_DIR}" \
    TAPE_ENV="${REPO_ROOT}" \
    CONFIG="${power_sim_config}" \
    NETLIST_RUN="${run_label}" \
    NETLIST="${netlist}" \
    STD_CELL_MODEL="${STD_CELL_MODEL}" \
    SRAM_ROOT="${SRAM_ROOT}" \
    SRAM_CORNER="${SRAM_CORNER}" \
    RANDOM_SEED="${POWER_RANDOM_SEED}" \
    WAVEFORM=1 \
    BINARY="${POWER_WORKLOAD}" \
    run_zero

' 2>&1 | tee "${POWER_FLOW_DIR}/power.log"
gls_status=${PIPESTATUS[0]}
set -e

if [[ "${gls_status}" -ne 0 ]]; then
  echo "GLS power activity generation failed with exit status ${gls_status}" >&2
  exit "${gls_status}"
fi

set +e
docker exec -i \
  -e POWER_PT_DIR="${POWER_PT_DIR}" \
  -e NETLIST_RUN="${run_label}" \
  -e NETLIST="${netlist}" \
  -e SDC="${constraint_sdc}" \
  -e FSDB="${power_fsdb}" \
  -e POWER_OUT_DIR="${power_report_dir}" \
  -e POWER_START_NS="${POWER_START_NS}" \
  -e STD_CELL_DB="${STD_CELL_DB}" \
  -e SRAM_ROOT="${SRAM_ROOT}" \
  -e SRAM_CORNER="${SRAM_CORNER}" \
  -e PT_SHELL="${PT_SHELL_BIN}" \
  "${DC_CONTAINER}" bash -lc '
    set -euo pipefail
    if [[ -z "${SYNOPSYS_LC_ROOT:-}" && -n "${LC_HOME:-}" ]]; then
      export SYNOPSYS_LC_ROOT="${LC_HOME}"
    fi
    pt_version="$("${PT_SHELL}" -version 2>&1)"
    if [[ "${pt_version}" != *"W-2024."* ]]; then
      echo "PrimeTime W-2024 is required, but PT_SHELL reports:" >&2
      echo "${pt_version}" >&2
      exit 1
    fi
    printf "%s\n" "${pt_version}"
    make -C "${POWER_PT_DIR}" \
      NETLIST_RUN="${NETLIST_RUN}" \
      NETLIST="${NETLIST}" \
      SDC="${SDC}" \
      FSDB="${FSDB}" \
      POWER_OUT_DIR="${POWER_OUT_DIR}" \
      POWER_START_NS="${POWER_START_NS}" \
      STD_CELL_DB="${STD_CELL_DB}" \
      SRAM_ROOT="${SRAM_ROOT}" \
      SRAM_CORNER="${SRAM_CORNER}" \
      PT_SHELL="${PT_SHELL}" \
      power
  ' 2>&1 | tee -a "${POWER_FLOW_DIR}/power.log"
power_status=${PIPESTATUS[0]}
set -e

if [[ "${power_status}" -ne 0 ]]; then
  echo "PrimeTime power analysis failed with exit status ${power_status}" >&2
  exit "${power_status}"
fi
