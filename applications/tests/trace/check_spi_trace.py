#!/usr/bin/env python3
"""Validate the deterministic SPI trace CI workloads after ELF reconstruction."""

import argparse
import re
import subprocess
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"CI SPI trace FAIL: {message}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("testcase")
    parser.add_argument("elf", type=Path)
    parser.add_argument("result_dir", type=Path)
    args = parser.parse_args()

    sim = (args.result_dir / "sim.log").read_text()
    deframe = (args.result_dir / "deframe.log").read_text()
    decoded = (args.result_dir / "decode.log").read_text()
    decode_rc = int((args.result_dir / "decode.rc").read_text())
    require("TRACE_SPI_RECONSTRUCT_SUMMARY" in sim, "SPI monitor summary is missing")
    require("SPI_DEFRAME_PASS" in deframe, "SPI deframing did not complete")
    require("SPI_DEFRAME_TRUNCATED" not in deframe, "SPI capture ends in a partial packet")
    require("truncated E-Trace" not in decoded, "decoder stopped at a truncated packet")
    require("undecodable E-Trace" not in decoded, "decoder stopped at an invalid payload")
    require("encoding=<unavailable>" not in decoded, "reconstructed instruction is outside the ELF")

    summary = re.search(
        r"^PULP_ETRACE_RECONSTRUCT packets=(\d+) instructions=(\d+) skipped=(\d+)$",
        decoded, re.MULTILINE,
    )
    require(summary is not None, "decoder reconstruction summary is missing")
    packets, instructions, skipped = map(int, summary.groups())
    pcs = [
        int(pc, 16)
        for pc in re.findall(r"^TRACE_INSTRUCTION pc=0x([0-9a-f]+)", decoded, re.MULTILINE)
    ]
    require(skipped == 0, f"decoder skipped {skipped} payloads or instructions")
    require(instructions == len(pcs), "decoder instruction count does not match its output")
    privileges = set(re.findall(r"privilege: (\w+)", decoded))

    if "exclude" in args.testcase:
        require(decode_rc == 2, f"exclusion workload returned decoder code {decode_rc}, expected 2")
        require(packets == instructions == 0, "exclusion filter emitted trace")
        require((args.result_dir / "trace.nibbles").stat().st_size == 0, "exclusion filter drove SPI data")
    else:
        require(decode_rc == 0, f"decoder returned {decode_rc}")
        require(packets > 0 and instructions > 0, "matching workload emitted no instructions")
        nm = subprocess.run(
            ["riscv64-unknown-elf-nm", "--defined-only", str(args.elf)],
            check=True, capture_output=True, text=True,
        ).stdout
        symbols = {
            fields[2]: int(fields[0], 16)
            for line in nm.splitlines()
            if len(fields := line.split()) == 3
        }
        if args.testcase == "test_privilege_exception_trace":
            require("TRACE_PRIV_EXCEPTION_BEGIN" in sim, "U-mode exception workload did not start")
            require(privileges == {"User"}, f"unexpected exception trace privileges: {privileges}")
            require(
                re.search(r"Trap\(.*ecause: 8\b", decoded) is not None,
                "U-mode ECALL cause 8 is missing",
            )
            require("user_block" in symbols, "user_block ELF symbol is missing")
            start = symbols["user_block"]
            require(
                set(pcs) == {start, start + 4, start + 8, start + 12},
                "unexpected U-mode instruction addresses",
            )
        else:
            require("traced_block" in symbols, "traced_block ELF symbol is missing")
            start = symbols["traced_block"]
            expected = (
                {start + offset for offset in (0, 4, 8, 12)}
                if args.testcase == "test_iaddr_range_match" else {start}
            )
            require(set(pcs) == expected, f"IADDR filter returned unexpected PCs: {pcs}")
            require(privileges == {"Machine"}, f"unexpected matching trace privileges: {privileges}")

    print(f"CI SPI trace workload PASS: {args.testcase} packets={packets} instructions={instructions}")


if __name__ == "__main__":
    main()
