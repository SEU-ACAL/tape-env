#!/usr/bin/env bash

# Build and run the instrumented edn workload on both performance configs.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
build_root="${script_dir}/build"
work_dir="${build_root}/perf-edn"
mkdir -p "${work_dir}"

if [[ -z "${IN_NIX_SHELL:-}" ]]; then
  echo "Run from the Chipyard Nix shell." >&2
  exit 1
fi

cc="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
sim_dir="${repo_root}/soc-generator/sims/verilator"
include_flags=(
  "-I${script_dir}/embench-iot/support"
  "-I${script_dir}/embench-iot/config/riscv32/boards/ri5cyverilator"
  "-I${script_dir}/embench-iot/config/riscv32/chips/generic"
  "-I${script_dir}/embench-iot/config/riscv32"
)
cflags=(-O2 -std=gnu99 -ffunction-sections -mabi=lp64d -specs=htif_nano.specs
  "${include_flags[@]}" -DCPU_MHZ=1 -DWARMUP_HEAT=1)
common_objects=(
  "${build_root}/intermediate/config/riscv32/chips/generic/chipsupport.o"
  "${build_root}/intermediate/config/riscv32/boards/ri5cyverilator/boardsupport.o"
  "${build_root}/intermediate/support/beebsc.o"
)

if [[ ! -r "${build_root}/intermediate/src/edn/libedn.o" ]]; then
  echo "Missing built edn objects; run applications/embench/build.sh first." >&2
  exit 1
fi

"${cc}" "${cflags[@]}" -c "${script_dir}/perf-main.c" -o "${work_dir}/perf-main.o"
"${cc}" -Wl,-gc-sections -specs=htif_nano.specs -o "${work_dir}/edn-perf" \
  "${work_dir}/perf-main.o" "${build_root}/intermediate/src/edn/libedn.o" \
  "${common_objects[@]}" -lm

# FDIP is validated with Spike commit cosimulation; the coupled BOOMv3
# baseline intentionally runs without cosimulation.
for config in FDIPMegaBoomV3CosimPerfConfig MegaBoomV3PerfConfig; do
  simulator="${sim_dir}/simulator-chipyard.harness-${config}"
  if [[ ! -x "${simulator}" ]]; then
    make -C "${sim_dir}" CONFIG="${config}" NUMACTL=0
  fi
  log="${work_dir}/${config}.log"
  echo "Running ${config}"
  simulator_args=(+cycle-count +max-cycles=10000000 "${work_dir}/edn-perf" +xsperf)
  if [[ "${config}" == FDIPMegaBoomV3CosimPerfConfig ]]; then
    simulator_args+=(+cospike-printf=0)
  fi
  if ! "${simulator}" "${simulator_args[@]}" >"${log}" 2>&1; then
    echo "Simulator failed for ${config}; simulator log: ${log}" >&2
    tail -20 "${log}" >&2
    exit 1
  fi
  rg -q 'XSPERF ' "${log}" || {
    echo "No XSPERF dump for ${config}; simulator log: ${log}" >&2
    tail -20 "${log}" >&2
    exit 1
  }
done
