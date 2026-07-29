# Linux RISC-V Benchmark Example

This is a complete Linux workload example. It ports the benchmark subset used
by CI without modifying `applications/riscv-tests`: the upstream sources are
copied to a temporary directory and only their bare-metal runtime is replaced.

Build the guest payload from the repository root:

```sh
nix develop .#firemarshal --command \
  applications/linux-workloads/examples/riscv-benchmarks/build.sh
```

The command writes eleven static RISC-V Linux executables and a suite runner to
`build/`. `applications/linux-workloads/workloads/riscv-benchmarks.json` copies
that directory to `/opt/riscv-benchmarks` and is the FireMarshal configuration
used to package and run the example on P2E.

The `pmp` benchmark is deliberately recorded as skipped because it requires
machine-mode PMP CSR access, which is not available to a Linux user process.
