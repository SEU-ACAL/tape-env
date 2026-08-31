#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_P2E_RUN_ROOT:?CI_P2E_RUN_ROOT must be set}"
: "${P2E_HOST:?P2E_HOST must be set to user@host}"
: "${P2E_REMOTE_ROOT:?P2E_REMOTE_ROOT must be set to the remote workspace}"

P2E_PORT="${P2E_PORT:-}"
P2E_FPGA_LOCATION="${P2E_FPGA_LOCATION:-4.A}"
P2E_DESIGN_FPGA_LOCATION="${P2E_DESIGN_FPGA_LOCATION:-0.A}"
P2E_LINUX_BUILD_JOBS="${P2E_LINUX_BUILD_JOBS:-8}"
P2E_CACHE_KEY="${RUNNER_NAME:-${HOSTNAME:-local}}"
P2E_SOURCE_REVISION="${GITHUB_SHA:-$(git -C "${REPO_ROOT}" rev-parse HEAD)}"
P2E_CLASSPATH_CACHE="${CI_CACHE_ROOT}/classpath/p2e/${P2E_CACHE_KEY}/${P2E_SOURCE_REVISION}"
P2E_SBT_CACHE_ROOT="${CI_CACHE_ROOT}/sbt/p2e/${P2E_CACHE_KEY}"
P2E_COURSIER_CACHE="${CI_CACHE_ROOT}/coursier/p2e/${P2E_CACHE_KEY}"
P2E_SBT_OPTS="-Dsbt.ivy.home=${P2E_SBT_CACHE_ROOT}/ivy -Dsbt.global.base=${P2E_SBT_CACHE_ROOT}/global -Dsbt.boot.directory=${P2E_SBT_CACHE_ROOT}/boot -Dsbt.color=always -Dsbt.supershell=false -Dsbt.server.forcestart=true"
P2E_RTL_DIR="${REPO_ROOT}/dependencies/p2e-runner/platform/tape-env/generated-src/chipyard.p2e.hpec.P2ETop.HpecP2ETapeoutConfig/gen-collateral"
P2E_LINUX_OUTPUT="${CI_P2E_RUN_ROOT}/linux-workload"
P2E_LINUX_ELF="${P2E_LINUX_OUTPUT}/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console-bin-nodisk"
P2E_LINUX_DTB="${P2E_LINUX_OUTPUT}/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb"
P2E_RESULTS_ROOT="${CI_P2E_RUN_ROOT}/p2e-results"
P2E_CONFIG="${CI_P2E_RUN_ROOT}/p2e.toml"
P2E_PASSWORD_FILE="${CI_P2E_RUN_ROOT}/.p2e/hpec-p2e.password"
P2E_RUNNER="${REPO_ROOT}/dependencies/p2e-runner/bin/p2e"

if [[ ! "${P2E_HOST}" =~ ^[A-Za-z0-9._@:-]+$ ]]; then
  echo "P2E_HOST must be an SSH destination such as user@host: ${P2E_HOST}" >&2
  exit 2
fi
if [[ -n "${P2E_PORT}" ]] && ! [[ "${P2E_PORT}" =~ ^[1-9][0-9]{0,4}$ ]] \
  || [[ -n "${P2E_PORT}" && "${P2E_PORT}" -gt 65535 ]]; then
  echo "P2E_PORT must be an integer from 1 to 65535: ${P2E_PORT}" >&2
  exit 2
