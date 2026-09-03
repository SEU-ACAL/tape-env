# JTAG Test Workload

This directory contains the self-contained bare-metal workload and host-side
GDB/RSP tests used by the Chipyard VCS JTAG flow. It does not require the P2E
submodule.

Build the workload with the Nix toolchain:

```sh
nix shell .#chipyardRiscvTools --command \
  make -C applications/tests/jtag
```

The ELF is written to `build/gdb-loop.elf`. With VCS and OpenOCD already
running on the configured JTAG ports, use one of:

```sh
make -C applications/tests/jtag vcs-gdb-regress
make -C applications/tests/jtag vcs-gdb-stress
make -C applications/tests/jtag vcs-jtag-stress

# Orchestrate VCS, OpenOCD, and the RSP client in one non-interactive command.
make -C applications/tests/jtag ci-jtag-test
```

The default RSP regression is a fast DRAMSim-backed smoke profile that runs the
complete phase chain: reset/halt, register access, hardware and software
breakpoints, single-step, sampled ROM reads, and DDR write/read traffic. It
uses 4 steps, 8 memory rounds, a preloaded ELF, and sampled ROM verification.
Set `JTAG_FULL_STRESS=1` for the exhaustive 32-step/64-round/full-ROM/full-ELF
variant. `JTAG_STOP_AFTER` and `JTAG_SKIP_BREAKPOINTS=1` remain available for
targeted diagnosis.

Run the exhaustive transport variant explicitly when validating bulk SBA
traffic. It restores the previous 32 single steps, 64 DDR write/read rounds,
full SBA ELF transfer, and complete ROM-window reads:

```sh
JTAG_FULL_STRESS=1 make -C applications/tests/jtag ci-jtag-test
```

With a debug VCS binary, save the waveform by setting `FSDB_FILE`:

```sh
SIMV=soc-generator/sims/vcs/simv-chipyard.harness-TapeoutConfig-debug \
FSDB_FILE=/tmp/jtag.fsdb make -C applications/tests/jtag ci-jtag-test
```

The CI wrapper uses `STRESS_TIMEOUT` for an individual RSP request and
`CI_TIMEOUT` for the complete run; their defaults are 1000 and 1000 seconds.
Set `JTAG_COMMAND_TIMEOUT_SEC` to increase OpenOCD's system-bus command timeout
when SMIC180 ROM simulation makes the first SBA DDR access slow; it defaults to
twice `STRESS_TIMEOUT` (2000 seconds by default). For example:

```sh
STRESS_TIMEOUT=3000 JTAG_COMMAND_TIMEOUT_SEC=6000 \
  make -C applications/tests/jtag ci-jtag-test
```
