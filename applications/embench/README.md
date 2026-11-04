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

Compare FDIP against a coupled Mega BOOMv3 frontend. By default, the runner uses
`FDIPMegaBoomV3CosimPerfConfig` with Spike commit cosimulation and
`MegaBoomV3PerfConfig` without cosimulation. Both enable XSPerf and run with
`+xsperf`. The runner invokes an incremental build for each simulator before
running the benchmarks; `--skip-build` reuses existing executables without
checking for RTL changes:

```sh
nix develop --command applications/embench/run-parallel.sh --jobs 2
```

只运行单个 workload（例如 `minver`）：

```sh
nix develop --command applications/embench/run-parallel.sh \
  --benchmark minver --jobs 2
```

Configurations run in sequence: all selected FDIP benchmarks finish before the
coupled frontend group starts. `--jobs` controls the number of concurrent
benchmark processes within one configuration. Start with two jobs because every FDIP
cosim process is CPU and memory intensive; increase it only after checking host
utilization. The two designs run the same program image and use the same
`+max-cycles` limit.

The configuration classes can be overridden when comparing another FDIP and
coupled frontend pair:

```sh
nix develop --command applications/embench/run-parallel.sh \
  --fdip-config FDIPMegaBoomV3PerfConfig \
  --coupled-config MegaBoomV3PerfConfig
```

This example disables FDIP host cosimulation. The same overrides are available
through `EMBENCH_FDIP_CONFIG` and `EMBENCH_COUPLED_CONFIG`; command-line options
take precedence. Keep XSPerf enabled in both configurations.

The runner uses the same memory protocol as the make-based performance runs:
`+loadmem=<ELF>` with DRAMSim2 and the repository's `dramsim2_ini` directory.
To collect ChiselDB records, select the DB configuration and provide an output
path; the runner links the SQLite support when it builds that configuration:

```sh
nix develop --command applications/embench/run-parallel.sh \
  --fdip-config FDIPMegaBoomV3CosimPerfDBConfig \
  --chisel-db "$PWD/pico-xsperf.db" \
  --benchmark picojpeg --jobs 1
```

Each invocation creates a unique directory under
`applications/embench/results/<timestamp>-<suffix>` (or `--results DIRECTORY`).
`run-info.txt` records the selected configurations, benchmarks, job count, and
cycle limit. `summary.tsv` reports each arm's status, XSPerf `cycles`,
`commit_instr`, and IPC (`commit_instr / cycles`), followed by
`fdip_over_coupled_cycles` and `fdip_over_coupled_ipc`. A cycle ratio below one
or IPC ratio above one favors FDIP. The harness's "Completed after ... cycles"
value is saved separately as `sim_cycles` in each run's `status` file.

A run passes only when the simulator exits successfully, prints
`*** PASSED ***`, and supplies exactly one numeric, nonzero `cycles` and
`commit_instr` counter. Missing or ambiguous primary counters produce
`missing-xsperf`. Comparison ratios are left empty unless both arms pass;
the runner exits nonzero if any selected benchmark fails. Single-benchmark
runs summarize only that selected benchmark.

The runner prints a `[start]` line for every process and a `[done]` line when it
finishes. Each run directory contains `sim.log`, `xsperf.tsv`, and `status`;
the top-level `xsperf-summary.tsv` contains one row per dynamically registered
counter and benchmark/config pair. Counter names include the Verilog module
hierarchy, so counters with the same leaf name remain distinguishable. During a
long run, inspect the printed per-run `sim.log`
path, for example:

```sh
tail -f applications/embench/results/<timestamp>-<suffix>/FDIPMegaBoomV3CosimPerfConfig/aha-mont64/sim.log
```

The generated `BENCHMARKS` file lists 18 runnable programs. `cubic` is recorded
in `SKIPPED`: it needs quad-precision libgcc routines, while the Nix GCC's
prebuilt libgcc uses the `medlow` code model and cannot link into the HTIF
address range. The remaining benchmarks are small embedded workloads, so use
them for functional coverage and front-end comparisons, not as a replacement
for larger server or desktop benchmark suites.

### Branch MPKI breakdown

FDIP and coupled V3 performance builds register the same core counters under
`branch_mispredict_<kind>`, with five mutually exclusive kinds: `cond`, `call`,
`return`, `directuncond`, and `indirectuncond`. Calls include JAL/JALR with
architectural rd=x1/x5; returns are non-call JALR with rs1=x1/x5 and rd!=rs1.
PopAndPush belongs to call and is also reported by the overlapping diagnostic
subset `branch_mispredict_call_popandpush`. Direct/indirect unconditionals
exclude calls and returns. `branch_mispredict_other` checks classification
coverage and should be zero.

All five MPKI numerators use the existing core `b2.mispredict` event. Divide each
by `commit_instr` and multiply by 1000; the categories add to total branch MPKI.
V3 handles JAL in its frontend, so backend direct-JAL errors are absent from
this metric. F1/F2/F3 corrections and frontend-discovered JAL errors are separate
events and must not be added to backend MPKI.

Each category also has `direction_taken`, `direction_not_taken`, and
`target_or_position` counters. These compare the selected backend event's
resolved `taken` with `uop.taken`; equal direction does not distinguish a
wrong target, wrong CFI position or missing prediction. They are not predictor
component attribution. The five `branch_commit_<kind>` counters use
`rob.io.commit.arch_valids` to report actual committed CFI populations, distinct
from speculative `branch_resolved` events.

Rebuild both performance configurations to collect the new counters. Then
validate a new result directory and export per-workload TSVs:

```sh
python3 applications/embench/summarize-mpki.py \
  applications/embench/results/<timestamp>-<suffix>
```

The script checks class/cause partitions, their cross-product, architectural
commit totals and the legacy JALR count. It writes `mpki.tsv`, `mpki-causes.tsv`,
`mpki-call-subsets.tsv`, and `validation.json` into a new `mpki-analysis`
directory. Old results missing the counters are rejected; no missing category
is silently reported as zero. Existing logs and counters are read only.
