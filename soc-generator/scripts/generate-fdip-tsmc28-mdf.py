#!/usr/bin/env python3
"""Generate the FDIP Mega TSMC28 MDF and simulation source list.

UHDDPSRAM uses A=read and B=write. Its single clock is supplied by the write
port. This binding requires both target clocks to be the same signal.
"""
import argparse
import json
from pathlib import Path


CORNER = "ssg0p81v125c"
VLSI = Path(__file__).resolve().parents[1] / "generator/chipyard/vlsi"


def pp(kind, name, polarity="active high"):
    return {kind + " port name": name, kind + " port polarity": polarity}


def dual_ports():
    reader = {}
    reader.update(pp("address", "AA"))
    reader.update(pp("read enable", "CEBA", "active low"))
    reader.update(pp("output", "QA"))
    writer = {}
    writer.update(pp("address", "AB"))
    writer.update(pp("clock", "CLK", "positive edge"))
    # Gate the port with CEBB and keep WEBB in write mode.  Mapping W0_en
    # only to WEBB would leave B enabled for unwanted reads while idle.
    writer.update(pp("write enable", "CEBB", "active low"))
    writer.update(pp("input", "DB"))
    writer.update(pp("mask", "BWEBB", "active low"))
    writer["mask granularity"] = 1
    return [reader, writer]


def single_port():
    port = {}
    port.update(pp("address", "A"))
    port.update(pp("clock", "CLK", "positive edge"))
    port.update(pp("chip enable", "CEB", "active low"))
    port.update(pp("write enable", "WEB", "active low"))
    port.update(pp("input", "D"))
    port.update(pp("output", "Q"))
    port.update(pp("mask", "BWEB", "active low"))
    port["mask granularity"] = 1
    return port


def macro(spec):
    compiler, name = spec['compiler'], spec['name']
    depth, width = spec['depth'], spec['width']
    dual = compiler == 'uhddp'
    if dual:
        ports = dual_ports()
        extra = [
            {"name": "RTSEL", "width": 2, "type": "constant", "value": 0},
            {"name": "WTSEL", "width": 2, "type": "constant", "value": 0},
            {"name": "PTSEL", "width": 2, "type": "constant", "value": 0},
            {"name": "WEBA", "width": 1, "type": "constant", "value": 1},
            {"name": "WEBB", "width": 1, "type": "constant", "value": 0},
            {"name": "DA", "width": width, "type": "constant", "value": 0},
            {"name": "BWEBA", "width": width, "type": "constant", "value": 0},
        ]
    else:
        ports = [single_port()]
        extra = []
        if compiler == "uhd" and depth in (64, 1024, 512):
            # The generated 64-row UHDSPSRAM model requires RTSEL=10; the
            # 512/1024-row models require 00/00.  D127 has no select pins.
            rt = 2 if depth == 64 else 0
            extra = [
                {"name": "RTSEL", "width": 2, "type": "constant", "value": rt},
                {"name": "WTSEL", "width": 2, "type": "constant", "value": 0},
            ]
    result = {
        "type": "sram",
        "name": name,
        "width": width,
        "depth": str(depth),
        "family": "1r1w" if dual else "1rw",
        "mux": spec['mux'],
        "mask": True,
        "ports": ports,
    }
    if extra:
        result["extra ports"] = extra
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("/data2/TSMC28/Memory/SRAM/fdip-20261014"))
    parser.add_argument("--mdf", type=Path, default=VLSI / "fdip_tsmc28_sram_library.mdf.json")
    parser.add_argument("--sources", type=Path, default=VLSI / "fdip_tsmc28_sram_sim.sources")
    parser.add_argument("--install-view", action="store_true", help="create integration/<macro> symlinks and EDA view lists under root")
    args = parser.parse_args()
    specs = json.loads((args.root / 'specs.json').read_text())
    if not specs or len({s['name'] for s in specs}) != len(specs):
        raise RuntimeError('Empty or duplicate macro specifications')
    for spec in specs:
        if spec['compiler'] not in ('uhddp', 'uhd', 'd127') or not spec['bweb']:
            raise RuntimeError('Unsupported compiler or missing BWEB: ' + spec['name'])
    entries = [macro(spec) for spec in specs]
    lines = ["{compiler}/{name}/VERILOG/{name}_{corner}.v".format(corner=CORNER, **s) for s in specs]
    for line in lines:
        if not (args.root / line).is_file():
            raise RuntimeError('Missing SRAM simulation model: ' + line)
    args.mdf.parent.mkdir(parents=True, exist_ok=True)
    args.mdf.write_text(json.dumps(entries, indent=2) + "\n")
    args.sources.write_text("\n".join(lines) + "\n")
    print("Wrote {} macros to {}".format(len(entries), args.mdf))
    print("Wrote {} model files to {}".format(len(lines), args.sources))
    if args.install_view:
        view = args.root / 'integration'
        view.mkdir(exist_ok=True)
        (view / 'macros.list').write_text('\n'.join(s['name'] for s in specs) + '\n')
        for spec in specs:
            link = view / spec['name']
            target = args.root / spec['compiler'] / spec['name']
            if link.is_symlink() or link.exists():
                if link.resolve() != target.resolve():
                    raise RuntimeError('Refusing to replace existing path: ' + str(link))
            else:
                link.symlink_to(Path('..') / spec['compiler'] / spec['name'], target_is_directory=True)
        for label, corner in [('ss', CORNER), ('tt', 'tt0p9v85c'), ('ff', 'ffg1p05vm40c')]:
            for kind, extension in [('NLDM', 'db'), ('NLDM', 'lib'), ('VERILOG', 'v')]:
                paths = [args.root / s['compiler'] / s['name'] / kind / (s['name'] + '_' + corner + '.' + extension) for s in specs]
                for path in paths:
                    if not path.is_file():
                        raise RuntimeError('Missing EDA view: ' + str(path))
                (view / (label + '.' + extension + '.f')).write_text('\n'.join(map(str, paths)) + '\n')
        for kind, extension in [('LEF', 'lef'), ('GDSII', 'gds')]:
            paths = [args.root / s['compiler'] / s['name'] / kind / (s['name'] + '.' + extension) for s in specs]
            for path in paths:
                if not path.is_file():
                    raise RuntimeError('Missing physical view: ' + str(path))
            (view / (extension + '.f')).write_text('\n'.join(map(str, paths)) + '\n')
        print('Installed EDA view lists and macro symlinks at ' + str(view))


if __name__ == "__main__":
    main()
