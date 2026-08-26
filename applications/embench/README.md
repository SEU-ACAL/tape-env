# Embench-IoT

This directory carries the same Embench-IoT revision and bare-metal build
configuration used by upstream Chipyard. The resulting RV64 ELF files use the
HTIF nano runtime and can be loaded directly by Chipyard simulators.

Build the suite from the repository root:

```sh
nix develop --command applications/embench/build.sh
```

Run an individual program on the FDIP Verilator configuration with Spike
commit cosimulation:

```sh
make -C soc-generator/sims/verilator \
  CONFIG=FDIPMegaBoomV3CosimConfig \
  BINARY=$PWD/applications/embench/build/bin/aha-mont64 \
  run-binary-fast
```

Compare FDIP against a Mega BOOMv3 baseline in parallel. FDIP runs with Spike
commit cosimulation; the BOOMv3 baseline runs without cosimulation. Both runs
use the performance configurations and pass `+xsperf`. The runner builds either
missing simulator and writes a cycle summary plus a normalized XSPerf TSV:

```sh
nix develop --command applications/embench/run-parallel.sh --jobs 2
```

只运行单个 workload（例如 `edn`）：

```sh
nix develop --command applications/embench/run-parallel.sh \
  --benchmark edn --jobs 2
```

`--jobs` is process-level parallelism. Start with two jobs because every FDIP
cosim process is CPU and memory intensive; increase it only after checking host
utilization. The two designs run the same program image and use the same
`+max-cycles` limit, so their cycle counts are directly comparable. A ratio
below one means FDIP used fewer RTL cycles.

The runner prints a `[start]` line for every process and a `[done]` line when it
finishes. Each run directory contains `sim.log`, `xsperf.tsv`, and `status`;
the top-level `xsperf-summary.tsv` contains one row per dynamically registered
counter and benchmark/config pair. Counter names include the Verilog module
hierarchy, so counters with the same leaf name remain distinguishable. During a long run, inspect the printed per-run `sim.log`
path, for example:

```sh
tail -f applications/embench/results/<timestamp>/FDIPMegaBoomV3CosimPerfConfig/aha-mont64/sim.log
```

The generated `BENCHMARKS` file lists 18 runnable programs. `cubic` is recorded
in `SKIPPED`: it needs quad-precision libgcc routines, while the Nix GCC's
prebuilt libgcc uses the `medlow` code model and cannot link into the HTIF
address range. The remaining benchmarks are small embedded workloads, so use
them for functional coverage and front-end comparisons, not as a replacement
for larger server or desktop benchmark suites.
