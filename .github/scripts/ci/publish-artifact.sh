#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_DIR:?CI_ARTIFACT_DIR must be set}"

source_sim="${REPO_ROOT}/soc-generator/sims/verilator"
if [[ ! -d "${source_sim}" ]]; then
  echo "Built Verilator directory is missing: ${source_sim}" >&2
  exit 1
fi

parent_dir="$(dirname "${CI_ARTIFACT_DIR}")"
mkdir -p "${parent_dir}"
rm -rf "${CI_ARTIFACT_DIR}"
cp -a "${source_sim}" "${CI_ARTIFACT_DIR}"
printf 'run_number=%s\nrun_id=%s\nrun_attempt=%s\nsha=%s\nref=%s\npr_number=%s\n' \
  "${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER must be set}" \
  "${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}" \
  "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT must be set}" \
  "${GITHUB_SHA:?GITHUB_SHA must be set}" \
  "${GITHUB_REF:?GITHUB_REF must be set}" \
  "${CI_PR_NUMBER:-}" > "${CI_ARTIFACT_DIR}/source.txt"
printf 'artifact_dir=%s\n' "${CI_ARTIFACT_DIR}" >> "${GITHUB_OUTPUT}"