fi
if [[ ! "${P2E_REMOTE_ROOT}" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "P2E_REMOTE_ROOT must be an absolute path using only letters, digits, '.', '_', '-', and '/': ${P2E_REMOTE_ROOT}" >&2
  exit 2
fi
if ! [[ "${P2E_LINUX_BUILD_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "P2E_LINUX_BUILD_JOBS must be a positive integer: ${P2E_LINUX_BUILD_JOBS}" >&2
  exit 2
fi

mkdir -p \
  "${CI_P2E_RUN_ROOT}" \
  "${P2E_RESULTS_ROOT}" \
  "${P2E_CLASSPATH_CACHE}" \
  "${P2E_SBT_CACHE_ROOT}" \
  "${P2E_COURSIER_CACHE}"

if [[ -n "${P2E_SSH_PASSWORD:-}" ]]; then
  umask 077
  mkdir -p "$(dirname "${P2E_PASSWORD_FILE}")"
  printf '%s\n' "${P2E_SSH_PASSWORD}" > "${P2E_PASSWORD_FILE}"
fi

{
  echo '[remote]'
  printf 'host = "%s"\n' "${P2E_HOST}"
  if [[ -n "${P2E_PORT}" ]]; then
    printf 'port = %s\n' "${P2E_PORT}"
  fi
  printf 'remote_root = "%s"\n' "${P2E_REMOTE_ROOT}"
  echo
  echo '[p2e]'
  printf 'rtl_dir = "%s"\n' "${P2E_RTL_DIR}"
  printf 'dtb = "%s"\n' "${P2E_LINUX_DTB}"
  echo 'dtb_address = 0x8ff00000'
  printf 'fpga_location = "%s"\n' "${P2E_FPGA_LOCATION}"
  printf 'design_fpga_location = "%s"\n' "${P2E_DESIGN_FPGA_LOCATION}"
  echo 'preload_ddr = true'
} > "${P2E_CONFIG}"

run_firemarshal_in_nix() {
  (
    cd "${REPO_ROOT}"
    "${NIX_BIN}" develop .#firemarshal --command bash -leo pipefail -c "$1"
  )
}

run_p2e_in_nix() {
  (
    cd "${REPO_ROOT}"
    "${NIX_BIN}" develop .#p2e --command bash -leo pipefail -c "$1"
  )
}

git -C "${REPO_ROOT}" submodule sync --recursive
# Chipyard aggregates Gemmini and Buckyball during Scala compilation. Initialize
# their roots before the focused P2E and Linux dependency setup below.
git -C "${REPO_ROOT}" submodule update --init \
  soc-generator/generator/gemmini \
  soc-generator/generator/buckyball/src \
  2>&1 | tee "${CI_P2E_RUN_ROOT}/submodules.log"

run_in_nix '
  export COURSIER_CACHE="${P2E_COURSIER_CACHE}"
  export CLASSPATH_CACHE="${P2E_CLASSPATH_CACHE}"
  export SBT_OPTS="${P2E_SBT_OPTS}"
  ./init-submodules.sh --buckyball --linux --p2e
  make -C "${REPO_ROOT}/dependencies/p2e-runner/platform/tape-env" verilog
' 2>&1 | tee "${CI_P2E_RUN_ROOT}/p2e-rtl.log"

test -s "${P2E_RTL_DIR}/P2ETop.sv"

run_firemarshal_in_nix '
  "${REPO_ROOT}/applications/scripts/build-linux-workload.sh" \
    --output "${P2E_LINUX_OUTPUT}" \
    --htif-console \
    --jobs "${P2E_LINUX_BUILD_JOBS}"
' 2>&1 | tee "${CI_P2E_RUN_ROOT}/linux-build.log"

test -s "${P2E_LINUX_ELF}"
test -s "${P2E_LINUX_DTB}"

run_p2e_in_nix '
  "${P2E_RUNNER}" build \
    --config "${P2E_CONFIG}" \
    --results-dir "${P2E_RESULTS_ROOT}/build"
' 2>&1 | tee "${CI_P2E_RUN_ROOT}/p2e-build.log"

run_p2e_in_nix '
  "${P2E_RUNNER}" run \
    --config "${P2E_CONFIG}" \
    --image "${P2E_LINUX_ELF}" \
    --results-dir "${P2E_RESULTS_ROOT}/run"
' 2>&1 | tee "${CI_P2E_RUN_ROOT}/p2e-run.log"

case_name="$(<"${CI_P2E_RUN_ROOT}/.p2e/last-case")"
{
  echo '## Weekly P2E Linux'
  echo
  echo '| Metric | Value |'
  echo '| --- | --- |'
  echo "| P2E case | ${case_name} |"
  echo '| Linux workload | HTIF-console no-disk Buildroot |'
  echo "| FPGA location | ${P2E_FPGA_LOCATION} |"
  echo "| Design location | ${P2E_DESIGN_FPGA_LOCATION} |"
  echo '| Result | passed |'
} > "${CI_P2E_RUN_ROOT}/p2e-linux-summary.md"
