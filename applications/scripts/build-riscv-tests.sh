#!/usr/bin/env bash

# Build the ISA and benchmark binaries consumed by the Verilator core
# regressions. Compatibility fixes are applied only to an ephemeral build copy,
# so the pinned official riscv-tests source files are never modified.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/../.." rev-parse --show-toplevel)"
TESTS_DIR="${REPO_ROOT}/applications/riscv-tests"
DEFAULT_OUTPUT="${TESTS_DIR}/build/install"
OUTPUT_DIR="${RISCV_TESTS_OUTPUT:-${DEFAULT_OUTPUT}}"

usage() {
  cat <<'EOF'
Usage: applications/scripts/build-riscv-tests.sh [--output DIRECTORY]

Build the RISC-V ISA and benchmark regression binaries.  The default output is
applications/riscv-tests/build/install.  Set RISCV_TESTS_JOBS to control make
parallelism, or RISCV_TESTS_OUTPUT instead of passing --output.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a directory" >&2; exit 2; }
      OUTPUT_DIR="$2"
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
  echo "Run this script from the Chipyard development shell:" >&2
  echo "  nix develop --command applications/scripts/build-riscv-tests.sh" >&2
  exit 1
fi

if [[ "${OUTPUT_DIR}" != /* ]]; then
  OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}"
fi

# This also initializes nested submodules when the script is used directly
# after a fresh clone. It does not change the pinned commit.
git -C "${REPO_ROOT}" submodule update --init --recursive applications/riscv-tests

if [[ ! -f "${TESTS_DIR}/benchmarks/Makefile" || ! -f "${TESTS_DIR}/isa/Makefile" ]]; then
  echo "riscv-tests submodule is unavailable: ${TESTS_DIR}" >&2
  exit 1
fi

if ! command -v riscv64-none-elf-gcc >/dev/null 2>&1; then
  echo "riscv64-none-elf-gcc is unavailable; enter the Chipyard Nix development shell." >&2
  exit 1
fi

JOBS="${RISCV_TESTS_JOBS:-${NIX_BUILD_CORES:-$(nproc)}}"
case "${JOBS}" in
  ''|*[!0-9]*|0)
    echo "RISCV_TESTS_JOBS must be a positive integer: ${JOBS}" >&2
    exit 1
    ;;
esac

OUTPUT_PARENT="$(dirname "${OUTPUT_DIR}")"
mkdir -p "${OUTPUT_PARENT}"
BUILD_DIR="$(mktemp -d "${OUTPUT_PARENT}/.riscv-tests-build.XXXXXX")"
STAGING_DIR="$(mktemp -d "${OUTPUT_PARENT}/.riscv-tests-install.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}" "${STAGING_DIR}"' EXIT

# riscv-tests writes binaries beside its sources. Build an ephemeral copy so a
# local or CI invocation leaves the pinned submodule source files untouched.
cp -a "${TESTS_DIR}/." "${BUILD_DIR}/"
rm -f "${BUILD_DIR}/.git"

# This revision predates the privileged-spec CSR renames, and its benchmark
# Makefile needs to target scalar Rocket and BOOM configurations. Keep these
# compatibility changes out of the official submodule checkout.
sed -i '/^RISCV_GCC_OPTS ?=/a RISCV_GCC_OPTS += -Wno-error=implicit-int -Wno-error=implicit-function-declaration' \
  "${BUILD_DIR}/benchmarks/Makefile"
sed -i 's/-march=rv$(XLEN)gcv/-march=rv$(XLEN)imafd/' \
  "${BUILD_DIR}/benchmarks/Makefile"
find "${BUILD_DIR}/isa" -name '*.S' -exec sed -i \
  -e 's/\<sptbr\>/satp/g' \
  -e 's/\<mbadaddr\>/mtval/g' \
  -e 's/\<sbadaddr\>/stval/g' {} +

benchmark_targets=(
  mm.riscv spmv.riscv mt-vvadd.riscv median.riscv multiply.riscv
  qsort.riscv rsort.riscv pmp.riscv towers.riscv vvadd.riscv
  dhrystone.riscv mt-matmul.riscv
)
isa_targets=(
  rv64ui rv64uc rv64um rv64ua rv64uf rv64ud rv64uzfh
  rv64uzba rv64uzbb rv64uzbs rv64mi
  rv64si-p-csr rv64si-p-icache-alias rv64si-p-ma_fetch
  rv64si-p-scall rv64si-p-wfi rv64si-p-sbreak rv64si-p-dirty
)

make -j"${JOBS}" -C "${BUILD_DIR}/benchmarks" RISCV_PREFIX=riscv64-none-elf- \
  "${benchmark_targets[@]}"
make -j"${JOBS}" -C "${BUILD_DIR}/isa" RISCV_PREFIX=riscv64-none-elf- XLEN=64 \
  "${isa_targets[@]}"

install_root="${STAGING_DIR}/riscv64-unknown-elf/share/riscv-tests"
install -d "${install_root}/isa" "${install_root}/benchmarks"
find "${BUILD_DIR}/isa" -maxdepth 1 -type f -name 'rv64*' -exec \
  install -m 0755 -t "${install_root}/isa" {} +
install -m 0755 "${BUILD_DIR}/benchmarks"/*.riscv "${install_root}/benchmarks/"

rm -rf "${OUTPUT_DIR}"
mv "${STAGING_DIR}" "${OUTPUT_DIR}"
trap - EXIT
rm -rf "${BUILD_DIR}"

echo "Built RISC-V regression tests in ${OUTPUT_DIR}"
