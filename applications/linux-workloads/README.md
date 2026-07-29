# Linux Workloads

`applications/linux-workloads/firemarshal/` is a trimmed, repository-owned subset of
FireMarshal. It retains the Buildroot workload builder, no-disk boot assembly,
and Spike launch support. Buildroot is the only direct submodule; it downloads
and pins Linux, OpenSBI, and BusyBox from the workload defconfig.

Initialize Buildroot after a clone:

```sh
./init-submodules.sh --linux
```

## P2E

The P2E harness has no Linux block device, so its default workload uses
no-disk mode. The Buildroot root filesystem is embedded into the boot ELF as an
initramfs and must be preloaded to DDR.

Use the FireMarshal-only development shell for Linux workloads. It omits the
simulator and RTL toolchain closure used by the default shell.

```sh
nix develop .#firemarshal --command applications/scripts/build-linux-workload.sh
```

The P2E ELF is written to:

```text
applications/linux-workloads/build/tape-env/tape-env-linux-poweroff/
  tape-env-linux-poweroff-bin-nodisk
```

Build a custom P2E workload by following
[WORKLOADS.zh-CN.md](WORKLOADS.zh-CN.md) (中文) or [WORKLOADS.md](WORKLOADS.md)
(English). They cover porting a bare-metal program to Linux user space,
packaging files into the root filesystem, and running the resulting ELF
through P2E. Use `--verify-spike` to run a completed non-HTIF no-disk workload
in Spike.

## HTIF Console

The P2E harness does not forward physical UART TX to the host. The separate
HTIF console workload routes Linux output through OpenSBI and HTIF:

```sh
nix develop .#firemarshal --command applications/scripts/build-linux-workload.sh --htif-console
```

This additionally generates a DTB. Run it with both DDR-preloaded inputs:

```sh
cd dependencies/p2e-runner
p2e run \
  --image ../../applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console-bin-nodisk \
  --dtb ../../applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb \
  --dtb-address 0x8ff00000
```

Do not combine `--htif-console` and `--verify-spike`: the P2E OpenSBI payload
expects its DTB at `0x8ff00000`, while Spike uses its own ROM convention.

The no-disk path still uses `guestmount` to turn the ext2 rootfs into an
initramfs. Install `libguestfs` on the build host before running a no-disk
build. Build outputs are ignored by Git.
