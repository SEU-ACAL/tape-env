# Chipyard Continuous Integration

The repository's validation CI is the `Rocket and BOOM Regression` workflow
(`.github/workflows/rocketchip-hello.yml`). It runs for pull requests targeting
`main` and can also be started manually.

The workflow builds Verilator emulators for:

- `QuadChannelRocketConfig`
- `MediumBoomV3CosimConfig`
- `MediumBoomV4CosimConfig`

It then runs the Rocket ISA, benchmark, and hello-world regressions, plus the
BOOM v3 and v4 ISA and benchmark regressions. Builds execute on the
self-hosted `builder` runner and tests execute on the self-hosted `runner`.

The regression software is prebuilt outside the workflow and shared by both
runners at `/data2/ci-workloads`:

```
ci-workloads/
  hello.riscv
  riscv-tests/riscv64-unknown-elf/share/riscv-tests/
```

Create this directory with `nix develop --command
applications/scripts/build-ci-workloads.sh`. CI deliberately fails if either
artifact is missing; it never compiles workload software during a regression.
The generated Verilator emulator and its configuration-specific `test-rules.d`
remain artifacts of each CI run.

`Rocket Chip Logrotate` is maintenance automation for the regression artifacts;
it does not run validation tests. Release-note generation is release automation,
not CI validation.
