# Chipyard Continuous Integration

The repository's validation CI is the `Regression Tests` workflow
(`.github/workflows/regression.yml`). It runs for pull requests targeting
`main` and can also be started manually.

The workflow builds Verilator emulators for:

- `QuadChannelRocketConfig`
- `MediumBoomV3CosimFastConfig`
- `MediumBoomV4CosimFastConfig`

It then runs the Rocket ISA, benchmark, native hello-world, and Zephyr
hello-world regressions, plus the BOOM v3 and v4 ISA and benchmark regressions.
The BOOM regression configurations omit TileLink monitors and, for Verilator,
disable Verilator assertion checking to keep software regressions practical;
the standard BOOM cosimulation configurations remain available for validation.
The Zephyr coverage is limited to the bare-metal
`samples/chipyard/hello_world` sample on `chipyard_riscv64`; it does not cover
other Zephyr samples, SMP, networking, or Linux. Builds execute on the
self-hosted `builder` runner and tests execute on the self-hosted `runner`.

The regression software is prebuilt outside the workflow and shared by both
runners at `/data2/ci-workloads`:

```
ci-workloads/
  hello.riscv
  riscv-tests/riscv64-unknown-elf/share/riscv-tests/
  zephyr/zephyr.elf
```

Create this directory with `nix develop --command
applications/scripts/build-ci-workloads.sh`. The publisher initializes the
pinned `applications/zephyr` submodule, uses its `west-riscv.yml` manifest to
fetch fixed Zephyr dependencies, and compiles with the Nix-provided Python,
West, and `riscv64-unknown-elf-` toolchain. CI deliberately validates only the
workload required by each testcase and never compiles workload software during
a regression. The generated Verilator emulator and its configuration-specific
`test-rules.d` remain artifacts of each CI run.

`Rocket Chip Logrotate` is maintenance automation for the regression artifacts;
it does not run validation tests. Release-note generation is release automation,
not CI validation.

`Weekly Synthesis` runs at 02:00 Asia/Shanghai every Monday (18:00 UTC on
Sunday), or manually through GitHub Actions. It generates
`TapeoutConfig` with the TSMC28 SRAM macro mapping and runs the pinned
`SEU-ACAL/Tapeout-Workbench` Design Compiler flow. The job must run on a
self-hosted runner labeled `builder`, with an available Design
Compiler license and the PDK mounts expected by the pinned flow. Design
Compiler runs in the `ci_env` container through `docker exec -i ci_env bash -lc`;
GitHub Actions has no TTY, so `-i` is used in place of `-it`. It does not upload
implementation files. Its job summary reports total cell area and the worst
setup slack for I2R, R2R, R2O, and I2O paths.
