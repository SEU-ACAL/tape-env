#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${SYNTHESIS_WORKBENCH:?SYNTHESIS_WORKBENCH must point to Tapeout-Workbench}"
: "${CI_SYNTHESIS_RUN_ROOT:?CI_SYNTHESIS_RUN_ROOT must be set}"

SYNTHESIS_CONFIG="${SYNTHESIS_CONFIG:-TapeoutConfig}"
SYNTHESIS_TECH="${SYNTHESIS_TECH:-smic180}"
SYNTHESIS_CORNER="${SYNTHESIS_CORNER:-ss}"
TOP_MODULE="${TOP_MODULE:-ChipTop}"
DC_CONTAINER="${DC_CONTAINER:-ci_env}"
PT_SHELL_BIN="${PT_SHELL_BIN:-/data0/tools/Synopsys/ptpx/prime/W-2024.09-SP1/bin/pt_shell}"
POWER_BENCHMARK="${POWER_BENCHMARK:-dhrystone}"
POWER_WORKLOAD_ROOT="${POWER_WORKLOAD_ROOT:-/data2/ci-workloads/riscv-tests/riscv64-unknown-elf/share/riscv-tests/benchmarks}"
POWER_WORKLOAD="${POWER_WORKLOAD:-}"
POWER_RANDOM_SEED="${POWER_RANDOM_SEED:-1}"
POWER_USE_SDF="${POWER_USE_SDF:-1}"
FLOW_DIR="${CI_SYNTHESIS_RUN_ROOT}/dc-flow"
POWER_FLOW_DIR="${CI_SYNTHESIS_RUN_ROOT}/power-flow"
POWER_GLS_DIR="${POWER_FLOW_DIR}/3-Pre_PR_NETSIM"
POWER_PT_DIR="${POWER_FLOW_DIR}/4-Pre_PR_STA_POWER"

case "${SYNTHESIS_CONFIG}" in
  [A-Za-z][A-Za-z0-9_]*) ;;
  *) echo "Invalid Chipyard configuration name: ${SYNTHESIS_CONFIG}" >&2; exit 1 ;;
esac

case "${SYNTHESIS_TECH}" in
  smic180)
    CLOCK_PERIOD="${CLOCK_PERIOD:-10.0}"
    ;;
  tsmc28)
    CLOCK_PERIOD="${CLOCK_PERIOD:-1.0}"
    ;;
  *)
    echo "Unsupported SYNTHESIS_TECH: ${SYNTHESIS_TECH}" >&2
    exit 1
    ;;
esac

case "${SYNTHESIS_CORNER}" in
  ss|tt|ff) ;;
  *)
    echo "Unsupported SYNTHESIS_CORNER: ${SYNTHESIS_CORNER}. Supported values: ss, tt, ff" >&2
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

case "${POWER_USE_SDF}" in
  0|1) ;;
  *)
    echo "POWER_USE_SDF must be 0 (zero-delay GLS) or 1 (SDF GLS): ${POWER_USE_SDF}" >&2
    exit 2
    ;;
esac

case "${POWER_BENCHMARK}" in
  dhrystone)
    default_power_workload="${POWER_WORKLOAD_ROOT}/dhrystone.riscv"
    default_power_start_ns=673046
    default_power_end_ns=4470574
    ;;
  fpu-stress)
    default_power_workload="${POWER_WORKLOAD_ROOT}/fpu-stress.riscv"
    # Use the common post-boot measurement interval for benchmark selection.
    default_power_start_ns=673046
    default_power_end_ns=4470574
    ;;
  *)
    echo "Unsupported POWER_BENCHMARK: ${POWER_BENCHMARK}. Supported values: dhrystone, fpu-stress" >&2
    exit 2
    ;;
esac

POWER_WORKLOAD="${POWER_WORKLOAD:-${default_power_workload}}"
POWER_START_NS="${POWER_START_NS:-${default_power_start_ns}}"
POWER_END_NS="${POWER_END_NS:-${default_power_end_ns}}"

if ! awk -v start="${POWER_START_NS}" -v end="${POWER_END_NS}" '
  BEGIN {
    valid = "^[0-9]+([.][0-9]+)?$"
    exit !(start ~ valid && end ~ valid && start + 0 < end + 0)
  }
'; then
  echo "POWER_START_NS and POWER_END_NS must be non-negative numbers with POWER_START_NS < POWER_END_NS" >&2
  exit 1
fi

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
sdf="${FLOW_DIR}/outputs/${run_label}/${TOP_MODULE}.sdf"
power_sim_config="chipyard.harness.TestHarness.${SYNTHESIS_CONFIG}"
power_gls_gen_dir="${POWER_GLS_DIR}/gen/${power_sim_config}/${run_label}"
if [[ "${POWER_USE_SDF}" == "1" ]]; then
  power_mode="SDF-annotated GLS"
  power_activity_source="SDF GLS FSDB"
  power_fsdb="${power_gls_gen_dir}/run-sdf.fsdb"
  power_report_dir="${POWER_PT_DIR}/outputs/${run_label}/sdf-fsdb"
