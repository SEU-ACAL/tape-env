#!/usr/bin/env python3
"""Convert SimTraceSPIMonitor nibble output to normal PULP encapsulation."""

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("nibbles", type=Path)
    parser.add_argument("encapsulation", type=Path)
    args = parser.parse_args()

    digits = "".join(args.nibbles.read_text(encoding="ascii").split())
    if len(digits) % 2:
        raise SystemExit(f"odd nibble count: {len(digits)}")
    try:
        stream = bytes.fromhex(digits)
    except ValueError as error:
        raise SystemExit(f"invalid hex nibble stream: {error}") from error

    offset = 0
    packets = 0
    output = bytearray()
    while offset < len(stream):
        if stream[offset] != 0xA5:
            raise SystemExit(f"bad magic at byte {offset}: 0x{stream[offset]:02x}")
        if offset + 2 > len(stream):
            raise SystemExit(f"truncated header at byte {offset}")
        length = stream[offset + 1]
        end = offset + 2 + length
        if end > len(stream):
            print(
                f"SPI_DEFRAME_TRUNCATED packet={packets} byte={offset} length={length} "
                f"payload_bytes={len(stream) - offset - 2}"
            )
            break
        output.extend(stream[offset + 1:end])
        offset = end
        packets += 1

    args.encapsulation.write_bytes(output)
    print(f"SPI_DEFRAME_PASS packets={packets} wire_bytes={len(stream)} encap_bytes={len(output)}")


if __name__ == "__main__":
    main()
