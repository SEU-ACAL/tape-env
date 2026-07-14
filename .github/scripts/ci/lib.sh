#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"
CI_SHARED_ROOT="${CI_SHARED_ROOT:-/data1/ci-runner}"
CI_CACHE_ROOT="${CI_CACHE_ROOT:-${CI_SHARED_ROOT}/cache}"
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
