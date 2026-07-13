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

zephyr_source="${REPO_ROOT}/applications/zephyr"
zephyr_workspace="${staging_dir}/zephyr-workspace"
zephyr_build="${staging_dir}/zephyr-build"

git -C "${REPO_ROOT}" submodule update --init applications/zephyr

if [[ ! -f "${zephyr_source}/west-riscv.yml" ]]; then
  echo "Zephyr submodule is unavailable: ${zephyr_source}" >&2
  exit 1
fi
if ! command -v west >/dev/null 2>&1; then
  echo "west is unavailable; enter the Chipyard Nix development shell." >&2
  exit 1
fi

mkdir -p "${zephyr_workspace}"
git clone --shared --no-checkout "${zephyr_source}" "${zephyr_workspace}/zephyr"
git -C "${zephyr_workspace}/zephyr" checkout --detach "$(git -C "${zephyr_source}" rev-parse HEAD)"
(
  cd "${zephyr_workspace}"
  west init -l --mf west-riscv.yml zephyr
  west_updated=false
  for attempt in 1 2 3; do
    if west update --narrow; then
      west_updated=true
      break
    fi
    echo "West dependency update attempt ${attempt} failed; retrying." >&2
  done
  if [[ "${west_updated}" != true ]]; then
    echo "Unable to fetch the pinned Zephyr dependencies." >&2
    exit 1
  fi
)

: "${ZEPHYR_RISCV:?ZEPHYR_RISCV must be set by the Chipyard Nix development shell}"
(
  cd "${zephyr_workspace}"
  ZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
  CROSS_COMPILE="${ZEPHYR_RISCV}/bin/riscv64-unknown-elf-" \
  west build -s zephyr/samples/chipyard/hello_world \
    -b chipyard_riscv64 -d "${zephyr_build}" \
    --extra-conf "${REPO_ROOT}/applications/zephyr-ci.conf"
)
install -D -m 0755 "${zephyr_build}/zephyr/zephyr.elf" "${staging_dir}/zephyr/zephyr.elf"
rm -rf "${zephyr_workspace}" "${zephyr_build}"

test -d "${staging_dir}/riscv-tests/riscv64-unknown-elf/share/riscv-tests"
test -x "${staging_dir}/hello.riscv"
test -x "${staging_dir}/zephyr/zephyr.elf"
chmod -R a+rX "${staging_dir}"

mv "${staging_dir}" "${CI_WORKLOAD_ROOT}"
trap - EXIT

echo "Built CI workloads in ${CI_WORKLOAD_ROOT}"
