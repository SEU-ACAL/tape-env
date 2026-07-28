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

## Linux workloads

`applications/linux-workloads/firemarshal` contains a trimmed, repository-owned
FireMarshal script layer for generating Buildroot Linux workloads. Linux,
OpenSBI, Buildroot, and BusyBox are pinned as direct submodules. The default
workload embeds the root filesystem in an initramfs, which is required by the
current Tapeout/P2E platform because it has no block device path.

Initialize Linux workload dependencies once after cloning:

```bash
./init-submodules.sh --linux
```

Build the default Linux smoke workload from the development shell:

```bash
nix develop .#firemarshal --command applications/scripts/build-linux-workload.sh
```

The resulting initramfs ELF, suitable as the P2E workload input, is:

```text
applications/linux-workloads/build/tape-env/tape-env-linux-poweroff/tape-env-linux-poweroff-bin-nodisk
```

Pass `--config PATH` to build another workload and `--output DIR` to place
artifacts elsewhere. See
[linux-workloads/WORKLOADS.zh-CN.md](linux-workloads/WORKLOADS.zh-CN.md) (中文)
or [linux-workloads/README.md](linux-workloads/README.md) (English) for workload
layout and P2E invocation.
