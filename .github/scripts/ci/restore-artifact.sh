#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_DIR:?CI_ARTIFACT_DIR must be set}"
require_rocketchip_profile

manifest="${CI_ARTIFACT_DIR}/manifest.json"
if [[ ! -f "${CI_ARTIFACT_DIR}/COMPLETE" || ! -f "${manifest}" ]]; then
  echo "Artifact is incomplete: ${CI_ARTIFACT_DIR}" >&2
  exit 1
fi

grep -Fq "\"commit\": \"${GITHUB_SHA}\"" "${manifest}"
grep -Fq "\"profile\": \"${CI_PROFILE}\"" "${manifest}"

artifact_sim="${CI_ARTIFACT_DIR}/soc-generator/sims/verilator"
if [[ ! -d "${artifact_sim}" ]]; then
  echo "Artifact is missing the Verilator simulator directory" >&2
  exit 1
fi

rm -rf "${REPO_ROOT}/soc-generator/sims/verilator"
cp -a "${artifact_sim}" "${REPO_ROOT}/soc-generator/sims/verilator"
