#!/usr/bin/env bash

# Compare Embench binaries on FDIP and coupled BOOMv3 Verilator simulators,
# collecting core cycles, IPC, and the full XSPerf dump from each run.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
sim_dir="${repo_root}/soc-generator/sims/verilator"
binary_dir="${script_dir}/build/bin"
benchmark_list="${script_dir}/build/BENCHMARKS"
jobs="${EMBENCH_JOBS:-2}"
results_root="${EMBENCH_RESULTS:-${script_dir}/results}"
max_cycles="${EMBENCH_MAX_CYCLES:-10000000}"
fdip_config="${EMBENCH_FDIP_CONFIG:-FDIPMegaBoomV3CosimPerfConfig}"
coupled_config="${EMBENCH_COUPLED_CONFIG:-MegaBoomV3PerfConfig}"
dramsim_ini_dir="${EMBENCH_DRAMSIM_INI_DIR:-${repo_root}/soc-generator/generator/testchipip/src/main/resources/dramsim2_ini}"
chisel_db="${EMBENCH_CHISEL_DB:-}"
skip_build=0
benchmark_filter=""

usage() {
  cat <<EOF
Usage: applications/embench/run-parallel.sh [options]

Run every built Embench binary on both Mega BOOMv3 performance configurations.
Configurations run in sequence; benchmarks within each configuration run in
parallel. Each run gets a private directory for simulator logs and XSPerf data.

Options:
  --jobs N              Maximum concurrent simulations (default: ${jobs})
  --results DIRECTORY   Results directory (default: ${results_root})
  --max-cycles N        Simulator timeout in RTL cycles (default: ${max_cycles})
  --benchmark NAME      Run only one benchmark from BENCHMARKS
  --fdip-config NAME    FDIP configuration class (default: ${fdip_config})
  --coupled-config NAME Coupled frontend configuration class (default: ${coupled_config})
  --chisel-db FILE      Write ChiselDB records to FILE (for a *DBConfig run)
  --skip-build          Use existing simulators without checking for RTL updates
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
    --fdip-config)
      [[ $# -ge 2 ]] || { echo "--fdip-config requires a value" >&2; exit 2; }
      fdip_config="$2"
      shift 2
      ;;
    --coupled-config)
      [[ $# -ge 2 ]] || { echo "--coupled-config requires a value" >&2; exit 2; }
      coupled_config="$2"
      shift 2
      ;;
    --chisel-db)
      [[ $# -ge 2 ]] || { echo "--chisel-db requires a value" >&2; exit 2; }
      chisel_db="$2"
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
[[ "$fdip_config" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "Invalid --fdip-config: ${fdip_config}" >&2; exit 2; }
[[ "$coupled_config" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "Invalid --coupled-config: ${coupled_config}" >&2; exit 2; }
[[ "$fdip_config" != "$coupled_config" ]] || { echo "FDIP and coupled configurations must differ" >&2; exit 2; }

if [[ "${results_root}" != /* ]]; then
  results_root="${repo_root}/${results_root}"
fi

if [[ ! -r "${benchmark_list}" ]]; then
  echo "Missing ${benchmark_list}; build Embench first." >&2
  exit 1
fi

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
if ((${#benchmarks[@]} == 0)); then
  echo "No benchmarks listed in ${benchmark_list}" >&2
  exit 1
fi
if [[ -n "${chisel_db}" && ${#benchmarks[@]} -ne 1 ]]; then
  echo "--chisel-db requires exactly one benchmark so runs do not share a SQLite file" >&2
  exit 2
fi
for benchmark in "${benchmarks[@]}"; do
  if [[ ! -x "${binary_dir}/${benchmark}" ]]; then
    echo "Missing binary: ${binary_dir}/${benchmark}; build Embench first." >&2
    exit 1
  fi
done

configs=("${fdip_config}" "${coupled_config}")
declare -A simulators
for config in "${configs[@]}"; do
  simulator="${sim_dir}/simulator-chipyard.harness-${config}"
  if ((!skip_build)); then
    echo "Building ${config} (incremental)..."
    build_args=()
    if [[ "${config}" == *DBConfig || -n "${chisel_db}" ]]; then
      build_args+=(ENABLE_BOOM_CHISELDB=1)
    fi
    if ! make -C "${sim_dir}" CONFIG="${config}" NUMACTL=0 "${build_args[@]}"; then
      echo "Failed to build ${config}" >&2
      exit 1
    fi
  fi
  if [[ ! -x "${simulator}" ]]; then
    echo "Missing simulator: ${simulator}" >&2
    exit 1
  fi
  simulators["${config}"]="${simulator}"
done

timestamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${results_root}" || exit 1
run_root="$(mktemp -d "${results_root}/${timestamp}-XXXXXX")" || exit 1
printf 'fdip_config=%s\ncoupled_config=%s\njobs=%s\nmax_cycles=%s\nskip_build=%s\ndramsim_ini_dir=%s\nloadmem=1\nchisel_db=%s\nbenchmarks=%s\ncycle_source=XSPerf cycles\n' \
  "${fdip_config}" "${coupled_config}" "${jobs}" "${max_cycles}" \
  "${skip_build}" "${dramsim_ini_dir}" "${chisel_db}" "${benchmarks[*]}" > "${run_root}/run-info.txt"
total_runs=$((${#benchmarks[@]} * ${#configs[@]}))
echo "[runner] ${#benchmarks[@]} benchmarks x ${#configs[@]} configs = ${total_runs} runs"
echo "[runner] parallel jobs: ${jobs}; max RTL cycles: ${max_cycles}"
echo "[runner] results: ${run_root}"

perf_value() {
  local perf_file="$1"
  local leaf="$2"
  [[ -r "${perf_file}" ]] || return 0
  # Multiple cores or repeated dumps are ambiguous; do not silently use the
  # first value. Keep the full hierarchy in xsperf.tsv for diagnosis.
  awk -F '\t' -v leaf="${leaf}" '
    { n=split($1, parts, "."); if (parts[n] == leaf) { count++; value=$2 } }
    END { if (count == 1 && value ~ /^[0-9]+$/) print value }
  ' "${perf_file}"
}

run_one() {
  local config="$1"
  local benchmark="$2"
  local run_dir="${run_root}/${config}/${benchmark}"
  local binary="${binary_dir}/${benchmark}"
  local log="${run_dir}/sim.log"
  local perf_file="${run_dir}/xsperf.tsv"
  local status_file="${run_dir}/status"
  local rc cycles sim_cycles commit_instr status perf_count perf_complete
  local -a simulator_args

  mkdir -p "${run_dir}"
  printf '[start] %-28s %-32s log=%s\n' "${config}" "${benchmark}" "${log}"
  if [[ ! -x "${binary}" ]]; then
    printf 'status=missing-binary\ncycles=\nsim_cycles=\ncommit_instr=\nexit=127\nxsperf_count=0\n' > "${status_file}"
    printf '[done ] %-28s %-32s status=missing-binary\n' "${config}" "${benchmark}"
    return 0
  fi

  # Match the make-based performance protocol: preload the ELF into the
  # backing memory and use DRAMSim2. Passing only the positional ELF makes
  # fesvr stream it through HTIF/TSI, which changes both startup time and the
  # memory timing seen by the core.
  simulator_args=(+permissive +dramsim "+dramsim_ini_dir=${dramsim_ini_dir}" \
    "+max-cycles=${max_cycles}" "+loadmem=${binary}")
  if [[ -n "${chisel_db}" ]]; then
    simulator_args+=("+chisel_db=${chisel_db}")
  fi
  simulator_args+=(+permissive-off +cycle-count +xsperf "${binary}")
  if [[ "${config}" == *Cosim* ]]; then
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
  # IPC and cycle comparisons use core counters from the same XSPerf dump.
  cycles="$(perf_value "${perf_file}" cycles)"
  commit_instr="$(perf_value "${perf_file}" commit_instr)"
  perf_complete=0
  if [[ "${cycles}" =~ ^[0-9]+$ && "${cycles}" -gt 0 && \
        "${commit_instr}" =~ ^[0-9]+$ && "${commit_instr}" -gt 0 ]]; then
    perf_complete=1
  fi

  sim_cycles="$(sed -nE 's/.*(Completed|timeout, seed [^)]*) after[[:space:]]+([0-9]+) cycles.*/\2/p' "${log}" | tail -1)"
  if [[ -z "${sim_cycles}" ]]; then
    sim_cycles="$(sed -nE 's/.*after[[:space:]]+([0-9]+)[[:space:]]+(simulation )?cycles.*/\1/p' "${log}" | tail -1)"
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
  printf 'status=%s\ncycles=%s\nsim_cycles=%s\ncommit_instr=%s\nexit=%s\nxsperf_count=%s\n' \
    "${status}" "${cycles}" "${sim_cycles}" "${commit_instr}" "${rc}" "${perf_count}" > "${status_file}"
  printf '[done ] %-34s %-32s status=%s cycles=%s xsperf=%s\n' \
    "${config}" "${benchmark}" "${status}" "${cycles:-n/a}" \
    "${perf_count}"
}

for config in "${configs[@]}"; do
  pids=()
  echo "[runner] configuration: ${config}"
  for benchmark in "${benchmarks[@]}"; do
    run_one "${config}" "${benchmark}" &
    pids+=("$!")
    if ((${#pids[@]} >= jobs)); then
      wait "${pids[0]}" || true
      pids=("${pids[@]:1}")
    fi
  done
  for pid in "${pids[@]}"; do
    wait "${pid}" || true
  done
done

summary="${run_root}/summary.tsv"
printf 'benchmark\tfdip_status\tfdip_cycles\tfdip_commit_instr\tfdip_ipc\tcoupled_status\tcoupled_cycles\tcoupled_commit_instr\tcoupled_ipc\tfdip_over_coupled_cycles\tfdip_over_coupled_ipc\n' > "${summary}"
perf_summary="${run_root}/xsperf-summary.tsv"
printf 'benchmark\tconfig\tstatus\tname\tvalue\n' > "${perf_summary}"
failures=0

for benchmark in "${benchmarks[@]}"; do
  fdip_status_file="${run_root}/${fdip_config}/${benchmark}/status"
  coupled_status_file="${run_root}/${coupled_config}/${benchmark}/status"
  fdip_status_value="unknown"; fdip_cycles_value=""; fdip_commit_value=""; fdip_ipc=""
  coupled_status_value="unknown"; coupled_cycles_value=""; coupled_commit_value=""; coupled_ipc=""
  if [[ -r "${fdip_status_file}" ]]; then
    status=""; cycles=""
    source "${fdip_status_file}"
    fdip_status_value="${status:-unknown}"; fdip_cycles_value="${cycles:-}"
  fi
  if [[ -r "${coupled_status_file}" ]]; then
    status=""; cycles=""
    source "${coupled_status_file}"
    coupled_status_value="${status:-unknown}"; coupled_cycles_value="${cycles:-}"
  fi
  fdip_perf_file="${run_root}/${fdip_config}/${benchmark}/xsperf.tsv"
  coupled_perf_file="${run_root}/${coupled_config}/${benchmark}/xsperf.tsv"
  fdip_commit_value="$(perf_value "${fdip_perf_file}" commit_instr)"
  coupled_commit_value="$(perf_value "${coupled_perf_file}" commit_instr)"
  if [[ "${fdip_cycles_value}" =~ ^[0-9]+$ && "${fdip_cycles_value}" -gt 0 && "${fdip_commit_value}" =~ ^[0-9]+$ ]]; then
    fdip_ipc="$(awk -v i="${fdip_commit_value}" -v c="${fdip_cycles_value}" 'BEGIN { printf "%.6f", i / c }')"
  fi
  if [[ "${coupled_cycles_value}" =~ ^[0-9]+$ && "${coupled_cycles_value}" -gt 0 && "${coupled_commit_value}" =~ ^[0-9]+$ ]]; then
    coupled_ipc="$(awk -v i="${coupled_commit_value}" -v c="${coupled_cycles_value}" 'BEGIN { printf "%.6f", i / c }')"
  fi
  cycle_ratio=""; ipc_ratio=""
  if [[ "${fdip_status_value}" == passed && "${coupled_status_value}" == passed ]]; then
    cycle_ratio="$(awk -v f="${fdip_cycles_value}" -v b="${coupled_cycles_value}" 'BEGIN { printf "%.6f", f / b }')"
    ipc_ratio="$(awk -v fi="${fdip_commit_value}" -v fc="${fdip_cycles_value}" \
      -v bi="${coupled_commit_value}" -v bc="${coupled_cycles_value}" \
      'BEGIN { printf "%.6f", (fi / fc) / (bi / bc) }')"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${benchmark}" "${fdip_status_value}" "${fdip_cycles_value}" "${fdip_commit_value}" "${fdip_ipc}" \
    "${coupled_status_value}" "${coupled_cycles_value}" "${coupled_commit_value}" "${coupled_ipc}" \
    "${cycle_ratio}" "${ipc_ratio}" >> "${summary}"
  for config in "${configs[@]}"; do
    run_dir="${run_root}/${config}/${benchmark}"
    status_value="unknown"
    [[ -r "${run_dir}/status" ]] && {
      status=""; cycles=""
      source "${run_dir}/status"
      status_value="${status:-unknown}"
    }
    if [[ -r "${run_dir}/xsperf.tsv" ]]; then
      while IFS=$'\t' read -r name value; do
        [[ -n "${name}" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\n' \
          "${benchmark}" "${config}" "${status_value}" "${name}" "${value}" \
          >> "${perf_summary}"
      done < "${run_dir}/xsperf.tsv"
    fi
  done
  [[ "${fdip_status_value}" == passed && "${coupled_status_value}" == passed ]] || failures=1
done

echo "Results: ${run_root}"
echo "Summary: ${summary}"
echo "XSPerf: ${perf_summary}"
exit "${failures}"
