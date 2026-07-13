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

`Rocket Chip Logrotate` is maintenance automation for the regression artifacts;
it does not run validation tests. Release-note generation is release automation,
not CI validation.
