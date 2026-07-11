#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"
CI_SHARED_ROOT="${CI_SHARED_ROOT:-/data2/ci-runner}"
CI_CACHE_ROOT="${CI_CACHE_ROOT:-${CI_SHARED_ROOT}/cache}"
CI_PROFILE="${CI_PROFILE:-rocketchip}"
NIX_BIN="${NIX_BIN:-/nix/var/nix/profiles/default/bin/nix}"

if [[ ! -x "${NIX_BIN}" ]]; then
  NIX_BIN="$(command -v nix || true)"
fi

if [[ -z "${NIX_BIN}" || ! -x "${NIX_BIN}" ]]; then
  echo "Nix is unavailable. Set NIX_BIN to a usable nix executable." >&2
  exit 1
fi

run_in_nix() {
  (
    cd "${REPO_ROOT}"
    "${NIX_BIN}" develop --command bash -leo pipefail -c "$1"
  )
}

require_rocketchip_profile() {
  if [[ "${CI_PROFILE}" != "rocketchip" ]]; then
    echo "Unsupported CI profile: ${CI_PROFILE}" >&2
    exit 1
  fi
}
