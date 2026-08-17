#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_ROOT:?CI_ARTIFACT_ROOT must be set}"

CI_VCS_BUILD_JOBS="${CI_VCS_BUILD_JOBS:-8}"
CI_VCS_BUILD_CONFIGS="${CI_VCS_BUILD_CONFIGS:-TapeoutConfig}"

case "${CI_VCS_BUILD_JOBS}" in
  ''|*[!0-9]*|0)
    echo "CI_VCS_BUILD_JOBS must be a positive integer: ${CI_VCS_BUILD_JOBS}" >&2
    exit 1
    ;;
esac

read -r -a configs <<< "${CI_VCS_BUILD_CONFIGS}"
if [[ ${#configs[@]} -eq 0 ]]; then
  echo "CI_VCS_BUILD_CONFIGS must contain at least one configuration" >&2
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

export CI_VCS_BUILD_CONFIGS CI_VCS_BUILD_JOBS

# Self-hosted workspaces persist between runs, so discard incomplete
# submodule worktrees before restoring the VCS build dependencies.
git -C "${REPO_ROOT}" submodule deinit --force --all
git -C "${REPO_ROOT}" submodule sync --recursive

# Chipyard aggregates Gemmini and Buckyball during Scala compilation. Their
# root submodules are sufficient for the VCS regression build.
git -C "${REPO_ROOT}" submodule update --init \
  soc-generator/generator/gemmini \
  soc-generator/generator/buckyball

CI_CACHE_KEY="${RUNNER_NAME:-${HOSTNAME:-local}}"
SBT_CACHE_ROOT="${CI_CACHE_ROOT}/sbt/${CI_CACHE_KEY}"
CI_COURSIER_CACHE="${CI_CACHE_ROOT}/coursier/${CI_CACHE_KEY}"
CI_SOURCE_REVISION="${GITHUB_SHA:-$(git -C "${REPO_ROOT}" rev-parse HEAD)}"
CI_CLASSPATH_CACHE="${CI_CACHE_ROOT}/classpath/${CI_CACHE_KEY}/${CI_SOURCE_REVISION}"
CI_SBT_OPTS="-Dsbt.ivy.home=${SBT_CACHE_ROOT}/ivy -Dsbt.global.base=${SBT_CACHE_ROOT}/global -Dsbt.boot.directory=${SBT_CACHE_ROOT}/boot -Dsbt.color=always -Dsbt.supershell=false -Dsbt.server.forcestart=true"
export SBT_CACHE_ROOT CI_COURSIER_CACHE CI_CLASSPATH_CACHE CI_SBT_OPTS
mkdir -p "${CI_CLASSPATH_CACHE}" "${CI_COURSIER_CACHE}" \
  "${SBT_CACHE_ROOT}/ivy" "${SBT_CACHE_ROOT}/global" "${SBT_CACHE_ROOT}/boot"

JAVA_TMP_DIR="${CI_SHARED_ROOT}/java/${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}"
export JAVA_TMP_DIR
mkdir -p "${JAVA_TMP_DIR}"
trap 'rm -rf "${JAVA_TMP_DIR}"' EXIT

run_in_nix '
  export COURSIER_CACHE="${CI_COURSIER_CACHE}"
  export CLASSPATH_CACHE="${CI_CLASSPATH_CACHE}"
  export SBT_OPTS="${CI_SBT_OPTS}"
  ./init-submodules.sh

  remove_invalid_jars() {
    while IFS= read -r -d "" jar; do
      if ! jar tf "${jar}" >/dev/null 2>&1; then
        rm -f "${jar}"
      fi
    done < <(find "${CI_COURSIER_CACHE}" "${SBT_CACHE_ROOT}/ivy" \
      "${CI_CLASSPATH_CACHE}" -type f -name "*.jar" -print0)
  }

  first_config="${CI_VCS_BUILD_CONFIGS%% *}"
  make -C soc-generator/sims/vcs CONFIG="${first_config}" \
    CLASSPATH_CACHE="${CI_SHARED_ROOT}/empty-classpath-cache/${GITHUB_RUN_ID}" clean
  for attempt in 1 2 3; do
    remove_invalid_jars
    if make -C soc-generator/sims/vcs CONFIG="${first_config}" firrtl \
      "${CI_CLASSPATH_CACHE}/tapeout.jar"; then
      break
    fi
    rm -f "${CI_CLASSPATH_CACHE}"/*.jar
    if [[ "${attempt}" -eq 3 ]]; then
      exit 1
    fi
    sleep 15
  done

  read -r -a configs <<< "${CI_VCS_BUILD_CONFIGS}"
  pids=()
  for config in "${configs[@]}"; do
    make -j"${CI_VCS_BUILD_JOBS}" -C soc-generator SIM=vcs CONFIG="${config}" emu &
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
  simulator="${REPO_ROOT}/soc-generator/sims/vcs/simv-chipyard.harness-${config}"
  simulator_dir="${simulator}.daidir"
  test_rules="${REPO_ROOT}/soc-generator/sims/vcs/generated-src/chipyard.harness.TestHarness.${config}/chipyard.harness.TestHarness.${config}.d"
  if [[ ! -x "${simulator}" || ! -d "${simulator_dir}" ]]; then
    echo "Built VCS simulator or runtime directory is missing for ${config}" >&2
    exit 1
  fi
  if [[ ! -f "${test_rules}" ]]; then
    echo "Generated VCS regression rules are missing: ${test_rules}" >&2
    exit 1
  fi
  mkdir -p "${CI_ARTIFACT_ROOT}/${config}"
  cp -a "${simulator}" "${simulator_dir}" "${CI_ARTIFACT_ROOT}/${config}/"
  cp -a "${test_rules}" "${CI_ARTIFACT_ROOT}/${config}/test-rules.d"
done
