#!/usr/bin/env python3
"""Validate the shared backend CFI counters and export per-workload MPKI."""

import argparse
import csv
import json
from pathlib import Path


KINDS = ("cond", "call", "return", "directuncond", "indirectuncond")
CAUSES = ("direction_taken", "direction_not_taken", "target_or_position")


def read_pairs(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)


def read_counters(path):
    counters = {}
    for name, raw_value in csv.reader(path.open(), delimiter="\t"):
        leaf = name.rsplit(".", 1)[-1]
        if leaf in ("cycles", "commit_instr", "control_flow_target_mispredict") or leaf.startswith(
            ("branch_mispredict", "branch_commit_")
        ):
            if leaf in counters:
                raise ValueError(f"{path}: ambiguous counter {leaf}")
            counters[leaf] = int(raw_value)
    return counters


def validate(counters, path):
    parts = KINDS + ("other",)
    required = {"cycles", "commit_instr", "branch_mispredict", "branch_commit_total",
                "control_flow_target_mispredict"}
    required.update(f"branch_commit_{kind}" for kind in KINDS)
    required.update(f"branch_mispredict_{part}" for part in parts + CAUSES)
    required.update(f"branch_mispredict_{kind}_{cause}" for kind in parts for cause in CAUSES)
    required.update(f"branch_mispredict_call_{part}" for part in ("direct", "indirect", "popandpush"))
    missing = sorted(required - counters.keys())
    if missing:
        raise ValueError(f"{path}: missing shared MPKI counters; rebuild and rerun: {', '.join(missing)}")
    if any(counters[name] < 0 for name in required) or any(counters[name] <= 0 for name in ("cycles", "commit_instr")):
        raise ValueError(f"{path}: invalid counter value")

    def check(label, actual, expected):
        if actual != expected:
            raise ValueError(f"{path}: {label}: {actual} != {expected}")

    total = counters["branch_mispredict"]
    check("CFI partition", sum(counters[f"branch_mispredict_{kind}"] for kind in parts), total)
    check("cause partition", sum(counters[f"branch_mispredict_{cause}"] for cause in CAUSES), total)
    check("CFI coverage", counters["branch_mispredict_other"], 0)
    check("committed CFI partition", sum(counters[f"branch_commit_{kind}"] for kind in KINDS),
          counters["branch_commit_total"])
    for kind in parts:
        check(f"{kind} cause partition", sum(counters[f"branch_mispredict_{kind}_{cause}"] for cause in CAUSES),
              counters[f"branch_mispredict_{kind}"])
    for cause in CAUSES:
        check(f"{cause} CFI partition", sum(counters[f"branch_mispredict_{kind}_{cause}"] for kind in parts),
              counters[f"branch_mispredict_{cause}"])
    check("call partition", counters["branch_mispredict_call_direct"] + counters["branch_mispredict_call_indirect"],
          counters["branch_mispredict_call"])
    check("legacy JALR cross-check", counters["branch_mispredict_return"] +
          counters["branch_mispredict_indirectuncond"] + counters["branch_mispredict_call_indirect"],
          counters["control_flow_target_mispredict"])
    if counters["branch_mispredict_call_popandpush"] > counters["branch_mispredict_call_indirect"]:
        raise ValueError(f"{path}: PopAndPush exceeds indirect calls")
    if counters["branch_commit_total"] > counters["commit_instr"]:
        raise ValueError(f"{path}: committed CFIs exceed committed instructions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("--output-dir", type=Path, help="New directory; defaults to RUN_ROOT/mpki-analysis")
    args = parser.parse_args()
    root = args.run_root.resolve()
    info = read_pairs(root / "run-info.txt")
    configs = [info["fdip_config"], info["coupled_config"]]
    rows, cause_rows, support_rows, reports = [], [], [], []
    for benchmark in info["benchmarks"].split():
        for config in configs:
            run = root / config / benchmark
            status = read_pairs(run / "status")
            report = {"benchmark": benchmark, "config": config, "status": status["status"]}
            if status["status"] != "passed":
                reports.append(report)
                continue
            counters = read_counters(run / "xsperf.tsv")
            validate(counters, run / "xsperf.tsv")
            for key in ("cycles", "commit_instr"):
                if counters[key] != int(status[key]):
                    raise ValueError(f"{run}: {key} disagrees with status")
            if status["exit"] != "0":
                raise ValueError(f"{run}: passed status has nonzero exit")
            instructions = counters["commit_instr"]
            total = counters["branch_mispredict"]
            report.update(counters=counters, ipc=instructions / counters["cycles"],
                          mpki=total * 1000 / instructions, checks="passed")
            reports.append(report)
            for kind in KINDS + ("other", "total"):
                count = total if kind == "total" else counters[f"branch_mispredict_{kind}"]
                committed = (counters["branch_commit_total"] if kind == "total" else
                             counters.get(f"branch_commit_{kind}", ""))
                rows.append((benchmark, config, kind, instructions, count, f"{count * 1000 / instructions:.9f}",
                             f"{count / total:.9f}" if total else "", committed))
            for kind in KINDS + ("other", "total"):
                for cause in CAUSES:
                    key = f"branch_mispredict_{cause}" if kind == "total" else f"branch_mispredict_{kind}_{cause}"
                    count = counters[key]
                    cause_rows.append((benchmark, config, kind, cause, count, f"{count * 1000 / instructions:.9f}"))
            for part in ("direct", "indirect", "popandpush"):
                count = counters[f"branch_mispredict_call_{part}"]
                support_rows.append((benchmark, config, f"call_{part}", count, f"{count * 1000 / instructions:.9f}"))
    out = (args.output_dir or root / "mpki-analysis").resolve()
    out.mkdir(parents=True, exist_ok=False)
    for filename, header, data in (
        ("mpki.tsv", ("benchmark", "config", "kind", "commit_instr", "mispredicts", "mpki", "mispredict_share", "committed_cfis"), rows),
        ("mpki-causes.tsv", ("benchmark", "config", "kind", "cause", "mispredicts", "mpki"), cause_rows),
        ("mpki-call-subsets.tsv", ("benchmark", "config", "subset", "mispredicts", "mpki"), support_rows),
    ):
        with (out / filename).open("w", newline="") as stream:
            writer = csv.writer(stream, delimiter="\t")
            writer.writerow(header)
            writer.writerows(data)
    (out / "validation.json").write_text(json.dumps({"run_root": str(root), "runs": reports}, indent=2) + "\n")
    print(f"Validated {sum(r['status'] == 'passed' for r in reports)} runs; wrote {out}")


if __name__ == "__main__":
    main()
