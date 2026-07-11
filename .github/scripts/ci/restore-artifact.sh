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

runner_sim="${REPO_ROOT}/soc-generator/sims/verilator"
if [[ -L "${runner_sim}" ]]; then
  rm "${runner_sim}"
  git -C "${REPO_ROOT}" checkout -- soc-generator/sims/verilator
fi

if [[ ! -f "${runner_sim}/Makefile" ]]; then
  echo "Runner simulator Makefile is missing: ${runner_sim}/Makefile" >&2
  exit 1
fi

rm -rf "${runner_sim}/generated-src"
ln -s "${artifact_sim}/generated-src" "${runner_sim}/generated-src"

shopt -s nullglob
simulator_count=0
for artifact_simulator in "${artifact_sim}"/simulator-*; do
  simulator_name="$(basename "${artifact_simulator}")"
  rm -f "${runner_sim}/${simulator_name}"
  ln -s "${artifact_simulator}" "${runner_sim}/${simulator_name}"
  ((simulator_count += 1))
done

if [[ ${simulator_count} -eq 0 ]]; then
  echo "Artifact has no Verilator simulator binary: ${artifact_sim}" >&2
  exit 1
fi
