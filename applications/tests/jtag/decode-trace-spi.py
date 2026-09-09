#!/usr/bin/env python3
"""Reconstruct PULP trace packets captured from quad-SPI DQ samples.

Input contains one hexadecimal nibble per SCK rising edge, in DQ[3:0] order.
Two nibbles form one MSB-first SPI byte. Packets are recovered as
0xA5 | length | payload[length], allowing resynchronization after loss. The
optional E-Trace output strips only the SPI transport magic and retains the
Normal Encapsulation length byte followed by the rv_tracer payload.
"""
import argparse
from pathlib import Path


def decode_nibbles(text):
    nibbles = [int(char, 16) for char in text if char in "0123456789abcdefABCDEF"]
    return bytes((nibbles[i] << 4) | nibbles[i + 1] for i in range(0, len(nibbles) - 1, 2))


def packets(data):
    index = 0
    result = []
    while index < len(data):
        try:
            index = data.index(0xA5, index)
        except ValueError:
            break
        if index + 1 >= len(data):
            break
        length = data[index + 1] & 0x1F
        end = index + 2 + length
        if end > len(data):
            break
        result.append(data[index:end])
        index = end
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--in", dest="input", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--etrace-out",
                        help="write concatenated E-Trace packets without SPI 0xA5 magic")
    args = parser.parse_args()
    raw = decode_nibbles(Path(args.input).read_text())
    rebuilt = packets(raw)
    if not rebuilt:
        raise SystemExit("TRACE_SPI_DECODE_FAIL no complete A5 packet")
    Path(args.out).write_bytes(b"".join(rebuilt))
    if args.etrace_out:
        Path(args.etrace_out).write_bytes(b"".join(packet[1:] for packet in rebuilt))
    print("TRACE_SPI_DECODE_PASS packets=%d bytes=%d out=%s" %
          (len(rebuilt), sum(map(len, rebuilt)), args.out))


if __name__ == "__main__":
    main()
