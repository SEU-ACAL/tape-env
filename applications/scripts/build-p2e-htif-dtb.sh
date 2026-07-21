#!/usr/bin/env bash

# Derive a P2E DTB that routes OpenSBI's console to its HTIF device. The
# original generated DTS remains untouched so normal UART runs are unaffected.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/../.." rev-parse --show-toplevel)"
DEFAULT_DTS="${REPO_ROOT}/dependencies/fpga/generated-src/chipyard.p2e.hpec.P2ETop.HpecP2ETapeoutConfig/chipyard.p2e.hpec.P2ETop.HpecP2ETapeoutConfig.dts"
DTS="${DEFAULT_DTS}"
OUTPUT=""

usage() {
  cat <<'EOF'
Usage: applications/scripts/build-p2e-htif-dtb.sh --output FILE [--dts FILE]

Create an HTIF-console DTB from the generated HPEC P2E DTS. The output DTS
sets /chosen/stdout-path to /htif; it does not modify the generated source.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dts)
      [[ $# -ge 2 ]] || { echo "--dts requires a path" >&2; exit 2; }
      DTS="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 2; }
      OUTPUT="$2"
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

if [[ -z "${OUTPUT}" ]]; then
  echo "--output is required" >&2
  usage >&2
  exit 2
fi
if [[ "${DTS}" != /* ]]; then
  DTS="${REPO_ROOT}/${DTS}"
fi
if [[ "${OUTPUT}" != /* ]]; then
  OUTPUT="${REPO_ROOT}/${OUTPUT}"
fi
if [[ ! -f "${DTS}" ]]; then
  echo "Generated P2E DTS does not exist: ${DTS}" >&2
  exit 1
fi
if ! command -v dtc >/dev/null 2>&1; then
  echo "dtc is required; run this command through tape-env nix develop." >&2
  exit 1
fi
if ! rg -q 'stdout-path[[:space:]]*=' "${DTS}"; then
  echo "P2E DTS has no /chosen/stdout-path: ${DTS}" >&2
  exit 1
fi
if ! rg -q 'compatible[[:space:]]*=[[:space:]]*"ucb,htif0"' "${DTS}"; then
  echo "P2E DTS has no ucb,htif0 node: ${DTS}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"
temporary_dts="$(mktemp)"
trap 'rm -f "${temporary_dts}"' EXIT
cp "${DTS}" "${temporary_dts}"
perl -0pi -e 's/(chosen\s*\{\s*)stdout-path\s*=\s*[^;]+;/${1}stdout-path = "\/htif";/s' "${temporary_dts}"
if ! rg -q 'stdout-path[[:space:]]*=[[:space:]]*"/htif"' "${temporary_dts}"; then
  echo "Failed to select HTIF as the P2E stdout path" >&2
  exit 1
fi

dtc -I dts -O dtb -o "${OUTPUT}" "${temporary_dts}"
cp "${temporary_dts}" "${OUTPUT%.dtb}.dts"
echo "Generated P2E HTIF-console DTB: ${OUTPUT}"
