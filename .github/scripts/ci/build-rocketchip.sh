#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_STAGE_DIR:?CI_STAGE_DIR must be set}"
require_rocketchip_profile

rm -rf "${CI_STAGE_DIR}"
mkdir -p "${CI_STAGE_DIR}/soc-generator/sims"

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
export COURSIER_CACHE="${CI_CACHE_ROOT}/coursier"
export SBT_OPTS="-Dsbt.ivy.home=${SBT_CACHE_ROOT}/ivy -Dsbt.global.base=${SBT_CACHE_ROOT}/global -Dsbt.boot.directory=${SBT_CACHE_ROOT}/boot -Dsbt.color=always -Dsbt.supershell=false -Dsbt.server.forcestart=true"
mkdir -p "${COURSIER_CACHE}" "${SBT_CACHE_ROOT}/ivy" \
  "${SBT_CACHE_ROOT}/global" "${SBT_CACHE_ROOT}/boot"

# SBT creates a Unix socket below JAVA_TMP_DIR. Keep this path short because
# the persistent GitHub Actions workspace exceeds the Unix socket length limit.
JAVA_TMP_DIR="${CI_SHARED_ROOT}/java/${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}"
export JAVA_TMP_DIR
mkdir -p "${JAVA_TMP_DIR}"
trap 'rm -rf "${JAVA_TMP_DIR}"' EXIT

run_in_nix '
  dependencies/scripts/init-submodules.sh
  make -C soc-generator CONFIG=RocketConfig emu
'

cp -a "${REPO_ROOT}/soc-generator/sims/verilator" \
  "${CI_STAGE_DIR}/soc-generator/sims/verilator"

submodule_digest="$(git -C "${REPO_ROOT}" submodule status --recursive | sha256sum | awk '{print $1}')"
printf '{\n  "commit": "%s",\n  "profile": "%s",\n  "submodule_digest": "%s"\n}\n' \
  "${GITHUB_SHA}" "${CI_PROFILE}" "${submodule_digest}" \
  > "${CI_STAGE_DIR}/manifest.json"
