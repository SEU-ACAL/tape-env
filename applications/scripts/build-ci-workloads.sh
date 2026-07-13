#!/usr/bin/env bash

# Build the software inputs consumed by the Rocket and BOOM regression CI.
# Run from `nix develop`; publication intentionally refuses to overwrite an
# existing workload directory so the CI never observes a partial replacement.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/../.." rev-parse --show-toplevel)"
CI_WORKLOAD_ROOT="${CI_WORKLOAD_ROOT:-/data2/ci-workloads}"

if [[ "${CI_WORKLOAD_ROOT}" != /* ]]; then
  echo "CI_WORKLOAD_ROOT must be an absolute path: ${CI_WORKLOAD_ROOT}" >&2
  exit 2
fi

if [[ -e "${CI_WORKLOAD_ROOT}" ]]; then
  echo "Refusing to overwrite existing CI workload directory: ${CI_WORKLOAD_ROOT}" >&2
  exit 1
fi

parent_dir="$(dirname "${CI_WORKLOAD_ROOT}")"
workload_name="$(basename "${CI_WORKLOAD_ROOT}")"
mkdir -p "${parent_dir}"
staging_dir="$(mktemp -d "${parent_dir}/.${workload_name}.XXXXXX")"
trap 'rm -rf "${staging_dir}"' EXIT

"${SCRIPT_DIR}/build-riscv-tests.sh" --output "${staging_dir}/riscv-tests"

cmake -S "${REPO_ROOT}/applications/tests" -B "${staging_dir}/hello-build"
cmake --build "${staging_dir}/hello-build" --target hello
install -m 0755 "${staging_dir}/hello-build/hello.riscv" "${staging_dir}/hello.riscv"
rm -rf "${staging_dir}/hello-build"

test -d "${staging_dir}/riscv-tests/riscv64-unknown-elf/share/riscv-tests"
test -x "${staging_dir}/hello.riscv"
chmod -R a+rX "${staging_dir}"

mv "${staging_dir}" "${CI_WORKLOAD_ROOT}"
trap - EXIT

echo "Built CI workloads in ${CI_WORKLOAD_ROOT}"
