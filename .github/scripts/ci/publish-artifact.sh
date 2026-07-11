#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_STAGE_DIR:?CI_STAGE_DIR must be set}"
: "${CI_ARTIFACT_DIR:?CI_ARTIFACT_DIR must be set}"

if [[ ! -f "${CI_STAGE_DIR}/manifest.json" ]]; then
  echo "Build stage is missing manifest.json" >&2
  exit 1
fi

parent_dir="$(dirname "${CI_ARTIFACT_DIR}")"
partial_dir="${CI_ARTIFACT_DIR}.partial"
mkdir -p "${parent_dir}"
rm -rf "${partial_dir}"
cp -a "${CI_STAGE_DIR}" "${partial_dir}"
touch "${partial_dir}/COMPLETE"

if [[ -e "${CI_ARTIFACT_DIR}" ]]; then
  echo "Artifact destination already exists: ${CI_ARTIFACT_DIR}" >&2
  exit 1
fi

mv "${partial_dir}" "${CI_ARTIFACT_DIR}"
printf 'artifact_dir=%s\n' "${CI_ARTIFACT_DIR}" >> "${GITHUB_OUTPUT}"
