#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
OUT=${1:-"$ROOT/trace_verification/result/address_filter_latest"}
ELF="$ROOT/applications/tests/build/test_address_fixed.riscv"
SIM="$ROOT/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutRocketConfig"

mkdir -p "$OUT"

nix develop "$ROOT#default" --command bash -c \
  "cd '$ROOT/applications/tests/build' && make test_address_fixed -j\$(nproc)"

nix develop "$ROOT#default" --command bash -c \
  "cd '$ROOT/soc-generator/sims/vcs' && '$SIM' +permissive +notimingcheck +loadmem='$ELF' +max-cycles=50000000 +trace_spi_nibbles='$OUT/trace_nibbles.txt' +pulp_filter_debug +permissive-off '$ELF'" \
  > "$OUT/vcs.log" 2>&1

python3 "$ROOT/applications/tests/trace/deframe_trace_spi.py" \
  "$OUT/trace_nibbles.txt" "$OUT/trace_encap.bin" \
  | tee "$OUT/deframe.log"

nix develop "$ROOT#default" --command bash -c \
  "cd '$ROOT/dependencies/riscv-etrace' && cargo build --release --example pulp_chipyard --features elf,alloc"

nix develop "$ROOT#default" --command bash -c \
  "cd '$ROOT/dependencies/riscv-etrace' && target/release/examples/pulp_chipyard '$OUT/trace_encap.bin' '$ELF'" \
  > "$OUT/reconstructed_instruction_trace.txt" \
  2> "$OUT/raw_etrace_packet_decode.txt"

nix develop "$ROOT#default" --command bash -c \
  "python3 '$ROOT/applications/tests/trace/extract_accepted_trace.py' '$OUT/vcs.log' '$ELF'" \
  > "$OUT/rtl_accepted_instruction_trace.txt"

grep -E 'TRACE_SPI_RECONSTRUCT_SUMMARY|TRACE_EXPORT_COMPLETE|\*\*\* PASSED \*\*\*' \
  "$OUT/vcs.log" || true
grep 'PULP_ETRACE_RECONSTRUCT' "$OUT/raw_etrace_packet_decode.txt"
echo "ADDRESS_FILTER_ARTIFACTS=$OUT"