else
  power_mode="Zero-delay GLS"
  power_activity_source="Zero-delay GLS FSDB"
  power_fsdb="${power_gls_gen_dir}/run-zero.fsdb"
  power_report_dir="${POWER_PT_DIR}/outputs/${run_label}/zero-fsdb"
fi
power_report="${power_report_dir}/power_total.rpt"

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
    echo "| Benchmark | \`${POWER_BENCHMARK}\` |"
    echo "| PVT corner | ${SYNTHESIS_CORNER} |"
    echo "| Workload | \`${POWER_WORKLOAD##*/}\` |"
    echo "| Timing mode | ${power_mode} |"
    echo "| Activity source | ${power_activity_source} from ${POWER_START_NS} ns to ${POWER_END_NS} ns |"
    if [[ "${POWER_USE_SDF}" == "1" ]]; then
      echo "| SDF | \`${sdf}\` |"
    fi
    if [[ -f "${power_report}" ]]; then
      internal_power="$(awk -F= '/^  Cell Internal Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      switching_power="$(awk -F= '/^  Net Switching Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      leakage_power="$(awk -F= '/^  Cell Leakage Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      total_power="$(awk -F= '/^Total Power/ { sub(/^[[:space:]]+/, "", $2); split($2, value, /[[:space:]]+/); print value[1]; exit }' "${power_report}")"
      echo "| Internal power | ${internal_power:-unavailable} W |"
      echo "| Switching power | ${switching_power:-unavailable} W |"
      echo "| Leakage power | ${leakage_power:-unavailable} W |"
      echo "| Total power | ${total_power:-unavailable} W |"
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

required_files=("${netlist}" "${constraint_sdc}" "${POWER_WORKLOAD}")
if [[ "${POWER_USE_SDF}" == "1" ]]; then
  required_files+=("${sdf}")
fi
for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Missing PrimeTime power input: ${required_file}" >&2
    exit 1
  fi
done

configure_power_window() {
  local power_makefile="${POWER_PT_DIR}/Makefile"
  local power_tcl="${POWER_PT_DIR}/scripts/pt_chiptop_power.tcl"
  local temp_file

  if rg -q '\bPOWER_END_NS\b' "${power_makefile}" && rg -q '\bPOWER_END_NS\b' "${power_tcl}"; then
    return
  fi
  if rg -q '\bPOWER_END_NS\b' "${power_makefile}" || rg -q '\bPOWER_END_NS\b' "${power_tcl}"; then
    echo "Tapeout-Workbench power flow has incomplete POWER_END_NS support" >&2
    exit 1
  fi

  # Apply this only to the isolated flow copy until the upstream flow supports
  # a bounded FSDB window natively.
  temp_file="$(mktemp "${POWER_PT_DIR}/Makefile.XXXXXX")"
  awk '
    /^POWER_START_NS \?=/ {
      print
      print "POWER_END_NS ?= -1"
      next
    }
    /POWER_START_NS=/ {
      print
      line = $0
      gsub("POWER_START_NS", "POWER_END_NS", line)
      print line
      next
    }
    { print }
  ' "${power_makefile}" > "${temp_file}"
  mv "${temp_file}" "${power_makefile}"

  temp_file="$(mktemp "${POWER_PT_DIR}/scripts/pt_chiptop_power.tcl.XXXXXX")"
  awk '
    /^set power_start_ns \[require_env POWER_START_NS\]$/ {
      print
      print "set power_end_ns [require_env POWER_END_NS]"
      next
    }
    {
      sub(/\$power_start_ns -1/, "$power_start_ns $power_end_ns")
      print
    }
  ' "${power_tcl}" > "${temp_file}"
  mv "${temp_file}" "${power_tcl}"

  if ! rg -q '\bPOWER_END_NS\b' "${power_makefile}" ||
    ! rg -q '\bPOWER_END_NS\b' "${power_tcl}" ||
    ! rg -Fq -- '-time [list $power_start_ns $power_end_ns]' "${power_tcl}"; then
    echo "Unable to add bounded FSDB window support to Tapeout-Workbench" >&2
    exit 1
  fi
}

rm -rf "${POWER_FLOW_DIR}"
mkdir -p "${POWER_FLOW_DIR}"
cp -a "${SYNTHESIS_WORKBENCH}/3-Pre_PR_NETSIM" "${POWER_GLS_DIR}"
cp -a "${SYNTHESIS_WORKBENCH}/4-Pre_PR_STA_POWER" "${POWER_PT_DIR}"
configure_power_window

if [[ "$(docker inspect --format '{{.State.Running}}' "${DC_CONTAINER}" 2>/dev/null || true)" != "true" ]]; then
  echo "The PrimeTime container is not running: ${DC_CONTAINER}" >&2
  exit 1
fi

export POWER_GLS_DIR POWER_PT_DIR POWER_WORKLOAD POWER_RANDOM_SEED POWER_START_NS POWER_END_NS POWER_USE_SDF
export POWER_SDF="${sdf}"
export PT_SHELL_BIN
export REPO_ROOT SYNTHESIS_CONFIG SYNTHESIS_TECH SYNTHESIS_CORNER power_sim_config netlist constraint_sdc run_label

set +e
run_in_nix '
  dramsim_dir="${REPO_ROOT}/dependencies/tools/DRAMSim2"

  make -C "${dramsim_dir}" libdramsim.a
  test -f "${dramsim_dir}/libdramsim.a"

  if [[ "${POWER_USE_SDF}" == "1" ]]; then
    make -C "${POWER_GLS_DIR}" \
      TAPE_ENV="${REPO_ROOT}" \
      CONFIG="${power_sim_config}" \
      TECH="${SYNTHESIS_TECH}" \
      CORNER="${SYNTHESIS_CORNER}" \
      CLOCK_PERIOD="${CLOCK_PERIOD}" \
      NETLIST_RUN="${run_label}" \
      NETLIST="${netlist}" \
      SDF="${POWER_SDF}" \
      RANDOM_SEED="${POWER_RANDOM_SEED}" \
      WAVEFORM=1 \
      gls_sdf

    make -C "${POWER_GLS_DIR}" \
      TAPE_ENV="${REPO_ROOT}" \
      CONFIG="${power_sim_config}" \
      TECH="${SYNTHESIS_TECH}" \
      CORNER="${SYNTHESIS_CORNER}" \
      CLOCK_PERIOD="${CLOCK_PERIOD}" \
      NETLIST_RUN="${run_label}" \
      NETLIST="${netlist}" \
      SDF="${POWER_SDF}" \
      RANDOM_SEED="${POWER_RANDOM_SEED}" \
      WAVEFORM=1 \
      BINARY="${POWER_WORKLOAD}" \
      run_sdf
  else
    make -C "${POWER_GLS_DIR}" \
      TAPE_ENV="${REPO_ROOT}" \
      CONFIG="${power_sim_config}" \
      TECH="${SYNTHESIS_TECH}" \
      CORNER="${SYNTHESIS_CORNER}" \
      CLOCK_PERIOD="${CLOCK_PERIOD}" \
      NETLIST_RUN="${run_label}" \
      NETLIST="${netlist}" \
      RANDOM_SEED="${POWER_RANDOM_SEED}" \
      WAVEFORM=1 \
      gls_zero

    make -C "${POWER_GLS_DIR}" \
      TAPE_ENV="${REPO_ROOT}" \
      CONFIG="${power_sim_config}" \
      TECH="${SYNTHESIS_TECH}" \
      CORNER="${SYNTHESIS_CORNER}" \
      CLOCK_PERIOD="${CLOCK_PERIOD}" \
      NETLIST_RUN="${run_label}" \
      NETLIST="${netlist}" \
      RANDOM_SEED="${POWER_RANDOM_SEED}" \
      WAVEFORM=1 \
      BINARY="${POWER_WORKLOAD}" \
      run_zero
  fi

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
  -e SYNTHESIS_TECH="${SYNTHESIS_TECH}" \
  -e SYNTHESIS_CORNER="${SYNTHESIS_CORNER}" \
  -e NETLIST_RUN="${run_label}" \
  -e NETLIST="${netlist}" \
  -e SDC="${constraint_sdc}" \
  -e FSDB="${power_fsdb}" \
  -e POWER_OUT_DIR="${power_report_dir}" \
  -e POWER_START_NS="${POWER_START_NS}" \
  -e POWER_END_NS="${POWER_END_NS}" \
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
      TECH="${SYNTHESIS_TECH}" \
      CORNER="${SYNTHESIS_CORNER}" \
      NETLIST_RUN="${NETLIST_RUN}" \
      NETLIST="${NETLIST}" \
      SDC="${SDC}" \
      FSDB="${FSDB}" \
      POWER_OUT_DIR="${POWER_OUT_DIR}" \
      POWER_START_NS="${POWER_START_NS}" \
      POWER_END_NS="${POWER_END_NS}" \
      PT_SHELL="${PT_SHELL}" \
      power
  ' 2>&1 | tee -a "${POWER_FLOW_DIR}/power.log"
power_status=${PIPESTATUS[0]}
set -e

if [[ "${power_status}" -ne 0 ]]; then
  echo "PrimeTime power analysis failed with exit status ${power_status}" >&2
  exit "${power_status}"
fi
