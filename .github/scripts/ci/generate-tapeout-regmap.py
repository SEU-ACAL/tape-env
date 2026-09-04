#!/usr/bin/env python3
"""Render a selected Chipyard configuration's generated maps for CI."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated-src", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--config", default="TapeoutConfig")
    return parser.parse_args()


def parse_int(value: object) -> int:
    if isinstance(value, int):
        return value
    return int(str(value), 0)


def format_hex(value: int) -> str:
    return f"0x{value:08x}"


def markdown_escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def parse_dts_nodes(dts: str) -> dict[int, dict[str, object]]:
    """Extract properties needed for the memory-map overview from a DTS file."""
    nodes: dict[int, dict[str, object]] = {}
    node_start = re.compile(r"^\s*(?:[A-Za-z0-9_]+:\s+)?([A-Za-z0-9,_-]+)@([0-9a-fA-F]+)\s*\{")

    lines = dts.splitlines()
    index = 0
    while index < len(lines):
        match = node_start.match(lines[index])
        if not match:
            index += 1
            continue

        name = match.group(1)
        depth = lines[index].count("{") - lines[index].count("}")
        body: list[str] = []
        index += 1
        while index < len(lines) and depth > 0:
            line = lines[index]
            depth += line.count("{") - line.count("}")
            body.append(line)
            index += 1

        text = "\n".join(body)
        reg = re.search(r"\breg\s*=\s*<([^>]+)>;", text)
        if reg is None:
            continue
        reg_values = [parse_int(value) for value in reg.group(1).split()]
        # Child nodes such as spi@.../mmc@0 use relative addresses.  The
        # top-level memory map always has a base and a size cell.
        if len(reg_values) < 2:
            continue

        compatible = re.search(r'compatible\s*=\s*([^;]+);', text)
        interrupts = re.search(r"\binterrupts\s*=\s*<([^>]+)>;", text)
        clocks = re.search(r"\bclocks\s*=\s*<([^>]+)>;", text)
        nodes[reg_values[0]] = {
            "name": name,
            "compatible": re.findall(r'"([^"]+)"', compatible.group(1)) if compatible else [],
            "interrupts": interrupts.group(1).split() if interrupts else [],
            "clocks": clocks.group(1).split() if clocks else [],
        }

    return nodes


def load_regmaps(generated_src: Path) -> list[dict[str, object]]:
    regmaps: list[dict[str, object]] = []
    for path in sorted(generated_src.glob("*.regmap.json")):
        peripheral = json.loads(path.read_text())["peripheral"]
        base = parse_int(peripheral["baseAddress"])
        fields: list[dict[str, object]] = []
        for entry in peripheral.get("regfields", []):
            for field_name, field in entry.items():
                fields.append({"name": field_name, **field})
        regmaps.append(
            {
                "source": path.name,
                "name": peripheral["displayName"],
                "base": base,
                "fields": sorted(
                    fields,
                    key=lambda field: (parse_int(field["byteOffset"]), field["bitOffset"], field["name"]),
                ),
            }
        )
    return regmaps


def write_summary(
    output: Path,
    mappings: list[dict[str, object]],
    dts_nodes: dict[int, dict[str, object]],
    config: str = "TapeoutConfig",
) -> None:
    lines = [
        f"## {config} Register Map",
        "",
        f"Generated from this run's `{config}` DTS and regmap JSON artifacts.",
        "",
        "| Device | Compatible | Base address | Size | PLIC IRQ |",
        "|---|---|---:|---:|---:|",
    ]
    for mapping in mappings:
        base = mapping["base"]
        node = dts_nodes.get(base, {})
        name = ", ".join(mapping["names"])
        compatible = ", ".join(node.get("compatible", [])) or "-"
        interrupts = ", ".join(node.get("interrupts", [])) or "-"
        lines.append(
            "| {name} | {compatible} | `{base}` | `{size}` | {interrupts} |".format(
                name=markdown_escape(name),
                compatible=markdown_escape(compatible),
                base=format_hex(base),
                size=format_hex(mapping["size"]),
                interrupts=markdown_escape(interrupts),
            )
        )
    lines.extend(
        [
            "",
            f"The `{config}-regmap` artifact contains the complete register-field map, normalized JSON, DTS, memmap, and raw regmap JSON files.",
            "",
        ]
    )
    output.write_text("\n".join(lines))


def write_full_map(
    output: Path,
    mappings: list[dict[str, object]],
    regmaps: list[dict[str, object]],
    config: str = "TapeoutConfig",
) -> None:
    regmaps_by_base = {regmap["base"]: regmap for regmap in regmaps}
    lines = [f"# {config} Register Map", "", "## Address Map", "", "| Device | Base address | Size |", "|---|---:|---:|"]
    for mapping in mappings:
        lines.append(
            "| {name} | `{base}` | `{size}` |".format(
                name=markdown_escape(", ".join(mapping["names"])),
                base=format_hex(mapping["base"]),
                size=format_hex(mapping["size"]),
            )
        )

    for mapping in mappings:
        regmap = regmaps_by_base.get(mapping["base"])
        if regmap is None:
            continue
        lines.extend(
            [
                "",
                f"## {regmap['name']}",
                "",
                "| Offset | Bits | Field | Access | Reset | Description |",
                "|---:|---:|---|---|---:|---|",
            ]
        )
        for field in regmap["fields"]:
            offset = parse_int(field["byteOffset"])
            bit_offset = field["bitOffset"]
            bit_width = field["bitWidth"]
            msb = bit_offset + bit_width - 1
            bits = str(bit_offset) if bit_width == 1 else f"{msb}:{bit_offset}"
            reset = field.get("resetValue", "-")
            lines.append(
                "| `{offset}` | `{bits}` | {name} | {access} | {reset} | {description} |".format(
                    offset=format_hex(offset),
                    bits=bits,
                    name=markdown_escape(field["name"]),
                    access=markdown_escape(field.get("accessType", "-")),
                    reset=markdown_escape(reset),
                    description=markdown_escape(field.get("description", "-")),
                )
            )
    output.write_text("\n".join(lines) + "\n")


def main() -> None:
    args = parse_args()
    generated_src = args.generated_src.resolve()
    output_dir = args.output_dir.resolve()
    if not generated_src.is_dir():
        raise SystemExit(f"Generated source directory does not exist: {generated_src}")

    dts_paths = sorted(generated_src.glob("*.dts"))
    memmap_paths = sorted(generated_src.glob("*.memmap.json"))
    if len(dts_paths) != 1 or len(memmap_paths) != 1:
        raise SystemExit("Expected exactly one DTS and one memmap JSON file")

    dts_path = dts_paths[0]
    memmap_path = memmap_paths[0]
    dts_nodes = parse_dts_nodes(dts_path.read_text())
    memmap = json.loads(memmap_path.read_text())
    mappings = sorted(memmap["mapping"], key=lambda mapping: mapping["base"][0])
    normalized_mappings = [
        {
            "base": mapping["base"][0],
            "size": mapping["size"][0],
            "names": mapping["names"],
            "readable": mapping["r"][0],
            "writable": mapping["w"][0],
            "executable": mapping["x"][0],
            "cacheable": mapping["c"][0],
            "atomics": mapping["a"][0],
        }
        for mapping in mappings
    ]
    regmaps = load_regmaps(generated_src)

    output_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = output_dir / "raw"
    raw_dir.mkdir(exist_ok=True)
    shutil.copy2(dts_path, raw_dir / dts_path.name)
    shutil.copy2(memmap_path, raw_dir / memmap_path.name)
    for regmap_path in generated_src.glob("*.regmap.json"):
        shutil.copy2(regmap_path, raw_dir / regmap_path.name)

    write_summary(output_dir / "tapeout-regmap-summary.md", normalized_mappings, dts_nodes, args.config)
    write_full_map(output_dir / "tapeout-regmap.md", normalized_mappings, regmaps, args.config)
    (output_dir / "tapeout-regmap.json").write_text(
        json.dumps(
            {
                "dts": dts_path.name,
                "memmap": normalized_mappings,
                "registerMaps": regmaps,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
