#!/usr/bin/env python3
"""Reject separate read/write clocks before mapping to shared-CLK UHDDPSRAM.

Resolve scalar port forwarding through the emitted hierarchy and simple
wire aliases. Unsupported clock expressions fail closed.
"""
import argparse
import json
from pathlib import Path
import re


IDENTIFIER = r"[A-Za-z_$][\w$]*"


def strip_comments(text):
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--hierarchy", required=True, type=Path)
    parser.add_argument("--rtl-dir", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    memories = json.loads(args.metadata.read_text())
    hierarchy = json.loads(args.hierarchy.read_text())
    paths = {}
    modules = {}

    def index(node, ancestors):
        chain = ancestors + [node]
        paths[".".join(n["instance_name"] for n in chain)] = chain
        for child in node.get("instances", []):
            index(child, chain)

    index(hierarchy, [])

    def source(name):
        if name not in modules:
            candidates = [args.rtl_dir / (name + suffix) for suffix in (".sv", ".v")]
            files = [p for p in candidates if p.is_file()]
            if len(files) != 1:
                raise RuntimeError("Expected one emitted source for " + name)
            modules[name] = strip_comments(files[0].read_text())
        return modules[name]

    def connection(parent, child, port):
        text = source(parent["module_name"])
        pattern = (r"\b" + re.escape(child["module_name"]) + r"\s+" +
                   re.escape(child["instance_name"]) + r"\s*\((.*?)\)\s*;")
        instances = re.findall(pattern, text, re.S)
        if len(instances) != 1:
            raise RuntimeError("Cannot find instance " + child["instance_name"] + " in " + parent["module_name"])
        matches = re.findall(r"\." + re.escape(port) + r"\s*\(([^()]*)\)", instances[0])
        if len(matches) != 1:
            raise RuntimeError("Cannot resolve port " + port + " of " + child["instance_name"])
        value = matches[0].strip()
        if not re.fullmatch(IDENTIFIER, value):
            raise RuntimeError("Unsupported clock expression: " + value)
        return value

    def resolve(chain, port):
        level = len(chain) - 1
        signal = port
        while level > 0:
            signal = connection(chain[level - 1], chain[level], signal)
            level -= 1
            text = source(chain[level]["module_name"])
            visited = set()
            while True:
                if signal in visited:
                    raise RuntimeError("Cyclic clock alias " + signal)
                visited.add(signal)
                alias = re.findall(r"\bassign\s+" + re.escape(signal) + r"\s*=\s*(.*?)\s*;", text)
                if not alias:
                    break
                if len(alias) != 1 or not re.fullmatch(IDENTIFIER, alias[0]):
                    raise RuntimeError("Unsupported clock alias for " + signal)
                signal = alias[0]
            # FIRRTL emits ANSI input declarations, one declaration per line.
            is_input = re.search(r"\binput\s+(?:wire\s+)?" + re.escape(signal) + r"\s*[,\n)]", text)
            if not is_input:
                break
        return ".".join(n["instance_name"] for n in chain[:level + 1]) + "." + signal

    report = []
    for memory in memories:
        if memory["read"] != 1 or memory["write"] != 1 or memory["readwrite"] != 0:
            continue
        for path in memory["hierarchy"]:
            chain = paths[path]
            read = resolve(chain, "R0_clk")
            write = resolve(chain, "W0_clk")
            if read != write:
                raise RuntimeError("Separate clocks at {}: {} != {}".format(path, read, write))
            report.append({"hierarchy": path, "clock": read})
    if not report:
        raise RuntimeError("No shared-clock memories were checked")
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: {} 1R1W instances use identical read/write clocks".format(len(report)))


if __name__ == "__main__":
    main()
