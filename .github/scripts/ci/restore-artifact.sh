#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

: "${CI_ARTIFACT_DIR:?CI_ARTIFACT_DIR must be set}"
: "${CI_SIMULATOR_NAME:?CI_SIMULATOR_NAME must be set}"

artifact_sim="${CI_ARTIFACT_DIR}"
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

# The run target has no simulator prerequisite when BREAK_SIM_PREREQ=1, so
# generated Verilator sources are unnecessary after the executable is built.
rm -rf "${runner_sim}/generated-src"

artifact_simulator="${artifact_sim}/${CI_SIMULATOR_NAME}"
if [[ ! -f "${artifact_simulator}" ]]; then
  echo "Artifact is missing the Verilator simulator binary: ${artifact_simulator}" >&2
  exit 1
fi

rm -f "${runner_sim}/${CI_SIMULATOR_NAME}"
ln -s "${artifact_simulator}" "${runner_sim}/${CI_SIMULATOR_NAME}"
