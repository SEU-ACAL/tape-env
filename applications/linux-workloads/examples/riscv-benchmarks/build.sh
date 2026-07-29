#!/usr/bin/env bash

# Build Linux user-space ports of the benchmark subset used by core CI.
# The upstream riscv-tests checkout remains untouched; its sources are copied
# into a temporary build directory before the bare-metal runtime is replaced.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
tests_dir="${repo_root}/applications/riscv-tests"
port_dir="${script_dir}"
output_dir="${LINUX_RISCV_BENCHMARKS_OUTPUT:-${port_dir}/build}"

usage() {
  cat <<'EOF'
Usage: applications/linux-workloads/examples/riscv-benchmarks/build.sh [--output DIRECTORY]

Build the Linux user-space ports of the benchmark subset used in CI. The
result contains eleven static RISC-V Linux binaries and a suite runner. The
bare-metal pmp benchmark is recorded as a runtime skip because it requires M
mode CSR and PMP access.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a directory" >&2; exit 2; }
      output_dir="$2"
      shift 2
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

if [[ "${output_dir}" != /* ]]; then
  output_dir="${repo_root}/${output_dir}"
fi

if [[ -e "${output_dir}" ]]; then
  echo "Refusing to overwrite existing output: ${output_dir}" >&2
  exit 1
fi

if [[ ! -d "${tests_dir}/benchmarks" ]]; then
  echo "riscv-tests benchmark source is unavailable: ${tests_dir}" >&2
  exit 1
fi

compiler="${RISCV_LINUX_GCC:-riscv64-unknown-linux-gnu-gcc}"
if ! command -v "${compiler}" >/dev/null 2>&1; then
  echo "RISC-V Linux compiler is unavailable: ${compiler}" >&2
  exit 1
fi

output_parent="$(dirname "${output_dir}")"
output_name="$(basename "${output_dir}")"
mkdir -p "${output_parent}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/linux-riscv-benchmarks-src.XXXXXX")"
staging_dir="$(mktemp -d "${output_parent}/.${output_name}.XXXXXX")"
cleanup() {
  rm -rf "${build_dir}" "${staging_dir}"
}
trap cleanup EXIT

source_dir="${build_dir}/benchmarks"
cp -a "${tests_dir}/benchmarks" "${source_dir}"
install -m 0644 "${port_dir}/linux_util.h" "${source_dir}/common/util.h"
install -d "${staging_dir}/bin"
install -m 0755 "${port_dir}/run-linux-riscv-benchmarks.sh" \
  "${staging_dir}/run-linux-riscv-benchmarks.sh"

common_flags=(
  -static -O2 -std=gnu99 -DPREALLOCATE=1 -D_POSIX_C_SOURCE=200809L
  -ffast-math -fno-common -fno-tree-loop-distribute-patterns
  -Wno-error=implicit-int -Wno-error=implicit-function-declaration
  -I"${source_dir}/common"
)

compile_benchmark() {
  local name="$1"
  local source_subdir="$2"
  shift 2

  "${compiler}" "${common_flags[@]}" -I"${source_dir}/${source_subdir}" \
    "$@" -lm -o "${staging_dir}/bin/${name}"
}

compile_benchmark median median \
  "${source_dir}/median/median.c" "${source_dir}/median/median_main.c"
compile_benchmark multiply multiply \
  "${source_dir}/multiply/multiply.c" "${source_dir}/multiply/multiply_main.c"
compile_benchmark qsort qsort "${source_dir}/qsort/qsort_main.c"
compile_benchmark rsort rsort "${source_dir}/rsort/rsort.c"
compile_benchmark spmv spmv "${source_dir}/spmv/spmv_main.c"
compile_benchmark towers towers "${source_dir}/towers/towers_main.c"
compile_benchmark vvadd vvadd "${source_dir}/vvadd/vvadd_main.c"
compile_benchmark dhrystone dhrystone \
  "${source_dir}/dhrystone/dhrystone.c" "${source_dir}/dhrystone/dhrystone_main.c"
compile_benchmark mm mm "${source_dir}/mm/mm.c" "${port_dir}/linux_mm_main.c"
compile_benchmark mt-vvadd mt-vvadd \
  "${source_dir}/mt-vvadd/vvadd.c" "${source_dir}/mt-vvadd/mt-vvadd.c" \
  "${port_dir}/linux_mt_main.c"
compile_benchmark mt-matmul mt-matmul \
  "${source_dir}/mt-matmul/matmul.c" "${source_dir}/mt-matmul/mt-matmul.c" \
  "${port_dir}/linux_mt_main.c"

printf '%s\n' 'pmp: skipped because it requires machine-mode PMP CSRs' > "${staging_dir}/SKIPPED"
printf '%s\n' 'Linux RISC-V benchmark suite: 11 runnable, 1 skipped (pmp)' > "${staging_dir}/README"
chmod -R a+rX "${staging_dir}"
mv "${staging_dir}" "${output_dir}"
trap - EXIT
rm -rf "${build_dir}"

echo "Built Linux RISC-V benchmarks in ${output_dir}"
