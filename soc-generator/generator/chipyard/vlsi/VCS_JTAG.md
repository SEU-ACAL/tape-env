# TapeoutConfig VCS JTAG Smoke Test

[中文版本](VCS_JTAG_CN.md)

This procedure verifies the JTAG debug path of the VCS `TapeoutConfig`
simulator built with SMIC180 hard SRAM replacement. It checks the complete
host-to-DUT path, not SRAM timing:

```text
VCS simulator -> SimJTAG remote bitbang -> OpenOCD -> GDB
```

The smoke halts the hart, reads the program counter, writes and reads `a0`,
then writes and reads a DRAM word using the Debug Module system bus access
(SBA). It does not prove resume/halt, single-step, or hardware breakpoints.

## Prerequisites

- Initialize the P2E submodule because it provides the `gdb-loop` workload:

  ```sh
  ./init-submodules.sh --p2e
  ```

- Start the normal development shell for VCS build and simulation:

  ```sh
  nix develop
  ```

  The shell configures the VCS ABI (`VCS_ARCH_OVERRIDE=linux` and
  `EXTRA_SIM_LDFLAGS=-no-pie`). Keep the shell's default `RISCV` toolchain;
  do not override it with a standalone newer Spike package. A tool linked
  against a newer `libstdc++` can be incompatible with VCS's GCC 11 link
  environment.

- The SMIC180 SRAM delivery must be available at the default path in
  `chipyard.mk`, or the `SMIC180_SRAM_ROOT` variable must point to the local
  delivery.

## Build The Workload And Simulator

From the repository root in the normal development shell:

```sh
make -C dependencies/p2e-runner/examples/gdb-loop

make -C soc-generator \
  SIM=vcs \
  CONFIG=TapeoutConfig \
  USE_SMIC180_SRAM=1 \
  emu
```

`USE_SMIC180_SRAM=1` selects `smic180_sram_library.mdf.json` in strict mode
and adds the SMIC SRAM Verilog models to the VCS file list. The generated
simulator is:

```text
soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig
```

When changing `remote_bitbang.cc`, force a simulator rebuild before testing:

```sh
make -C soc-generator \
  SIM=vcs \
  CONFIG=TapeoutConfig \
  USE_SMIC180_SRAM=1 \
  clean-sim
make -C soc-generator \
  SIM=vcs \
  CONFIG=TapeoutConfig \
  USE_SMIC180_SRAM=1 \
  emu
```

## Start VCS

Keep the normal development shell open and run the following from the
repository root. `+jtag_rbb_enable=1` enables `SimJTAG`; the simulator prints
the dynamically allocated Remote Bitbang port to stderr and waits for a
connection.

```sh
simv=$PWD/soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig
elf=$PWD/dependencies/p2e-runner/examples/gdb-loop/build/gdb-loop.elf
dram_ini=$PWD/soc-generator/generator/testchipip/src/main/resources/dramsim2_ini

"$simv" \
  +permissive \
  +dramsim \
  +dramsim_ini_dir="$dram_ini" \
  +max-cycles=0 \
  +notimingcheck \
  +jtag_rbb_enable=1 \
  +permissive-off \
  "$elf" \
  2>sim-jtag.stderr | tee sim-jtag.stdout
```

The port is transient and must not be hard-coded. The OpenOCD GDB port below
is deliberately `3335`, leaving a user's existing server on `3333` untouched.

## Start OpenOCD

In the second terminal, enter the lightweight debug shell and start OpenOCD.
Run the commands from the repository root so the ELF path used in the next
section is unchanged.

```sh
nix develop .#jtag-debug

rbb_port=$(sed -n 's/.*Listening on port \([0-9][0-9]*\).*/\1/p' sim-jtag.stderr | tail -n 1)
[ -n "$rbb_port" ] || { echo 'Remote Bitbang port is not ready'; exit 1; }

export REMOTE_BITBANG_HOST=127.0.0.1
export REMOTE_BITBANG_PORT="$rbb_port"

openocd \
  -c 'adapter driver remote_bitbang' \
  -c 'remote_bitbang host $::env(REMOTE_BITBANG_HOST)' \
  -c 'remote_bitbang port $::env(REMOTE_BITBANG_PORT)' \
  -c 'transport select jtag' \
  -c 'bindto 127.0.0.1' \
  -c 'gdb_port 3335' \
  -c 'telnet_port disabled' \
  -c 'tcl_port disabled' \
  -c 'set _CHIPNAME riscv' \
  -c 'jtag newtap $_CHIPNAME cpu -irlen 5' \
  -c 'set _TARGETNAME $_CHIPNAME.cpu' \
  -c 'target create $_TARGETNAME riscv -chain-position $_TARGETNAME' \
  -c 'reset_config none' \
  -c 'riscv set_reset_timeout_sec 30' \
  -c 'riscv set_command_timeout_sec 30' \
  -c 'init'
```

Successful initialization includes these lines:

```text
JTAG tap: riscv.cpu tap/device found: 0x00000001
datacount=8 progbufsize=16
Examined RISC-V core; found 1 harts
hart 0: XLEN=64
Listening on port 3335 for gdb connections
```

`0x00000001` is the expected simulation TAP ID. It is not a production
manufacturer ID.

## Run The GDB Smoke

In a third terminal, or after OpenOCD has been started in the background, use
the same debug shell. The commands below are intentionally directed and leave
the target halted.

```sh
elf=$PWD/dependencies/p2e-runner/examples/gdb-loop/build/gdb-loop.elf

riscv64-unknown-elf-gdb -batch \
  -ex 'set pagination off' \
  -ex 'set confirm off' \
  -ex 'set remotetimeout 30' \
  -ex "file $elf" \
  -ex 'target extended-remote :3335' \
  -ex 'monitor halt' \
  -ex 'printf "JTAG_PC="' \
  -ex 'print/x $pc' \
  -ex 'set $a0 = 0x1234abcd' \
  -ex 'printf "JTAG_A0="' \
  -ex 'print/x $a0' \
  -ex 'set {unsigned int}0x80100000 = 0x4a544147' \
  -ex 'printf "JTAG_MEM="' \
  -ex 'x/wx 0x80100000' \
  -ex 'disconnect' \
  -ex 'quit'
```

Expected evidence is similar to:

```text
JTAG_PC=$1 = 0x80000042
JTAG_A0=$2 = 0x1234abcd
JTAG_MEM=0x80100000:  0x4a544147
```

The PC may differ because `gdb-loop` is running when the halt request arrives.
The `a0` and memory values must match exactly.

## Pass Criteria And Cleanup

The smoke passes only when all of the following are true:

1. OpenOCD reports the TAP ID, DTM parameters, and one RV64 hart.
2. `monitor halt` succeeds and GDB can read `$pc`.
3. `$a0` reads back as `0x1234abcd` after the write.
4. `0x80100000` reads back as `0x4a544147` after the SBA write.

Exit GDB with `disconnect` and `quit`, stop OpenOCD with `Ctrl-C`, then stop
VCS with `Ctrl-C`. OpenOCD may report a Remote Bitbang socket reset during
shutdown; this is expected if the simulator is terminated after the smoke has
already passed.

## Current Limitations

- `resume` followed by a second `halt` has not yet been established as a
  stable VCS test case.
- Hardware breakpoint and `stepi` are not part of this smoke. The Debug Module
  exposes one trigger, and OpenOCD may report duplicate breakpoint addresses.
- `+notimingcheck` is suitable for functional hard-SRAM replacement testing;
  it is not an SRAM timing-signoff flow.
