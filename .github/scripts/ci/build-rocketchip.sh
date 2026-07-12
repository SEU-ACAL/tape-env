#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

CI_BUILD_JOBS="${CI_BUILD_JOBS:-32}"
case "${CI_BUILD_JOBS}" in
  ''|*[!0-9]*|0)
    echo "CI_BUILD_JOBS must be a positive integer: ${CI_BUILD_JOBS}" >&2
    exit 1
    ;;
esac
export CI_BUILD_JOBS

# The self-hosted workspace survives canceled jobs. Deinitialize any partial
# worktrees so init-submodules can recreate them from the retained git cache.
git -C "${REPO_ROOT}" submodule deinit --force --all
git -C "${REPO_ROOT}" submodule sync --recursive

# chipyard aggregates Gemmini even for RocketConfig. Only its root submodule is
# needed for Scala compilation; its software submodules remain unnecessary.
git -C "${REPO_ROOT}" submodule update --init soc-generator/generator/gemmini

# Keep immutable dependency downloads outside the checkout because
# actions/checkout removes untracked files from the persistent workspace.
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
  make -j"${CI_BUILD_JOBS}" -C soc-generator CONFIG=RocketConfig emu
'
