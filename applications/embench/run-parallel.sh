#!/usr/bin/env bash

# Run Embench binaries on FDIP-with-cosim and baseline BOOMv3 Verilator
# simulators, collecting the XSPerf dump from each run.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
sim_dir="${repo_root}/soc-generator/sims/verilator"
binary_dir="${script_dir}/build/bin"
benchmark_list="${script_dir}/build/BENCHMARKS"
jobs="${EMBENCH_JOBS:-2}"
results_root="${EMBENCH_RESULTS:-${script_dir}/results}"
max_cycles="${EMBENCH_MAX_CYCLES:-10000000}"
skip_build=0
benchmark_filter=""

usage() {
  cat <<'EOF'
Usage: applications/embench/run-parallel.sh [options]

Run every built Embench binary on both Mega BOOMv3 performance configurations.
Each run gets a private directory, so simulator logs and XSPerf data can be
collected in parallel.

Options:
  --jobs N             Maximum concurrent simulations (default: 2)
  --results DIRECTORY Results directory (default: applications/embench/results)
  --max-cycles N       Simulator timeout in RTL cycles (default: 10000000)
  --benchmark NAME     Run only one benchmark from BENCHMARKS
  --skip-build         Do not build missing Verilator simulators
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs)
      [[ $# -ge 2 ]] || { echo "--jobs requires a value" >&2; exit 2; }
      jobs="$2"
      shift 2
      ;;
    --results)
      [[ $# -ge 2 ]] || { echo "--results requires a directory" >&2; exit 2; }
      results_root="$2"
      shift 2
      ;;
    --max-cycles)
      [[ $# -ge 2 ]] || { echo "--max-cycles requires a value" >&2; exit 2; }
      max_cycles="$2"
      shift 2
      ;;
    --benchmark)
      [[ $# -ge 2 ]] || { echo "--benchmark requires a value" >&2; exit 2; }
      benchmark_filter="$2"
      shift 2
      ;;
    --skip-build)
      skip_build=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${IN_NIX_SHELL:-}" ]]; then
  echo "Run this script from the Chipyard Nix development shell:" >&2
  echo "  nix develop --command applications/embench/run-parallel.sh" >&2
  exit 1
fi

[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "--jobs must be a positive integer" >&2; exit 2; }
[[ "$max_cycles" =~ ^[1-9][0-9]*$ ]] || { echo "--max-cycles must be a positive integer" >&2; exit 2; }

if [[ "${results_root}" != /* ]]; then
  results_root="${repo_root}/${results_root}"
fi

if [[ ! -r "${benchmark_list}" ]]; then
  echo "Missing ${benchmark_list}; build Embench first." >&2
  exit 1
fi

configs=(FDIPMegaBoomV3CosimPerfConfig MegaBoomV3PerfConfig)
perf_names=(
  cycles commit_instr branch_resolved branch_mispredict
  control_flow_target_mispredict flush icache_demand_miss dcache_miss
  dtlb_miss l2tlb_miss icache_prefetch ftq_full
  ftq_metadata_conflict ftq_redirect_conflict
)
declare -A simulators
for config in "${configs[@]}"; do
  simulator="${sim_dir}/simulator-chipyard.harness-${config}"
  if [[ ! -x "${simulator}" ]]; then
    if ((skip_build)); then
      echo "Missing simulator: ${simulator}" >&2
      exit 1
    fi
    echo "Building ${config}..."
    if ! make -C "${sim_dir}" CONFIG="${config}" NUMACTL=0; then
      echo "Failed to build ${config}" >&2
      exit 1
    fi
  fi
  simulators["${config}"]="${simulator}"
done

timestamp="$(date +%Y%m%d-%H%M%S)"
run_root="${results_root}/${timestamp}"
mkdir -p "${run_root}"

mapfile -t benchmarks < <(sed '/^[[:space:]]*$/d' "${benchmark_list}")
if [[ -n "${benchmark_filter}" ]]; then
  filtered_benchmarks=()
  for benchmark in "${benchmarks[@]}"; do
    [[ "${benchmark}" == "${benchmark_filter}" ]] && filtered_benchmarks+=("${benchmark}")
  done
  if ((${#filtered_benchmarks[@]} != 1)); then
    echo "Benchmark not found in ${benchmark_list}: ${benchmark_filter}" >&2
    exit 1
  fi
  benchmarks=("${filtered_benchmarks[0]}")
fi
total_runs=$((${#benchmarks[@]} * ${#configs[@]}))
echo "[runner] ${#benchmarks[@]} benchmarks x ${#configs[@]} configs = ${total_runs} runs"
echo "[runner] parallel jobs: ${jobs}; max RTL cycles: ${max_cycles}"
echo "[runner] results: ${run_root}"

run_one() {
  local config="$1"
  local benchmark="$2"
  local run_dir="${run_root}/${config}/${benchmark}"
  local binary="${binary_dir}/${benchmark}"
  local log="${run_dir}/sim.log"
  local perf_file="${run_dir}/xsperf.tsv"
  local status_file="${run_dir}/status"
  local rc cycles status perf_count perf_complete expected_names actual_names

  mkdir -p "${run_dir}"
  printf '[start] %-28s %-32s log=%s\n' "${config}" "${benchmark}" "${log}"
  if [[ ! -x "${binary}" ]]; then
    printf 'status=missing-binary\ncycles=\nexit=127\nxsperf_count=0\n' > "${status_file}"
    printf '[done ] %-28s %-32s status=missing-binary\n' "${config}" "${benchmark}"
    return 0
  fi

  simulator_args=(+cycle-count "+max-cycles=${max_cycles}" "${binary}" +xsperf)
  if [[ "${config}" == FDIPMegaBoomV3CosimPerfConfig ]]; then
    simulator_args+=(+cospike-printf=0)
  fi
  set +e
  timeout --foreground "${EMBENCH_WALL_TIMEOUT:-24h}" \
    "${simulators[${config}]}" "${simulator_args[@]}" >"${log}" 2>&1
  rc=$?
  set -e

  # Keep a normalized per-run copy so consumers do not need to parse the
  # simulator's (potentially very large) combined log.
  if [[ -r "${log}" ]]; then
    awk '/^XSPERF / {
      split($2, field, "=");
      if (field[1] != "" && field[2] != "") print field[1] "\t" field[2]
    }' "${log}" >"${perf_file}"
  else
    : >"${perf_file}"
  fi
  perf_count="$(wc -l <"${perf_file}")"
  perf_complete=0
  expected_names="$(printf '%s\n' "${perf_names[@]}" | sort)"
  actual_names="$(cut -f1 "${perf_file}" | sort -u)"
  if [[ "${perf_count}" -eq "${#perf_names[@]}" && "${actual_names}" == "${expected_names}" ]]; then
    perf_complete=1
  fi

  cycles="$(sed -nE 's/.*(Completed|timeout, seed [^)]*) after[[:space:]]+([0-9]+) cycles.*/\2/p' "${log}" | tail -1)"
  if [[ -z "${cycles}" ]]; then
    cycles="$(sed -nE 's/.*after[[:space:]]+([0-9]+)[[:space:]]+(simulation )?cycles.*/\1/p' "${log}" | tail -1)"
  fi
  if [[ "${rc}" -eq 0 && "${log}" != "" ]] && \
      rg -q '\*\*\* PASSED \*\*\*' "${log}" && \
      [[ "${perf_complete}" -eq 1 ]]; then
    status=passed
  elif [[ "${rc}" -eq 0 ]] && rg -q '\*\*\* PASSED \*\*\*' "${log}"; then
    status=missing-xsperf
  elif [[ "${rc}" -eq 124 ]]; then
    status=wall-timeout
  elif [[ "${rc}" -eq 2 ]] || rg -q '\*\*\* FAILED \*\*\*' "${log}"; then
    status=failed
  else
    status=error
  fi
  printf 'status=%s\ncycles=%s\nexit=%s\nxsperf_count=%s\n' \
    "${status}" "${cycles}" "${rc}" "${perf_count}" > "${status_file}"
  printf '[done ] %-34s %-32s status=%s cycles=%s xsperf=%s/%s\n' \
    "${config}" "${benchmark}" "${status}" "${cycles:-n/a}" \
    "${perf_count}" "${#perf_names[@]}"
}

pids=()
for config in "${configs[@]}"; do
  for benchmark in "${benchmarks[@]}"; do
    run_one "${config}" "${benchmark}" &
    pids+=("$!")
    if ((${#pids[@]} >= jobs)); then
      wait "${pids[0]}" || true
      pids=("${pids[@]:1}")
    fi
  done
done
for pid in "${pids[@]}"; do
  wait "${pid}" || true
done

summary="${run_root}/summary.tsv"
printf 'benchmark\tfdip_status\tfdip_cycles\tboomv3_status\tboomv3_cycles\tfdip_over_boomv3\n' > "${summary}"
perf_summary="${run_root}/xsperf-summary.tsv"
printf 'benchmark\tconfig\tstatus\t%s\n' "$(IFS=$'\t'; printf '%s' "${perf_names[*]}")" > "${perf_summary}"
failures=0
while IFS= read -r benchmark; do
  [[ -n "${benchmark}" ]] || continue
  fdip_status_file="${run_root}/FDIPMegaBoomV3CosimPerfConfig/${benchmark}/status"
  boom_status_file="${run_root}/MegaBoomV3PerfConfig/${benchmark}/status"
  status=""; cycles=""
  fdip_status="unknown"; fdip_cycles=""; boom_status="unknown"; boom_cycles=""
  [[ -r "${fdip_status_file}" ]] && source "${fdip_status_file}"
  fdip_status_value="${status:-${fdip_status}}"; fdip_cycles_value="${cycles:-${fdip_cycles}}"
  status=""; cycles=""
  [[ -r "${boom_status_file}" ]] && source "${boom_status_file}"
  boom_status_value="${status:-${boom_status}}"; boom_cycles_value="${cycles:-${boom_cycles}}"
  ratio=""
  if [[ "${fdip_cycles_value}" =~ ^[0-9]+$ && "${boom_cycles_value}" =~ ^[0-9]+$ && "${boom_cycles_value}" -gt 0 ]]; then
    ratio="$(awk -v f="${fdip_cycles_value}" -v b="${boom_cycles_value}" 'BEGIN { printf "%.6f", f / b }')"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${benchmark}" "${fdip_status_value}" "${fdip_cycles_value}" "${boom_status_value}" "${boom_cycles_value}" "${ratio}" >> "${summary}"
  for config in "${configs[@]}"; do
    run_dir="${run_root}/${config}/${benchmark}"
    status_value="unknown"
    [[ -r "${run_dir}/status" ]] && {
      status=""; cycles=""
      source "${run_dir}/status"
      status_value="${status:-unknown}"
    }
    values=()
    for name in "${perf_names[@]}"; do
      value=""
      if [[ -r "${run_dir}/xsperf.tsv" ]]; then
        value="$(awk -v key="${name}" '$1 == key { value=$2 } END { print value }' "${run_dir}/xsperf.tsv")"
      fi
      values+=("${value}")
    done
    printf '%s\t%s\t%s\t%s\n' "${benchmark}" "${config}" "${status_value}" \
      "$(IFS=$'\t'; printf '%s' "${values[*]}")" >> "${perf_summary}"
  done
  [[ "${fdip_status_value}" == passed && "${boom_status_value}" == passed ]] || failures=1
done < "${benchmark_list}"

echo "Results: ${run_root}"
echo "Summary: ${summary}"
echo "XSPerf: ${perf_summary}"
exit "${failures}"
