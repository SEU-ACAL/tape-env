#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_ROOT:?CI_ARTIFACT_ROOT must be set}"

CI_BUILD_JOBS="${CI_BUILD_JOBS:-8}"
CI_BUILD_CONFIGS="${CI_BUILD_CONFIGS:-QuadChannelRocketConfig MediumBoomV3CosimConfig MediumBoomV4CosimConfig}"
CI_ROCKET_CONFIG="${CI_ROCKET_CONFIG:-QuadChannelRocketConfig}"

case "${CI_BUILD_JOBS}" in
  ''|*[!0-9]*|0)
    echo "CI_BUILD_JOBS must be a positive integer: ${CI_BUILD_JOBS}" >&2
    exit 1
    ;;
esac

read -r -a configs <<< "${CI_BUILD_CONFIGS}"
if [[ ${#configs[@]} -eq 0 ]]; then
  echo "CI_BUILD_CONFIGS must contain at least one configuration" >&2
  exit 1
fi

for config in "${configs[@]}"; do
  case "${config}" in
    [A-Za-z][A-Za-z0-9_]*) ;;
    *)
      echo "Invalid Chipyard configuration name: ${config}" >&2
      exit 1
      ;;
  esac
done

if [[ " ${CI_BUILD_CONFIGS} " != *" ${CI_ROCKET_CONFIG} "* ]]; then
  echo "CI_ROCKET_CONFIG must be included in CI_BUILD_CONFIGS: ${CI_ROCKET_CONFIG}" >&2
  exit 1
fi
export CI_BUILD_CONFIGS CI_BUILD_JOBS CI_ROCKET_CONFIG

# The self-hosted workspace survives canceled jobs. Deinitialize any partial
# worktrees so init-submodules can recreate them from the retained git cache.
git -C "${REPO_ROOT}" submodule deinit --force --all
git -C "${REPO_ROOT}" submodule sync --recursive

SBT_CACHE_ROOT="${CI_CACHE_ROOT}/sbt"
CI_COURSIER_CACHE="${CI_CACHE_ROOT}/coursier"
CI_SBT_OPTS="-Dsbt.ivy.home=${SBT_CACHE_ROOT}/ivy -Dsbt.global.base=${SBT_CACHE_ROOT}/global -Dsbt.boot.directory=${SBT_CACHE_ROOT}/boot -Dsbt.color=always -Dsbt.supershell=false -Dsbt.server.forcestart=true"
export CI_COURSIER_CACHE CI_SBT_OPTS
mkdir -p "${CI_COURSIER_CACHE}" "${SBT_CACHE_ROOT}/ivy" \
  "${SBT_CACHE_ROOT}/global" "${SBT_CACHE_ROOT}/boot"

# SBT creates a Unix socket below JAVA_TMP_DIR. Keep this path short because
# the persistent GitHub Actions workspace exceeds the Unix socket length limit.
JAVA_TMP_DIR="${CI_SHARED_ROOT}/java/${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}"
export JAVA_TMP_DIR
mkdir -p "${JAVA_TMP_DIR}"
trap 'rm -rf "${JAVA_TMP_DIR}"' EXIT

run_in_nix '
  export COURSIER_CACHE="${CI_COURSIER_CACHE}"
  export SBT_OPTS="${CI_SBT_OPTS}"
  dependencies/scripts/init-submodules.sh

  # Prime the shared Chipyard classpath before launching independent Make
  # processes; otherwise all three builds race to create the same SBT output.
  first_config="${CI_BUILD_CONFIGS%% *}"
  make -C soc-generator/sims/verilator CONFIG="${first_config}" firrtl

  read -r -a configs <<< "${CI_BUILD_CONFIGS}"
  pids=()
  for config in "${configs[@]}"; do
    make -j"${CI_BUILD_JOBS}" -C soc-generator CONFIG="${config}" emu &
    pids+=("$!")
  done

  status=0
  for pid in "${pids[@]}"; do
    wait "${pid}" || status=1
  done
  exit "${status}"
'

rm -rf "${CI_ARTIFACT_ROOT}"
mkdir -p "${CI_ARTIFACT_ROOT}"
for config in "${configs[@]}"; do
  simulator="${REPO_ROOT}/soc-generator/sims/verilator/simulator-chipyard.harness-${config}"
  if [[ ! -f "${simulator}" ]]; then
    echo "Built Verilator simulator is missing: ${simulator}" >&2
    exit 1
  fi
  mkdir -p "${CI_ARTIFACT_ROOT}/${config}"
  cp -a "${simulator}" "${CI_ARTIFACT_ROOT}/${config}/"
done

run_in_nix '
  cmake -S applications/tests -B "${CI_ARTIFACT_ROOT}/${CI_ROCKET_CONFIG}/tests-build"
  cmake --build "${CI_ARTIFACT_ROOT}/${CI_ROCKET_CONFIG}/tests-build" --target hello
'
