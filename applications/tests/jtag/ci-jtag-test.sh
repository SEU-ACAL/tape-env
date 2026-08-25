#!/usr/bin/env bash
set -euo pipefail

# Run the complete VCS -> Remote Bitbang -> OpenOCD -> RSP path without any
# interactive terminals. Invoke this script from the repository's JTAG Nix
# shell so vcs, openocd, and the RISC-V Python client are available.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../../.." && pwd)"

simv="${SIMV:-$repo_root/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig}"
elf="${ELF:-$script_dir/build/gdb-loop.elf}"
dram_ini="${DRAM_INI:-$repo_root/soc-generator/generator/testchipip/src/main/resources/dramsim2_ini}"
openocd_bin="${OPENOCD:-openocd}"
python_bin="${PYTHON:-python3}"
rbb_host="${RBB_HOST:-127.0.0.1}"
gdb_host="${GDB_HOST:-127.0.0.1}"
gdb_port="${GDB_PORT:-3335}"
stress_steps="${STRESS_STEPS:-32}"
stress_memory="${STRESS_MEMORY:-64}"
stress_timeout="${STRESS_TIMEOUT:-1000}"
ci_timeout="${CI_TIMEOUT:-1000}"
startup_timeout="${STARTUP_TIMEOUT:-30}"
command_timeout="${JTAG_COMMAND_TIMEOUT_SEC:-$((stress_timeout * 2))}"
bootrom_base="${BOOTROM_BASE:-0x10000}"
bootrom_size="${BOOTROM_SIZE:-0x2000}"
debugrom_base="${DEBUGROM_BASE:-0x800}"
debugrom_size="${DEBUGROM_SIZE:-0x80}"
rom_read_chunk="${ROM_READ_CHUNK:-0x40}"
build_elf="${BUILD_ELF:-1}"

for required in "$openocd_bin" "$python_bin"; do
  if ! command -v "$required" >/dev/null 2>&1; then
    printf 'CI JTAG error: required command not found: %s\n' "$required" >&2
    exit 2
  fi
done

if [[ "$build_elf" == 1 ]]; then
  make -C "$script_dir" all
fi

for required_file in "$simv" "$elf" "$dram_ini"; do
  if [[ ! -e "$required_file" ]]; then
    printf 'CI JTAG error: required path not found: %s\n' "$required_file" >&2
    exit 2
  fi
done

log_dir="$(mktemp -d "${TMPDIR:-/tmp}/chipyard-jtag-ci.XXXXXX")"
flash_image="$log_dir/spiflash.img"
sim_stdout="$log_dir/sim.stdout"
sim_stderr="$log_dir/sim.stderr"
openocd_log="$log_dir/openocd.log"
sim_pid=''
openocd_pid=''

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$openocd_pid" ]] && kill -0 "$openocd_pid" 2>/dev/null; then
    kill "$openocd_pid" 2>/dev/null || true
    wait "$openocd_pid" 2>/dev/null || true
  fi
  if [[ -n "$sim_pid" ]] && kill -0 "$sim_pid" 2>/dev/null; then
    kill "$sim_pid" 2>/dev/null || true
    wait "$sim_pid" 2>/dev/null || true
  fi
  if [[ "$status" -ne 0 ]]; then
    printf 'CI JTAG logs: %s\n' "$log_dir" >&2
    printf '%s\n' '--- OpenOCD log (tail) ---' >&2
    tail -40 "$openocd_log" 2>/dev/null || true
    printf '%s\n' '--- VCS stderr (tail) ---' >&2
    tail -40 "$sim_stderr" 2>/dev/null || true
  else
    rm -rf "$log_dir"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

# TapeoutConfig includes the SPI flash pad model for every peripheral test.
# Mount an inert image so the model does not terminate the JTAG-only run at
# time zero.
"$python_bin" "$repo_root/applications/tests/spiflash.py" --outfile "$flash_image"

printf 'CI JTAG: ELF=%s steps=%s memory=%s\n' \
  "$elf" "$stress_steps" "$stress_memory"

"$simv" \
  +permissive \
  +dramsim \
  +dramsim_ini_dir="$dram_ini" \
  +max-cycles=0 \
  +notimingcheck \
  +spiflash0="$flash_image" \
  +loadmem="$elf" \
  +jtag_rbb_enable=1 \
  +permissive-off \
  "$elf" >"$sim_stdout" 2>"$sim_stderr" &
sim_pid=$!

rbb_port=''
for ((attempt = 0; attempt < startup_timeout; ++attempt)); do
  rbb_port="$(sed -n 's/.*Listening on port \([0-9][0-9]*\).*/\1/p' "$sim_stderr" | tail -n 1)"
  [[ -n "$rbb_port" ]] && break
  if ! kill -0 "$sim_pid" 2>/dev/null; then
    printf 'CI JTAG error: VCS exited before opening Remote Bitbang\n' >&2
    exit 1
  fi
  sleep 1
done
if [[ -z "$rbb_port" ]]; then
  printf 'CI JTAG error: timed out waiting for Remote Bitbang port\n' >&2
  exit 1
fi

"$openocd_bin" \
  -c 'adapter driver remote_bitbang' \
  -c "remote_bitbang host $rbb_host" \
  -c "remote_bitbang port $rbb_port" \
  -c 'transport select jtag' \
  -c "bindto $gdb_host" \
  -c "gdb_port $gdb_port" \
  -c 'telnet_port disabled' \
  -c 'tcl_port disabled' \
  -c 'jtag newtap riscv cpu -irlen 5' \
  -c 'target create riscv.cpu riscv -chain-position riscv.cpu' \
  -c 'reset_config none' \
  -c 'riscv set_reset_timeout_sec 30' \
  -c "riscv set_command_timeout_sec $command_timeout" \
  -c init >"$openocd_log" 2>&1 &
openocd_pid=$!

for ((attempt = 0; attempt < startup_timeout; ++attempt)); do
  if "$python_bin" - "$gdb_host" "$gdb_port" 2>/dev/null <<'PY'
import socket
import sys

with socket.socket() as sock:
    sock.settimeout(1)
    sock.connect((sys.argv[1], int(sys.argv[2])))
PY
  then
    break
  fi
  if ! kill -0 "$openocd_pid" 2>/dev/null; then
    printf 'CI JTAG error: OpenOCD exited before opening GDB port\n' >&2
    exit 1
  fi
  sleep 1
done

if ! "$python_bin" - "$gdb_host" "$gdb_port" 2>/dev/null <<'PY'
import socket
import sys

with socket.socket() as sock:
    sock.settimeout(1)
    sock.connect((sys.argv[1], int(sys.argv[2])))
PY
then
  printf 'CI JTAG error: timed out waiting for OpenOCD GDB port\n' >&2
  exit 1
fi

timeout "$ci_timeout" "$python_bin" "$script_dir/jtag-rsp-stress.py" \
  --elf "$elf" \
  --host "$gdb_host" \
  --port "$gdb_port" \
  --steps "$stress_steps" \
  --memory "$stress_memory" \
  --bootrom-base "$bootrom_base" \
  --bootrom-size "$bootrom_size" \
  --debugrom-base "$debugrom_base" \
  --debugrom-size "$debugrom_size" \
  --rom-read-chunk "$rom_read_chunk" \
  --timeout "$stress_timeout"

printf 'CI JTAG PASS steps=%s memory=%s\n' "$stress_steps" "$stress_memory"
