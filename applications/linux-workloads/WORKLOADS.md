# Building Linux Workloads

This guide turns a workload into a Linux user-space program and packages it
for Tapeout/P2E. It applies to a C/C++ program, an existing bare-metal test,
or a directory containing several executables.

P2E has no Linux block device. The workload files are copied into a Buildroot
root filesystem, which is embedded in the boot ELF as an initramfs. A P2E
Linux workload is therefore not a bare-metal ELF placed inside Linux: the
program itself must be rebuilt for the RISC-V Linux ABI.

## Prerequisites

Initialize the Linux dependencies once after cloning:

```sh
./init-submodules.sh --linux
```

The no-disk image build uses `guestmount` from `libguestfs`. Build from the
FireMarshal development shell:

```sh
nix develop .#firemarshal
```

Buildroot 2024.05 has external-toolchain selectors through GCC 14. The
FireMarshal Nix wrapper uses the current GCC 15 compiler, but reports GCC 14.3
only to Buildroot and FireMarshal version probes; GCC 15 satisfies that feature
floor. Do not substitute a different compiler without upgrading Buildroot or
updating this compatibility boundary.

The workload builder refuses to run if `applications/linux-workloads/buildroot`
has local changes. It does not patch Buildroot: a disposable Git worktree holds
the unmodified source while generated files stay in ignored `output/` paths.
The Buildroot 1.34 `fakeroot` binary is replaced only in that ignored output
directory with the Nix-provided `fakeroot`; the small host `makedevs` utility
is rebuilt there against the same Nix closure. This creates the initramfs
without changing Buildroot source or Makefiles.

## Port The Program

Start with a normal Linux `main()` and compile it with the Linux cross
compiler. Static linking avoids needing target shared libraries beyond the
Buildroot root filesystem.

`build-linux-workload.sh` does not compile C/C++ sources. It copies the
already generated files named by `files` in the workload JSON into the guest
rootfs, then packages that rootfs into the boot ELF. The cross-compilation
command below turns a source program into a Linux workload; image packaging is
the later step.

```sh
riscv64-unknown-linux-gnu-gcc -static -O2 -std=gnu11 \
  -o payload/my-workload src/main.c
```

`payload/` in this example is a directory you create in the workload source
tree. It is an input to the JSON `files` mapping and is copied into the guest
rootfs; it is not a generated OpenSBI or P2E payload file. The final P2E
artifact is the `*-bin-nodisk` ELF written under the workload build directory.

For a Make-based project, use the equivalent settings:

```make
CC := riscv64-unknown-linux-gnu-gcc
CFLAGS += -O2
LDFLAGS += -static
```

An existing bare-metal workload commonly needs these changes before it can
run under Linux:

| Bare-metal dependency | Linux replacement |
| --- | --- |
| `crt.S`, `test.ld`, `-nostdlib`, `tohost` | Normal C runtime and `main()` return value |
| `syscalls.c` / semihosting output | libc `printf`, files, and POSIX syscalls |
| `setStats`, `mcycle`, `minstret` | `clock_gettime(CLOCK_MONOTONIC, ...)` or a Linux perf interface |
| M-mode CSRs, PMP, direct MMIO privilege assumptions | Remove, emulate, or move to a kernel driver; Linux user space cannot use them |
| Bare-metal hart startup/barriers | A single process, or `pthread`s when the Linux image has multiple CPUs |

Keep the original benchmark data headers and loop bounds unchanged when the
goal is functional equivalence. The Linux RISC-V benchmark port is a concrete
reference: `applications/linux-workloads/examples/riscv-benchmarks/build.sh`
copies the
upstream sources to a temporary directory and substitutes only its runtime
layer.

Check the generated ELF before making an image:

```sh
file payload/my-workload
qemu-riscv64 payload/my-workload
```

`qemu-riscv64` is an optional host-side smoke check. P2E remains the hardware
validation.

## Organize The Payload

Use a directory that is copied unchanged into the guest. A shell script is a
good way to run a group of binaries and emit machine-readable results.

```text
applications/my-workload/
  src/main.c
  payload/
    my-workload
    run.sh
```

For example, `payload/run.sh` can be:

