#!/usr/bin/env python3
"""Run high-volume JTAG traffic with only the RSP packets under test."""

import argparse
import socket
import struct
import sys

STEP_STREAM_INSTRUCTIONS = 256


class RspError(RuntimeError):
    pass


class Rsp:
    def __init__(self, host, port, timeout):
        self.sock = socket.create_connection((host, port), timeout)
        self.sock.settimeout(timeout)
        self.no_ack = False

    def _read_packet(self):
        data = bytearray()
        while True:
            byte = self.sock.recv(1)
            if not byte:
                raise RspError("connection closed while waiting for packet")
            if byte == b"$":
                break
        while True:
            byte = self.sock.recv(1)
            if not byte:
                raise RspError("connection closed in packet")
            if byte == b"#":
                break
            data.extend(byte)
        checksum = self.sock.recv(2)
        if len(checksum) != 2:
            raise RspError("short packet checksum")
        if (sum(data) & 0xff) != int(checksum, 16):
            raise RspError("bad packet checksum")
        if not self.no_ack:
            self.sock.sendall(b"+")
        return bytes(data)

    def request(self, payload):
        packet = b"$" + payload + b"#%02x" % (sum(payload) & 0xff)
        self.sock.sendall(packet)
        if not self.no_ack:
            ack = self.sock.recv(1)
            if ack != b"+":
                raise RspError("RSP request was not acknowledged: %r" % ack)
        response = self._read_packet()
        while response.startswith(b"O") and response != b"OK":
            response = self._read_packet()
        return response

    def monitor(self, command):
        encoded = command.encode("ascii").hex().encode("ascii")
        self.sock.sendall(b"$qRcmd," + encoded + b"#%02x" %
                          (sum(b"qRcmd," + encoded) & 0xff))
        if not self.no_ack:
            if self.sock.recv(1) != b"+":
                raise RspError("monitor command was not acknowledged")
        result = b""
        while True:
            response = self._read_packet()
            if response.startswith(b"O") and response != b"OK":
                # OpenOCD normally hex-encodes console output, but some
                # monitor commands return an unencoded diagnostic string.
                try:
                    result += bytes.fromhex(response[1:].decode("ascii"))
                except ValueError:
                    result += response[1:]
                continue
            if response == b"OK":
                return result
            if response.startswith(b"E"):
                raise RspError("monitor %s failed: %s" %
                               (command, response.decode("ascii")))
            return response

    def close(self):
        try:
            self.request(b"D")
        except (OSError, RspError):
            pass
        self.sock.close()


def write_memory(rsp, address, data):
    escaped = bytearray()
    for byte in data:
        if byte in (ord("$"), ord("#"), ord("}"), ord("*")):
            escaped.extend((ord("}"), byte ^ 0x20))
        else:
            escaped.append(byte)
    response = rsp.request(b"X%x,%x:" % (address, len(data)) + escaped)
    if response != b"OK":
        raise RspError("memory write failed at 0x%x: %r" % (address, response))


def read_memory(rsp, address, length):
    response = rsp.request(b"m%x,%x" % (address, length))
    if response.startswith(b"E"):
        raise RspError("memory read failed at 0x%x: %s" %
                       (address, response.decode("ascii")))
    try:
        return bytes.fromhex(response.decode("ascii"))
    except ValueError as exc:
        raise RspError("invalid memory response at 0x%x" % address) from exc


