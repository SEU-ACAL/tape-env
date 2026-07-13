# Applications

## RISC-V core regression tests

The ISA and benchmark binaries used by the Rocket and BOOM Verilator
regressions are built from the pinned `applications/riscv-tests` submodule.
Build them from the Chipyard development shell:

```bash
nix develop --command applications/scripts/build-riscv-tests.sh
```

This produces the test-root layout expected by the Verilator Makefiles at
`applications/riscv-tests/build/install`. To write it elsewhere, for example
before running a simulator manually, pass `--output` and use that directory as
`RISCV`:

```bash
nix develop --command applications/scripts/build-riscv-tests.sh --output /tmp/riscv-tests
make -C soc-generator/sims/verilator CONFIG=QuadChannelRocketConfig \
  RISCV=/tmp/riscv-tests run-asm-tests-fast
```

The submodule is pinned to the official `riscv-software-src/riscv-tests`
source. The build script applies the legacy-toolchain compatibility changes to
an ephemeral copy and does not patch or otherwise alter the pinned source
files.