```sh
#!/bin/sh
set -eu

cd "$(dirname "$0")"
./my-workload
printf 'MY_WORKLOAD_RESULT status=PASS\n'
```

Mark the script executable. A nonzero exit from the command makes the Linux
workload fail and is propagated to P2E through HTIF.

## Create A Workload Configuration

Create `applications/linux-workloads/workloads/my-workload.json`:

```json
{
  "name": "tape-env-linux-my-workload",
  "base": "htif-console.json",
  "workdir": "../..",
  "files": [
    ["my-workload/payload", "/opt/my-workload"]
  ],
  "command": "/opt/my-workload/run.sh"
}
```

`workdir` is relative to the JSON file. In this example `../..` resolves from
`applications/linux-workloads/workloads/` to `applications/`, so the payload
source is `applications/my-workload/payload`. Each `files` pair is
`[host_source, guest_destination]`; a directory source is copied recursively.
The `command` runs from the guest init script after Linux has booted.

Inherit `htif-console.json` for P2E. It supplies the Linux console route over
HTIF and the OpenSBI DTB convention. For a disk-backed FireSim workload,
inherit `firesim-poweroff.json` instead; see [README.md](README.md).

## Build The P2E Image

Run the builder with the custom config and HTIF support:

```sh
nix develop .#firemarshal --command \
  applications/scripts/build-linux-workload.sh \
  --config applications/linux-workloads/workloads/my-workload.json \
  --htif-console
```

The important outputs are:

```text
applications/linux-workloads/build/tape-env/tape-env-linux-my-workload/
  tape-env-linux-my-workload-bin-nodisk
  tape-env-linux-my-workload.img

applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/
  tape-env-linux-htif-console.dtb
```

The image is useful for inspecting guest files. The `*-bin-nodisk` ELF is the
P2E input. `--htif-console` generates the DTB used by all workloads inheriting
the HTIF console base.

## Run On P2E

Use an existing successful P2E bitstream case. This command does not build a
bitstream:

```sh
./dependencies/p2e-runner/bin/p2e run \
  --image "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-my-workload/tape-env-linux-my-workload-bin-nodisk" \
  --dtb "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb" \
  --dtb-address 0x8ff00000 \
  --detach
```

For a long workload, query and retrieve results without interrupting the FPGA:

```sh
./dependencies/p2e-runner/bin/p2e status
./dependencies/p2e-runner/bin/p2e fetch
```

The downloaded `p2e-run.log` contains the Linux boot log, workload stdout, the
HTIF exit status, and any result markers written by `run.sh`. A successful run
must show both the expected application result and `P2E HTIF completed with
exit code 0`.

## Complete Example: Build Your Own C Workload And Run It On P2E

This example assumes that the Linux user-space source entry point is
`applications/my-workload/src/main.c` and it has a normal `main()`. Run every
command from the repository root.

Initialize the Linux submodules once for a new checkout:

```sh
./init-submodules.sh --linux
```

Create the directory that will be copied to the guest, then cross-compile the
source into a static RISC-V Linux ELF. Add more sources, include directories,
and libraries to the same `gcc` command as required:

```sh
mkdir -p applications/my-workload/payload

nix develop .#firemarshal --command \
  riscv64-unknown-linux-gnu-gcc -static -O2 -std=gnu11 \
  -o applications/my-workload/payload/my-workload \
  applications/my-workload/src/main.c
```

Create `applications/my-workload/payload/run.sh` to set the guest working
directory, run the program, and emit a result marker:

```sh
#!/bin/sh
set -eu

cd "$(dirname "$0")"
./my-workload
printf 'MY_WORKLOAD_RESULT status=PASS\n'
```

Make the script executable:

```sh
chmod 0755 applications/my-workload/payload/run.sh
```

Then create `applications/linux-workloads/workloads/my-workload.json`:

```json
{
  "name": "tape-env-linux-my-workload",
  "base": "htif-console.json",
  "workdir": "../..",
  "files": [
    ["my-workload/payload", "/opt/my-workload"]
  ],
  "command": "/opt/my-workload/run.sh"
}
```

`workdir` resolves `my-workload/payload` to the host directory
`applications/my-workload/payload`. The `files` mapping copies the compiled
ELF and `run.sh`, not the C source. Package that JSON as a no-disk P2E image
and its DTB:

