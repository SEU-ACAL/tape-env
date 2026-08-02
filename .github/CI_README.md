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
applications/scripts/build-ci-workloads.sh`. This includes `dhrystone.riscv`
and `fpu-stress.riscv`; the latter runs sustained scalar FP64 fused
multiply-add operations for FPU-sensitive power measurement. The publisher
initializes the pinned `applications/zephyr` submodule, uses its `west-riscv.yml` manifest to
fetch fixed Zephyr dependencies, and compiles with the Nix-provided Python,
West, and `riscv64-unknown-elf-` toolchain. CI deliberately validates only the
workload required by each testcase and never compiles workload software during
a regression. The generated Verilator emulator and its configuration-specific
`test-rules.d` remain artifacts of each CI run.

The regression summary also includes a `TapeoutConfig` address map generated
from the VCS elaboration output. The `tapeoutconfig-regmap` artifact contains
the complete Markdown register-field map, normalized JSON, DTS, memmap, and
the raw generated regmap JSON files.

`Rocket Chip Logrotate` is maintenance automation for the regression artifacts;
it does not run validation tests. Release-note generation is release automation,
not CI validation.

`Weekly Synthesis` runs at 02:00 Asia/Shanghai every Monday (18:00 UTC on
Sunday), or manually through GitHub Actions. It generates
`TapeoutConfig` with the selected SMIC180 (default) or TSMC28 SRAM macro mapping and runs the current
`SEU-ACAL/Tapeout-Workbench` Design Compiler flow. The job must run on a
self-hosted runner labeled `builder`, with available Design Compiler, VCS,
PrimeTime, and Verdi licenses and the PDK mounts expected by the flow. Design
Compiler and PrimeTime run in the `ci_env` container through `docker exec -i
ci_env bash -lc`; GitHub Actions has no TTY, so `-i` is used in place of `-it`.
Manual runs select `smic180` or `tsmc28`; scheduled runs use `smic180`.
The SMIC180 default clock period is 2.0 ns (500 MHz), while TSMC28 defaults to
1.0 ns (1 GHz). A manual `Weekly Synthesis` run provides an optional `Clock
period in ns` field; leave it blank to use the selected technology's default.
It can also be overridden through `CLOCK_PERIOD` in nanoseconds.

The job has separate `Generate RTL and run Design Compiler` and `Run PrimeTime
power analysis` steps. A manually dispatched run offers `dhrystone` (default)
and `fpu-stress` workload choices, plus an `SDF timing annotation` checkbox
that defaults to enabled. In SDF mode the DC-generated `ChipTop.sdf` is
annotated into GLS and PrimeTime reads `run-sdf.fsdb`; disabling the checkbox
preserves the zero-delay GLS `run-zero.fsdb` flow. The latter runs a compact
scalar FP64 FMA smoke workload. Both modes default to the 673046 ns to 4470574
ns steady-state FSDB window. PrimeTime reports averaged power in watts. The
workload, timing mode, activity window, and technology paths can be overridden
with `POWER_BENCHMARK`, `POWER_WORKLOAD`, `POWER_USE_SDF`, `POWER_START_NS`,
`POWER_END_NS`,
`STD_CELL_MODEL`, `STD_CELL_DB`, `SRAM_ROOT`, and `SRAM_CORNER`. For SMIC180,
the standard-cell and SRAM libraries use the same SS, 125C process and voltage
corner. The power
step requires PrimeTime W-2024 and defaults to W-2024.09-SP1. The power result
is a workload-based pre-layout estimate, not a
signoff result. The job does not upload implementation files. Its job summary
reports total cell area, the worst setup slack for I2R, R2R, R2O, and I2O paths,
the synthesized hard-SRAM instance count by macro type and MDF port family (for
example, `1rw` for one read/write port), and PrimeTime internal,
switching, leakage, and total power.
