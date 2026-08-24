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

The RSP stress test covers abstract register read/write, hardware and software
breakpoints, single-step execution, complete reads of the Tapeout BootROM and
Debug ROM windows, and DDR write/read traffic. It accepts `STRESS_STEPS` and
`STRESS_MEMORY`; the default values are intentionally bounded for the slow
Remote Bitbang transport. ROM ranges can be overridden with `BOOTROM_BASE`,
`BOOTROM_SIZE`, `DEBUGROM_BASE`, `DEBUGROM_SIZE`, and `ROM_READ_CHUNK`.

The CI wrapper uses `STRESS_TIMEOUT` for an individual RSP request and
`CI_TIMEOUT` for the complete run; their defaults are 1000 and 1000 seconds.
Set `JTAG_COMMAND_TIMEOUT_SEC` to increase OpenOCD's system-bus command timeout
when SMIC180 ROM simulation makes the first SBA DDR access slow; it defaults to
500 seconds. For example:

```sh
JTAG_COMMAND_TIMEOUT_SEC=500 make -C applications/tests/jtag ci-jtag-test
```
