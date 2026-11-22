#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../../.." && pwd)"
result_dir="${PULP_BACKPRESSURE_RESULT_DIR:-$(mktemp -d)}"
mkdir -p "$result_dir"
result_dir="$(cd -- "$result_dir" && pwd)"
printf 'PULP backpressure diagnostics: %s\n' "$result_dir"
verilator --binary --timing --assert -Wno-fatal --top-module test_pulp_backpressure \
  "+incdir+$repo_root/soc-generator/generator/rocket-chip/src/main/resources/vsrc/rv_tracer" \
  "$script_dir/test_pulp_backpressure.sv" --Mdir "$result_dir/obj" -j 4 \
  >"$result_dir/build.log" 2>&1
for events in 4 128; do
  "$result_dir/obj/Vtest_pulp_backpressure" "+events=$events" >"$result_dir/ready-$events.log"
  "$result_dir/obj/Vtest_pulp_backpressure" "+events=$events" +stall >"$result_dir/stall-$events.log"
done
# Dense control-flow events repeatedly fill/drain the input buffer and wrap its
# pointers, while the scoreboard checks every event and its associated metadata.
"$result_dir/obj/Vtest_pulp_backpressure" +events=128 +dense +stall >"$result_dir/dense.log"
"$result_dir/obj/Vtest_pulp_backpressure" +events=128 +dense >"$result_dir/dense-ready.log"
python3 - "$result_dir" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])

def packets(filename):
    log = (root / filename).read_text()
    assert "BACKPRESSURE_PASS" in log, log
    return re.findall(r"^PACKET .*?type=(\w+) len=\s*(\d+) payload=(\w+)$", log, re.M)

dense_reference, dense_stalled = packets("dense-ready.log"), packets("dense.log")
assert dense_reference == dense_stalled, (dense_reference, dense_stalled)
print(f"PULP_BACKPRESSURE_PASS dense_events=128 packets={len(dense_reference)}")
for events in (4, 128):
    reference, stalled = packets(f"ready-{events}.log"), packets(f"stall-{events}.log")
    assert reference == stalled, (events, reference, stalled)
    assert len(reference) == 4, reference
    # The final qualified instruction must be reported before EndedRep.
    assert reference[2][0] == "8" and int(reference[2][2], 16) == ((events - 1) * 4 << 2) | 2
    print(f"PULP_BACKPRESSURE_PASS block_events={events} packets={len(reference)}")
PY
