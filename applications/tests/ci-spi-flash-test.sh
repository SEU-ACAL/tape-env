#!/usr/bin/env bash
set -euo pipefail

# Build and run the SPI flash stress test against the TapeoutConfig VCS
# simulator. Run from a Nix shell that provides cmake, Python, the RISC-V
# compiler, and VCS.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

simv="${SIMV:-$repo_root/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig}"
dram_ini="${DRAM_INI:-$repo_root/soc-generator/generator/testchipip/src/main/resources/dramsim2_ini}"
rounds="${SPI_FLASH_STRESS_ROUNDS:-16}"
transfer_bytes="${SPI_FLASH_STRESS_TRANSFER_BYTES:-64}"
timeout_polls="${SPI_FLASH_TIMEOUT_POLLS:-1000000}"
sim_timeout="${SPI_FLASH_CI_TIMEOUT:-300}"
build_test="${BUILD_TEST:-1}"

for required in cmake python3 timeout; do
  if ! command -v "$required" >/dev/null 2>&1; then
    printf 'CI SPI flash error: required command not found: %s\n' "$required" >&2
    exit 2
  fi
done

for required_path in "$simv" "$dram_ini"; do
  if [[ ! -e "$required_path" ]]; then
    printf 'CI SPI flash error: required path not found: %s\n' "$required_path" >&2
    exit 2
  fi
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/chipyard-spi-flash-ci.XXXXXX")"
build_dir="$work_dir/build"
flash_image="$work_dir/spiflash.img"
log_file="$work_dir/spi-flash-vcs.log"

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ "$exit_code" -ne 0 ]]; then
    printf 'CI SPI flash log: %s\n' "$log_file" >&2
    tail -80 "$log_file" 2>/dev/null || true
  else
    rm -rf "$work_dir"
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

if [[ "$build_test" == 1 ]]; then
  cmake -S "$script_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-DSPI_FLASH_STRESS_ROUNDS=$rounds -DSPI_FLASH_STRESS_TRANSFER_BYTES=$transfer_bytes -DSPI_FLASH_TIMEOUT_POLLS=$timeout_polls"
  cmake --build "$build_dir" --target tapeout_spi_flash_stress -j2
fi

elf="${ELF:-$build_dir/tapeout_spi_flash_stress.riscv}"
if [[ ! -e "$elf" ]]; then
  printf 'CI SPI flash error: test ELF not found: %s\n' "$elf" >&2
  exit 2
fi

python3 "$script_dir/spiflash.py" --outfile "$flash_image"

printf 'CI SPI flash: ELF=%s image=%s rounds=%s transfer_bytes=%s\n' \
  "$elf" "$flash_image" "$rounds" "$transfer_bytes"
timeout "$sim_timeout" "$simv" \
  +permissive \
  +dramsim \
  +dramsim_ini_dir="$dram_ini" \
  +max-cycles=0 \
  +notimingcheck \
  +spiflash0="$flash_image" \
  +permissive-off \
  "$elf" >"$log_file" 2>&1

expected="SPI flash stress passed: rounds=$rounds transfer_bytes=$transfer_bytes verified_bytes=$((rounds * (transfer_bytes + 2) - 1))"
if ! grep -Fqx "$expected" "$log_file"; then
  printf 'CI SPI flash error: expected pass marker not found: %s\n' "$expected" >&2
  exit 1
fi

printf 'CI SPI flash PASS\n'