```sh
nix develop .#firemarshal --command \
  applications/scripts/build-linux-workload.sh \
  --config applications/linux-workloads/workloads/my-workload.json \
  --htif-console \
  --jobs 16
```

Finally, reuse an existing successful P2E bitstream case. Do not run `p2e
build`:

```sh
./dependencies/p2e-runner/bin/p2e run \
  --image "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-my-workload/tape-env-linux-my-workload-bin-nodisk" \
  --dtb "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb" \
  --dtb-address 0x8ff00000 \
  --detach

./dependencies/p2e-runner/bin/p2e status
./dependencies/p2e-runner/bin/p2e fetch
```

Confirm `MY_WORKLOAD_RESULT status=PASS` and `P2E HTIF completed with exit
code 0` in `p2e-run.log`. This is the complete normal-workload flow. The
benchmark example below only replaces its cross-compilation step with a
dedicated porting script.

## Complete Example: Linux RISC-V Benchmarks On P2E

The following complete flow runs from the repository root. It builds the Linux
ports of the RISC-V benchmarks used in CI, packages a no-disk P2E ELF, then
runs it on an existing successful P2E bitstream case. It does not run `p2e
build` and therefore does not rebuild a bitstream.

Initialize the Linux submodules once for a new checkout:

```sh
./init-submodules.sh --linux
```

First build the benchmarks. This creates eleven static RISC-V Linux binaries
and the suite runner:

```sh
nix develop .#firemarshal --command \
  applications/linux-workloads/examples/riscv-benchmarks/build.sh
```

The script writes to
`applications/linux-workloads/examples/riscv-benchmarks/build/` by default
and refuses to overwrite an existing directory. Skip this step when that
directory already contains the required version. To rebuild after a source
change, choose a new `--output` directory and update the `files` source path
in a new workload JSON to match it.

Build the P2E Linux image and HTIF DTB with 16 parallel jobs:

```sh
nix develop .#firemarshal --command \
  applications/scripts/build-linux-workload.sh \
  --config applications/linux-workloads/workloads/riscv-benchmarks.json \
  --htif-console \
  --jobs 16
```

Then reuse the latest successful P2E case to run the image. `--detach` returns
the terminal immediately, which is useful for Linux workloads:

```sh
./dependencies/p2e-runner/bin/p2e run \
  --image "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-riscv-benchmarks/tape-env-linux-riscv-benchmarks-bin-nodisk" \
  --dtb "$PWD/applications/linux-workloads/build/tape-env/tape-env-linux-htif-console/tape-env-linux-htif-console.dtb" \
  --dtb-address 0x8ff00000 \
  --detach

./dependencies/p2e-runner/bin/p2e status
./dependencies/p2e-runner/bin/p2e fetch
```

The final P2E input is
`applications/linux-workloads/build/tape-env/tape-env-linux-riscv-benchmarks/tape-env-linux-riscv-benchmarks-bin-nodisk`;
the `.img` is only for inspecting the root filesystem. The downloaded
`p2e-run.log` should show all eleven benchmarks completing, `pmp` intentionally
skipped because it requires M-mode PMP CSRs, and end with `P2E HTIF completed
with exit code 0`.

## Common Failures

| Symptom | Likely cause and action |
| --- | --- |
| `Illegal instruction` or CSR trap | The program still uses a privileged CSR or unsupported ISA extension. Remove it or use an appropriate kernel driver. |
| Program cannot execute | Rebuild with `riscv64-unknown-linux-gnu-gcc`; inspect it with `file` and prefer `-static`. |
| `guestmount` or `supermin` fails | Ensure `libguestfs` is installed. The builder places guestfs temporary files under `applications/linux-workloads/build/libguestfs/`, not the root filesystem. |
| P2E boots but no output arrives | Inherit `htif-console.json` and pass both `--dtb` and `--dtb-address 0x8ff00000`. |
| Root filesystem is too small | Increase `rootfs-size` in the workload JSON, then rebuild. |
| Buildroot submodule is reported dirty | Revert or commit the user changes first. Do not patch the submodule for a workload build. |