def elf_load_segments(path):
    image = open(path, "rb").read()
    if image[:4] != b"\x7fELF" or image[4] != 2 or image[5] != 1:
        raise RspError("%s is not a little-endian ELF64 file" % path)
    phoff = struct.unpack_from("<Q", image, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", image, 54)
    segments = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        p_type, _, p_offset, _, p_paddr, p_filesz, p_memsz, _ = struct.unpack_from(
            "<IIQQQQQQ", image, offset)
        if p_type != 1 or p_filesz == 0:
            continue
        data = image[p_offset:p_offset + p_filesz]
        segments.append((p_paddr, data))
        if p_memsz > p_filesz:
            segments.append((p_paddr + p_filesz, b"\0" * (p_memsz - p_filesz)))
    return segments


def elf_symbol(path, name):
    image = open(path, "rb").read()
    shoff = struct.unpack_from("<Q", image, 40)[0]
    shentsize, shnum = struct.unpack_from("<HH", image, 58)
    sections = []
    for index in range(shnum):
        offset = shoff + index * shentsize
        sections.append(struct.unpack_from("<IIQQQQIIQQ", image, offset))
    for section in sections:
        sh_type, sh_offset, sh_size, sh_link, sh_entsize = (
            section[1], section[4], section[5], section[6], section[9])
        if sh_type != 2 or not sh_entsize:
            continue
        strings = sections[sh_link]
        string_data = image[strings[4]:strings[4] + strings[5]]
        for offset in range(sh_offset, sh_offset + sh_size, sh_entsize):
            st_name, _, _, _, st_value, _ = struct.unpack_from(
                "<IBBHQQ", image, offset)
            end = string_data.find(b"\0", st_name)
            if string_data[st_name:end] == name.encode("ascii"):
                return st_value
    raise RspError("symbol %s not found in %s" % (name, path))


def reg_value(response):
    if response.startswith(b"E"):
        raise RspError("register read failed: %s" % response.decode("ascii"))
    data = bytes.fromhex(response.decode("ascii"))
    if len(data) != 8:
        raise RspError("expected 64-bit register, got %r" % response)
    return struct.unpack("<Q", data)[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3335)
    parser.add_argument("--elf", default="build/gdb-loop.elf")
    parser.add_argument("--steps", type=int, default=32)
    parser.add_argument("--memory", type=int, default=64)
    parser.add_argument("--memory-base", type=lambda value: int(value, 0),
                        default=0x80102000)
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()
    if args.steps < 1 or args.memory < 1:
        parser.error("--steps and --memory must be positive")
    if args.steps > STEP_STREAM_INSTRUCTIONS:
        parser.error("--steps must not exceed %d" % STEP_STREAM_INSTRUCTIONS)

    rsp = None
    try:
        rsp = Rsp(args.host, args.port, args.timeout)
        rsp.request(b"qSupported")
        response = rsp.request(b"QStartNoAckMode")
        if response == b"OK":
            rsp.no_ack = True
        rsp.monitor("riscv set_mem_access sysbus")
        rsp.monitor("reset halt")
        for address, data in elf_load_segments(args.elf):
            write_memory(rsp, address, data)
        start = elf_symbol(args.elf, "gdb_step_stress")
        rsp.request(b"P20=" + struct.pack("<Q", start).hex().encode("ascii"))

        for iteration in range(args.steps):
            stop = rsp.request(b"s")
            if not stop.startswith((b"T05", b"S05")):
                raise RspError("step %d returned %r" % (iteration, stop))
            pc = reg_value(rsp.request(b"p20"))
            expected_pc = start + (iteration + 1) * 4
            if pc != expected_pc:
                raise RspError("step %d PC 0x%x, expected 0x%x" %
                               (iteration, pc, expected_pc))
            dcsr = reg_value(rsp.request(b"p7f1"))
            if ((dcsr >> 6) & 0x7) != 4:
                raise RspError("step %d dcsr.cause=%d, expected 4" %
                               (iteration, (dcsr >> 6) & 0x7))

        for iteration in range(args.memory):
            address = args.memory_base + iteration * 8
            value = 0xA5A5000000000000 | iteration
            expected = struct.pack("<Q", value)
            write_memory(rsp, address, expected)
            actual = read_memory(rsp, address, len(expected))
            if actual != expected:
                raise RspError("memory %d mismatch: got %s expected %s" %
                               (iteration, actual.hex(), expected.hex()))
        print("JTAG_RSP_STRESS_PASS steps=%d memory=%d" %
              (args.steps, args.memory))
        return 0
    except (OSError, RspError) as exc:
        print("JTAG_RSP_STRESS_FAIL: %s" % exc, file=sys.stderr)
        return 1
    finally:
        if rsp is not None:
            rsp.close()


if __name__ == "__main__":
    sys.exit(main())
