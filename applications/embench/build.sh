#!/usr/bin/env bash

# Build the Embench-IoT programs as bare-metal RV64 HTIF ELF files.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
embench_dir="${script_dir}/embench-iot"
output_dir="${EMBENCH_OUTPUT:-${script_dir}/build}"

usage() {
  cat <<'EOF'
Usage: applications/embench/build.sh [--output DIRECTORY]

Build the Embench-IoT suite as bare-metal RV64 HTIF ELF binaries. The default
output directory is applications/embench/build.
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

if [[ -z "${IN_NIX_SHELL:-}" ]]; then
  echo "Run this script from the Chipyard Nix development shell:" >&2
  echo "  nix develop --command applications/embench/build.sh" >&2
  exit 1
fi

if [[ "${output_dir}" != /* ]]; then
  output_dir="${repo_root}/${output_dir}"
fi

if [[ -e "${output_dir}" ]]; then
  echo "Refusing to overwrite existing output: ${output_dir}" >&2
  exit 1
fi

if [[ ! -x "${embench_dir}/build_all.py" ]]; then
  echo "Embench-IoT submodule is unavailable: ${embench_dir}" >&2
  exit 1
fi

compiler="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
if ! command -v "${compiler}" >/dev/null 2>&1; then
  echo "RISC-V bare-metal compiler is unavailable: ${compiler}" >&2
  exit 1
fi

output_parent="$(dirname "${output_dir}")"
output_name="$(basename "${output_dir}")"
mkdir -p "${output_parent}"
staging_dir="$(mktemp -d "${output_parent}/.${output_name}.XXXXXX")"
cleanup() {
  rm -rf "${staging_dir}"
}
trap cleanup EXIT

build_dir="${staging_dir}/intermediate"
log_dir="${staging_dir}/logs"
benchmarks=(
  aha-mont64 crc32 edn huffbench matmult-int minver nbody nettle-aes
  nettle-sha256 nsichneu picojpeg qrduino sglib-combined slre st statemate ud
  wikisort
)

(
  cd "${embench_dir}"
  ./build_all.py \
    --arch riscv32 \
    --chip generic \
    --board ri5cyverilator \
    --cc "${compiler}" \
    --cflags="-c -O2 -std=gnu99 -ffunction-sections -mabi=lp64d -specs=htif_nano.specs" \
    --ldflags="-Wl,-gc-sections -specs=htif_nano.specs" \
    --user-libs="-lm" \
    --builddir "${build_dir}" \
    --logdir "${log_dir}" \
    --clean \
    --verbose
)

install -d "${staging_dir}/bin"
for benchmark in "${benchmarks[@]}"; do
  install -m 0755 "${build_dir}/src/${benchmark}/${benchmark}" \
    "${staging_dir}/bin/${benchmark}"
done
printf '%s\n' "${benchmarks[@]}" > "${staging_dir}/BENCHMARKS"
printf '%s\n' 'cubic: skipped; the Nix GCC libgcc is medlow while HTIF loads at 0x80000000' > \
  "${staging_dir}/SKIPPED"
printf '%s\n' 'Embench-IoT bare-metal RV64 HTIF binaries' > "${staging_dir}/README"

mv "${staging_dir}" "${output_dir}"
trap - EXIT

echo "Built ${#benchmarks[@]} Embench-IoT binaries in ${output_dir}/bin"
