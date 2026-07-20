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

`applications/firemarshal` is a pinned FireMarshal submodule for generating
Buildroot Linux workloads. The default workload uses the Chipyard board
configuration and embeds the root filesystem in an initramfs. This is required
by the current Tapeout/P2E platform, which has no FireMarshal block-device
path.

Initialize FireMarshal once after cloning:

```bash
./init-submodules.sh --firemarshal
```

Build the default Linux smoke workload from the development shell:

```bash
nix develop --command applications/scripts/build-linux-workload.sh
```

The resulting initramfs ELF, suitable as the P2E workload input, is:

```text
applications/linux/build/chipyard/tape-env-linux-poweroff/tape-env-linux-poweroff-bin-nodisk
```

Pass `--config PATH` to build another FireMarshal workload and `--output DIR`
to place artifacts elsewhere. `--disk` produces the conventional boot ELF plus
an ext2 image for a platform with a block device; it is not runnable on the
current P2E harness. See [linux/README.md](linux/README.md) for workload layout
and P2E invocation.
