#!/usr/bin/env python3
"""Render RTL PULP_FILTER_ACCEPT events with their static ELF instructions."""

import argparse
import re
import subprocess
from pathlib import Path


def disassembly(objdump: str, elf: Path) -> dict[int, tuple[str, str]]:
    output = subprocess.check_output([objdump, "-d", "-M", "no-aliases", str(elf)], text=True)
    result = {}
    for line in output.splitlines():
        match = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]+)\s+(.+)", line)
        if match:
            result[int(match.group(1), 16)] = (match.group(2), match.group(3))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vcs_log", type=Path)
    parser.add_argument("elf", type=Path)
    parser.add_argument("--objdump", default="riscv64-unknown-elf-objdump")
    args = parser.parse_args()

    instructions = disassembly(args.objdump, args.elf)
    phase = "setup"
    for line in args.vcs_log.read_text(encoding="utf-8").splitlines():
        if "--- Test 1:" in line:
            phase = "test1_both"
        elif "--- Test 2:" in line:
            phase = "test2_a_only"
        elif "--- Test 3:" in line:
            phase = "test3_b_only"
        match = re.search(r"PULP_FILTER_ACCEPT pc=([0-9a-fA-F]+)", line)
        if not match:
            continue
        pc = int(match.group(1), 16)
        encoding, mnemonic = instructions.get(pc, ("<unavailable>", "<unavailable>"))
        print(f"RTL_ACCEPT phase={phase} pc=0x{pc:016x} encoding=0x{encoding} {mnemonic}")


if __name__ == "__main__":
    main()
