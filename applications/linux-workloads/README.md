# Linux Workloads

`applications/linux-workloads/firemarshal/` is a trimmed, repository-owned subset of
FireMarshal. It retains only the Buildroot workload builder, no-disk and disk
boot assembly, Spike launch support, and the FireSim installer. Linux,
OpenSBI, Buildroot, BusyBox, and FireSim block/network drivers are direct
submodules under this directory.

Initialize the workload dependencies after a clone:

```sh
./init-submodules.sh --linux
```

## P2E

The P2E harness has no Linux block device, so its default workload uses
no-disk mode. The Buildroot root filesystem is embedded into the boot ELF as an
initramfs and must be preloaded to DDR.

```sh
nix develop --command applications/scripts/build-linux-workload.sh
```

The P2E ELF is written to:

```text
applications/linux-workloads/build/tape-env/tape-env-linux-poweroff/
  tape-env-linux-poweroff-bin-nodisk
```

Build a custom P2E workload by copying `workloads/poweroff.json`; it should
inherit `p2e-br-base.json`. Use `--verify-spike` to run a completed no-disk
workload in Spike.

## HTIF Console

The P2E harness does not forward physical UART TX to the host. The separate
HTIF console workload routes Linux output through OpenSBI and HTIF:

```sh
nix develop --command applications/scripts/build-linux-workload.sh --htif-console
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

## FireSim

FireSim Linux workloads use disk mode: the boot ELF and ext2 root filesystem
are separate, and the initramfs loads `iceblk` before mounting the root image.
The retained FireSim installer does not support no-disk workloads.

```sh
nix develop --command applications/scripts/build-linux-workload.sh --firesim
```

This builds `workloads/firesim-poweroff.json`, installs a workload descriptor
to `soc-generator/sims/firesim/deploy/workloads/`, and leaves the boot ELF and
rootfs image under `applications/linux-workloads/build/tape-env/`. Custom FireSim
workloads should inherit `firesim-br-base.json` so the required block-device
drivers are included.

The no-disk path still uses `guestmount` to turn the ext2 rootfs into an
initramfs. Install `libguestfs` on the build host before running a no-disk
build. Build outputs are ignored by Git.
