#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_STAGE_DIR:?CI_STAGE_DIR must be set}"
require_rocketchip_profile

rm -rf "${CI_STAGE_DIR}"
mkdir -p "${CI_STAGE_DIR}/soc-generator/sims"

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
