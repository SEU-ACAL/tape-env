#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../../.." && pwd)"
target_dir="${1:?usage: build_spi_decoder.sh TARGET_DIR LOG_DIR}"
log_dir="${2:?usage: build_spi_decoder.sh TARGET_DIR LOG_DIR}"
manifest="$repo_root/dependencies/riscv-etrace/Cargo.toml"
decoder_host="$(rustc -vV | sed -n 's/^host: //p')"
mkdir -p "$log_dir"
if [[ -n "${CARGO_HOME:-}" ]]; then
  mkdir -p "$CARGO_HOME"
fi

# A warm cache must work without contacting the registry. Resolve the checked-in
# lockfile first; only a cold cache needs a network fetch. Cargo serializes access
# to its registry cache when several CI jobs use the same runner.
printf 'CI SPI decoder: checking cached dependencies\n'
if ! cargo metadata --manifest-path "$manifest" --features elf,alloc \
  --filter-platform "$decoder_host" --frozen --format-version 1 \
  >/dev/null 2>"$log_dir/decoder-fetch.log"; then
  printf 'CI SPI decoder: fetching locked dependencies\n'
  if ! CARGO_NET_RETRY=3 CARGO_HTTP_TIMEOUT=30 \
    cargo fetch --manifest-path "$manifest" --target "$decoder_host" --locked \
    >>"$log_dir/decoder-fetch.log" 2>&1; then
    cat "$log_dir/decoder-fetch.log" >&2
    exit 1
  fi
fi

# All downloads finish before compilation. Never update dependency versions or
# access the network while building the decoder used by a regression.
printf 'CI SPI decoder: building offline\n'
cargo build --manifest-path "$manifest" --frozen \
  --target-dir "$target_dir" --release --example pulp_chipyard --features elf,alloc \
  >"$log_dir/decoder-build.log" 2>&1
