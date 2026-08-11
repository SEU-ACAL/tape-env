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

The lightweight RSP stress test accepts `STRESS_STEPS` and `STRESS_MEMORY`;
the default values are intentionally bounded for the slow Remote Bitbang
transport. The CI wrapper uses `STRESS_TIMEOUT` for an individual RSP request
and `CI_TIMEOUT` for the complete run; their defaults are 120 and 1800 seconds.
