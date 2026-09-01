#!/usr/bin/env bash
set -euo pipefail

# Build and run the I2C EEPROM test against the TapeoutConfig VCS simulator.
# Run from a Nix shell that provides cmake, the RISC-V compiler, and VCS.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

simv="${SIMV:-$repo_root/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig}"
dram_ini="${DRAM_INI:-$repo_root/soc-generator/generator/testchipip/src/main/resources/dramsim2_ini}"
spiflash_image="${SPIFLASH_IMAGE:-}"
rounds="${I2C_STRESS_ROUNDS:-1}"
page_bytes="${I2C_STRESS_PAGE_BYTES:-1}"
timeout_polls="${I2C_TIMEOUT_POLLS:-1000000}"
sim_timeout="${I2C_CI_TIMEOUT:-300}"
build_test="${BUILD_TEST:-1}"
ci_log_dir="${CI_LOG_DIR:-${TMPDIR:-/tmp}/chipyard-ci-logs}"

for required in cmake python3 timeout stdbuf; do
  if ! command -v "$required" >/dev/null 2>&1; then
    printf 'CI I2C error: required command not found: %s\n' "$required" >&2
    exit 2
  fi
done

for required_path in "$simv" "$dram_ini"; do
  if [[ ! -e "$required_path" ]]; then
    printf 'CI I2C error: required path not found: %s\n' "$required_path" >&2
    exit 2
  fi
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/chipyard-i2c-ci.XXXXXX")"
build_dir="$work_dir/build"
flash_image="$work_dir/spiflash.img"
log_file="$work_dir/i2c-vcs.log"
elf=""

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  local saved_log_dir="${ci_log_dir}/i2c-ci-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$saved_log_dir" 2>/dev/null || true
  cp -f "$log_file" "$saved_log_dir/i2c-vcs.log" 2>/dev/null || true
  if [[ -n "$elf" && -e "$elf" ]]; then
    cp -f "$elf" "$saved_log_dir/$(basename "$elf")" 2>/dev/null || true
  fi
  if [[ -e "$flash_image" ]]; then
    cp -f "$flash_image" "$saved_log_dir/spiflash.img" 2>/dev/null || true
  fi
  printf 'CI I2C log: %s\n' "$saved_log_dir/i2c-vcs.log" >&2
  if [[ "$status" -eq 124 ]]; then
    printf 'CI I2C TIMEOUT after %ss; simulator did not complete.\n' "$sim_timeout" >&2
    tail -80 "$log_file" 2>/dev/null || true
  elif [[ "$status" -ne 0 ]]; then
    tail -80 "$log_file" 2>/dev/null || true
  else
    rm -rf "$work_dir"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [[ "$build_test" == 1 ]]; then
  cmake -S "$script_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-DI2C_STRESS_ROUNDS=$rounds -DI2C_STRESS_PAGE_BYTES=$page_bytes -DI2C_TIMEOUT_POLLS=$timeout_polls"
  cmake --build "$build_dir" --target tapeout_i2c_stress -j2
fi

elf="${ELF:-$build_dir/tapeout_i2c_stress.riscv}"
if [[ ! -e "$elf" ]]; then
  printf 'CI I2C error: test ELF not found: %s\n' "$elf" >&2
  exit 2
fi

# TapeoutConfig includes the SPI flash pad model even for I2C-only tests. The
# model requires a valid image plusarg at time zero, so provide an inert image
# for this test as well.
python3 "$script_dir/spiflash.py" --outfile "$flash_image"

printf 'CI I2C: ELF=%s rounds=%s page_bytes=%s\n' \
  "$elf" "$rounds" "$page_bytes"

sim_args=(
  +permissive
  +dramsim
  +dramsim_ini_dir="$dram_ini"
  +max-cycles=0
  +notimingcheck
  +spiflash0="$flash_image"
  +loadmem="$elf"
)
if [[ -n "$spiflash_image" ]]; then
  if [[ ! -e "$spiflash_image" ]]; then
    printf 'CI I2C error: SPI flash image not found: %s\n' "$spiflash_image" >&2
    exit 2
  fi
  sim_args+=(+spiflash0="$spiflash_image")
fi
sim_args+=(+permissive-off "$elf")

# Keep VCS in the caller's foreground process group. Without --foreground,
# timeout creates a separate group and VCS can be stopped by terminal control.
set +e
timeout --foreground "$sim_timeout" /usr/bin/stdbuf -oL -eL "$simv" "${sim_args[@]}" 2>&1 | tee "$log_file"
sim_status=${PIPESTATUS[0]}
set -e
if [[ "$sim_status" -ne 0 ]]; then
  exit "$sim_status"
fi

expected="I2C stress passed: rounds=$rounds verified_bytes=$((rounds * (page_bytes + 1)))"
if ! tr -d '\r' <"$log_file" | grep -Fqx "$expected"; then
  printf 'CI I2C error: expected pass marker not found: %s\n' "$expected" >&2
  exit 1
fi

printf 'CI I2C PASS rounds=%s page_bytes=%s\n' "$rounds" "$page_bytes"
