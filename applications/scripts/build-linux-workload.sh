#!/usr/bin/env bash

# Build a FireMarshal Linux workload for the Chipyard/Tapeout platform. The
# default embeds the rootfs into the boot ELF because P2E has no disk device.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/../.." rev-parse --show-toplevel)"
FIREMARSHAL_DIR="${REPO_ROOT}/applications/firemarshal"
DEFAULT_CONFIG="${REPO_ROOT}/applications/linux/workloads/poweroff.json"
CONFIG="${DEFAULT_CONFIG}"
OUTPUT_DIR="${REPO_ROOT}/applications/linux/build"
NO_DISK=1
JOBS="${FIREMARSHAL_JOBS:-}"

usage() {
  cat <<'EOF'
Usage: applications/scripts/build-linux-workload.sh [OPTIONS]

Build a FireMarshal Buildroot Linux workload for Tapeout/P2E.

Options:
  --config PATH    FireMarshal workload configuration (default: poweroff.json)
  --output DIR     Artifact root (default: applications/linux/build)
  --disk           Build a disk-backed image instead of P2E's initramfs ELF
  --jobs N         Parallel build jobs (default: FireMarshal auto-detect)
  -h, --help       Show this help text

The default output is a P2E-loadable ELF at:
  <output>/chipyard/tape-env-linux-poweroff/tape-env-linux-poweroff-bin-nodisk
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "--config requires a path" >&2; exit 2; }
      CONFIG="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a directory" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --disk)
      NO_DISK=0
      shift
      ;;
    --jobs)
      [[ $# -ge 2 ]] || { echo "--jobs requires a positive integer" >&2; exit 2; }
      JOBS="$2"
      shift 2
      ;;
    -h|--help)
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
  echo "Run this script from the Tapeout Nix development shell:" >&2
  echo "  nix develop --command applications/scripts/build-linux-workload.sh" >&2
  exit 1
fi

if [[ "${CONFIG}" != /* ]]; then
  CONFIG="${REPO_ROOT}/${CONFIG}"
fi
if [[ "${OUTPUT_DIR}" != /* ]]; then
  OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}"
fi

if [[ ! -f "${CONFIG}" ]]; then
  echo "Workload configuration does not exist: ${CONFIG}" >&2
  exit 1
fi

if [[ -n "${JOBS}" && ! "${JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--jobs must be a positive integer: ${JOBS}" >&2
  exit 2
fi

git -C "${REPO_ROOT}" submodule update --init applications/firemarshal
if [[ ! -x "${FIREMARSHAL_DIR}/marshal" ]]; then
  echo "FireMarshal submodule is unavailable: ${FIREMARSHAL_DIR}" >&2
  exit 1
fi

# FireMarshal keeps Linux, OpenSBI, Buildroot, and BusyBox as nested
# submodules. This is idempotent and makes the command usable after a clone.
(
  cd "${FIREMARSHAL_DIR}"
  ./init-submodules.sh
)

if [[ -n "${FIREMARSHAL_RISCV:-}" ]]; then
  export RISCV="${FIREMARSHAL_RISCV}"
fi
if [[ -z "${RISCV:-}" || ! -x "${RISCV}/bin/riscv64-unknown-linux-gnu-gcc" ]]; then
  echo "FireMarshal requires the Linux RISC-V toolchain from nix develop." >&2
  echo "Expected: \$FIREMARSHAL_RISCV/bin/riscv64-unknown-linux-gnu-gcc" >&2
  exit 1
fi
if ! command -v guestmount >/dev/null 2>&1; then
  echo "FireMarshal requires guestmount to construct the initramfs image." >&2
  echo "Install libguestfs/guestmount on this Linux host and retry." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${OUTPUT_DIR}/logs" "${OUTPUT_DIR}/run-output"

export MARSHAL_BOARD_DIR="${FIREMARSHAL_DIR}/boards/chipyard"
export MARSHAL_IMAGE_DIR="${OUTPUT_DIR}"
export MARSHAL_LOG_DIR="${OUTPUT_DIR}/logs"
export MARSHAL_RES_DIR="${OUTPUT_DIR}/run-output"
export MARSHAL_MOUNT_DIR="${OUTPUT_DIR}/mount"
if [[ -n "${JOBS}" ]]; then
  export MARSHAL_JLEVEL="${JOBS}"
fi

marshal_args=(--workdir "$(dirname "${CONFIG}")")
if [[ "${NO_DISK}" -eq 1 ]]; then
  marshal_args+=(--no-disk)
fi
marshal_args+=(build "${CONFIG}")

cd "${REPO_ROOT}"
exec "${FIREMARSHAL_DIR}/marshal" "${marshal_args[@]}"
