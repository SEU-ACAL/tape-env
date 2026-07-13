#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_ROOT:?CI_ARTIFACT_ROOT must be set}"

CI_BUILD_JOBS="${CI_BUILD_JOBS:-8}"
CI_BUILD_CONFIGS="${CI_BUILD_CONFIGS:-QuadChannelRocketConfig MediumBoomV3CosimConfig MediumBoomV4CosimConfig}"

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

export CI_BUILD_CONFIGS CI_BUILD_JOBS

# The self-hosted workspace survives canceled jobs. Deinitialize any partial
# worktrees so init-submodules can recreate them from the retained git cache.
git -C "${REPO_ROOT}" submodule deinit --force --all
git -C "${REPO_ROOT}" submodule sync --recursive

# Chipyard aggregates Gemmini during Scala compilation even though these core
# regressions do not exercise the accelerator. The root submodule is sufficient.
git -C "${REPO_ROOT}" submodule update --init soc-generator/generator/gemmini

# SBT and Coursier updates are not safe to share between independent builder
# workspaces. Keep reusable caches local to one self-hosted runner.
CI_CACHE_KEY="${RUNNER_NAME:-${HOSTNAME:-local}}"
SBT_CACHE_ROOT="${CI_CACHE_ROOT}/sbt/${CI_CACHE_KEY}"
CI_COURSIER_CACHE="${CI_CACHE_ROOT}/coursier/${CI_CACHE_KEY}"
CI_SOURCE_REVISION="${GITHUB_SHA:-$(git -C "${REPO_ROOT}" rev-parse HEAD)}"
CI_CLASSPATH_CACHE="${CI_CACHE_ROOT}/classpath/${CI_CACHE_KEY}/${CI_SOURCE_REVISION}"
CI_SBT_OPTS="-Dsbt.ivy.home=${SBT_CACHE_ROOT}/ivy -Dsbt.global.base=${SBT_CACHE_ROOT}/global -Dsbt.boot.directory=${SBT_CACHE_ROOT}/boot -Dsbt.color=always -Dsbt.supershell=false -Dsbt.server.forcestart=true"
export CI_COURSIER_CACHE CI_CLASSPATH_CACHE CI_SBT_OPTS
mkdir -p "${CI_CLASSPATH_CACHE}" "${CI_COURSIER_CACHE}" \
  "${SBT_CACHE_ROOT}/ivy" "${SBT_CACHE_ROOT}/global" "${SBT_CACHE_ROOT}/boot"

# SBT creates a Unix socket below JAVA_TMP_DIR. Keep this path short because
# the persistent GitHub Actions workspace exceeds the Unix socket length limit.
JAVA_TMP_DIR="${CI_SHARED_ROOT}/java/${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}"
export JAVA_TMP_DIR
mkdir -p "${JAVA_TMP_DIR}"
trap 'rm -rf "${JAVA_TMP_DIR}"' EXIT

run_in_nix '
  export COURSIER_CACHE="${CI_COURSIER_CACHE}"
  export CLASSPATH_CACHE="${CI_CLASSPATH_CACHE}"
  export SBT_OPTS="${CI_SBT_OPTS}"
  dependencies/scripts/init-submodules.sh

  remove_invalid_jars() {
    while IFS= read -r -d "" jar; do
      if ! jar tf "${jar}" >/dev/null 2>&1; then
        echo "Removing corrupt JAR from CI cache: ${jar}" >&2
        rm -f "${jar}"
      fi
    done < <(find "${CI_COURSIER_CACHE}" "${SBT_CACHE_ROOT}/ivy" \
      "${CI_CLASSPATH_CACHE}" -type f -name "*.jar" -print0)
  }

  # Prime both SBT assemblies before launching independent Make processes;
  # otherwise emulator builds can race to create the shared classpath JARs.
  first_config="${CI_BUILD_CONFIGS%% *}"
  make -C soc-generator/sims/verilator CONFIG="${first_config}" \
    CLASSPATH_CACHE="${CI_SHARED_ROOT}/empty-classpath-cache/${GITHUB_RUN_ID}" clean
  for attempt in 1 2 3; do
    remove_invalid_jars
    if make -C soc-generator/sims/verilator CONFIG="${first_config}" firrtl \
      "${CI_CLASSPATH_CACHE}/tapeout.jar"; then
      break
    fi
    rm -f "${CI_CLASSPATH_CACHE}"/*.jar
    if [[ "${attempt}" -eq 3 ]]; then
      exit 1
    fi
    echo "Classpath prebuild failed; retrying after cache repair (${attempt}/3)" >&2
    sleep 15
  done

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
  test_rules="${REPO_ROOT}/soc-generator/sims/verilator/generated-src/chipyard.harness.TestHarness.${config}/chipyard.harness.TestHarness.${config}.d"
  if [[ ! -f "${simulator}" ]]; then
    echo "Built Verilator simulator is missing: ${simulator}" >&2
    exit 1
  fi
  if [[ ! -f "${test_rules}" ]]; then
    echo "Generated regression rules are missing: ${test_rules}" >&2
    exit 1
  fi
  mkdir -p "${CI_ARTIFACT_ROOT}/${config}"
  cp -a "${simulator}" "${CI_ARTIFACT_ROOT}/${config}/"
  cp -a "${test_rules}" "${CI_ARTIFACT_ROOT}/${config}/test-rules.d"
done
