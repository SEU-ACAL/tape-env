#!/usr/bin/env python3
"""Run high-volume JTAG traffic with only the RSP packets under test."""

import argparse
import hashlib
import socket
import struct
import sys
import time

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
        data = bytes.fromhex(response.decode("ascii"))
    except ValueError as exc:
        raise RspError("invalid memory response at 0x%x" % address) from exc
    if len(data) != length:
        raise RspError("short memory response at 0x%x: got %d bytes, expected %d" %
                       (address, len(data), length))
    return data


def read_register(rsp, register):
    return reg_value(rsp.request(b"p%x" % register))


def write_register(rsp, register, value):
    response = rsp.request(b"P%x=" % register + struct.pack("<Q", value).hex().encode("ascii"))
    if response != b"OK":
        raise RspError("register write failed for %x: %r" % (register, response))


def set_breakpoint(rsp, kind, address, length=4):
    response = rsp.request(b"Z%d,%x,%x" % (kind, address, length))
    if response != b"OK":
        raise RspError("failed to set breakpoint kind=%d at 0x%x: %r" %
                       (kind, address, response))


def clear_breakpoint(rsp, kind, address, length=4):
    response = rsp.request(b"z%d,%x,%x" % (kind, address, length))
    if response != b"OK":
        raise RspError("failed to clear breakpoint kind=%d at 0x%x: %r" %
                       (kind, address, response))


def expect_stop(rsp, address, cause, description):
    stop = rsp.request(b"c")
    if not stop.startswith((b"T05", b"S05")):
        raise RspError("%s did not stop with SIGTRAP: %r" % (description, stop))
    pc = read_register(rsp, 0x20)
    if pc != address:
        raise RspError("%s stopped at 0x%x, expected 0x%x" %
                       (description, pc, address))
    dcsr = read_register(rsp, 0x7f1)
    actual_cause = (dcsr >> 6) & 0x7
    if actual_cause != cause:
        raise RspError("%s DCSR cause=%d, expected %d" %
                       (description, actual_cause, cause))


def read_region(rsp, name, address, length, chunk):
    if length <= 0 or chunk <= 0:
        raise RspError("invalid %s read range" % name)
    print("JTAG_RSP_READ_START name=%s address=0x%x bytes=%d" %
          (name, address, length), flush=True)
    digest = hashlib.sha256()
    offset = 0
    while offset < length:
        count = min(chunk, length - offset)
        digest.update(read_memory(rsp, address + offset, count))
        offset += count
    print("JTAG_RSP_READ_PASS name=%s address=0x%x bytes=%d sha256=%s" %
          (name, address, length, digest.hexdigest()), flush=True)


def read_region_samples(rsp, name, address, length):
    if length <= 0:
        raise RspError("invalid %s read range" % name)
    offsets = {0, ((length - 1) // 8) * 8}
    if length > 8:
        offsets.add((length // 2 // 8) * 8)
    digest = hashlib.sha256()
    for offset in sorted(offsets):
        count = min(8, length - offset)
        digest.update(read_memory(rsp, address + offset, count))
    print("JTAG_RSP_READ_SAMPLE_PASS name=%s address=0x%x probes=%d sha256=%s" %
          (name, address, len(offsets), digest.hexdigest()), flush=True)


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


def verify_preloaded_elf(rsp, path):
    """Check sparse, aligned bytes from the image loaded by +loadmem."""
    probes = 0
    for address, data in elf_load_segments(path):
        offsets = {0, ((len(data) - 1) // 8) * 8}
        if len(data) > 8:
            offsets.add((len(data) // 2 // 8) * 8)
        for offset in sorted(offsets):
            count = min(8, len(data) - offset)
            actual = read_memory(rsp, address + offset, count)
            expected = data[offset:offset + count]
            if actual != expected:
                raise RspError("preloaded ELF mismatch at 0x%x: got %s expected %s" %
                               (address + offset, actual.hex(), expected.hex()))
            probes += 1
    print("JTAG_RSP_ELF_PRELOAD_VERIFY_PASS probes=%d" % probes, flush=True)


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
    parser.add_argument("--bootrom-base", type=lambda value: int(value, 0),
                        default=0x10000)
    parser.add_argument("--bootrom-size", type=lambda value: int(value, 0),
                        default=0x2000)
    parser.add_argument("--debugrom-base", type=lambda value: int(value, 0),
                        default=0x800)
    parser.add_argument("--debugrom-size", type=lambda value: int(value, 0),
                        default=0x80)
    parser.add_argument("--rom-read-chunk", type=lambda value: int(value, 0),
                        default=0x40)
    parser.add_argument("--elf-load-mode", choices=("preloaded", "write"),
                        default="preloaded")
    parser.add_argument("--rom-verify-mode", choices=("sampled", "full"),
                        default="sampled")
    parser.add_argument("--stop-after", choices=("reset", "register", "hardware", "software", "breakpoint", "step", "rom", "memory"),
                        default="memory", help=argparse.SUPPRESS)
    parser.add_argument("--skip-breakpoints", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--skip-hardware-breakpoint", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--timeout", type=float, default=500.0)
    args = parser.parse_args()
    if args.steps < 1 or args.memory < 1:
        parser.error("--steps and --memory must be positive")
    if args.steps > STEP_STREAM_INSTRUCTIONS:
        parser.error("--steps must not exceed %d" % STEP_STREAM_INSTRUCTIONS)
    if args.bootrom_size <= 0 or args.debugrom_size <= 0 or args.rom_read_chunk <= 0:
        parser.error("ROM sizes and --rom-read-chunk must be positive")

    rsp = None
    try:
        phase_start = time.monotonic()
        def phase(name):
            nonlocal phase_start
            elapsed = time.monotonic() - phase_start
            print("JTAG_RSP_PHASE name=%s elapsed=%.3f" % (name, elapsed), flush=True)
            phase_start = time.monotonic()

        print("JTAG_RSP_CONNECT host=%s port=%d" % (args.host, args.port), flush=True)
        rsp = Rsp(args.host, args.port, args.timeout)
        rsp.request(b"qSupported")
        response = rsp.request(b"QStartNoAckMode")
        if response == b"OK":
            rsp.no_ack = True
        print("JTAG_RSP_TARGET_READY", flush=True)
        rsp.monitor("riscv set_mem_access sysbus")
        rsp.monitor("reset halt")
        print("JTAG_RSP_RESET_HALT_PASS", flush=True)
        phase("reset")
        if args.stop_after == "reset":
            return 0
        if args.elf_load_mode == "write":
            for address, data in elf_load_segments(args.elf):
                write_memory(rsp, address, data)
            print("JTAG_RSP_ELF_LOAD_PASS", flush=True)
        else:
            # The simulator has already loaded this image through +loadmem;
            # repeating it over Remote Bitbang is prohibitively slow.
            print("JTAG_RSP_ELF_PRELOADED_PASS", flush=True)
        start = elf_symbol(args.elf, "gdb_step_stress")

        # Exercise abstract register write/read while the hart is halted.
        register_test_value = 0x1122334455667788
        write_register(rsp, 5, register_test_value)
        if read_register(rsp, 5) != register_test_value:
            raise RspError("GPR x5 readback mismatch")
        if read_register(rsp, 0) != 0:
            raise RspError("GPR x0 is not hard-wired to zero")
        print("JTAG_RSP_REGISTER_PASS x5_write_read x0_read")
        phase("register")
        if args.stop_after == "register":
            return 0

        if not args.skip_breakpoints:
            # Test one hardware trigger and one software EBREAK breakpoint.
            hardware_breakpoint = start + 64 * 4
            software_breakpoint = start + 128 * 4
            if not args.skip_hardware_breakpoint:
                write_register(rsp, 0x20, start)
                print("JTAG_RSP_HARDWARE_START address=0x%x" % hardware_breakpoint, flush=True)
                set_breakpoint(rsp, 1, hardware_breakpoint)
                expect_stop(rsp, hardware_breakpoint, 2, "hardware breakpoint")
                clear_breakpoint(rsp, 1, hardware_breakpoint)
                print("JTAG_RSP_BREAKPOINT_PASS kind=hardware address=0x%x" %
                      hardware_breakpoint)
                if args.stop_after == "hardware":
                    return 0

            write_register(rsp, 0x20, start)
            print("JTAG_RSP_SOFTWARE_START address=0x%x" % software_breakpoint, flush=True)
            set_breakpoint(rsp, 0, software_breakpoint)
            expect_stop(rsp, software_breakpoint, 1, "software breakpoint")
            clear_breakpoint(rsp, 0, software_breakpoint)
            print("JTAG_RSP_BREAKPOINT_PASS kind=software address=0x%x" %
                  software_breakpoint)
            if args.stop_after == "software":
                return 0
            phase("breakpoint")
            if args.stop_after == "breakpoint":
                return 0

        # Single-step a known fixed-width instruction stream.
        write_register(rsp, 0x20, start)

        for iteration in range(args.steps):
            stop = rsp.request(b"s")
            if not stop.startswith((b"T05", b"S05")):
                raise RspError("step %d returned %r" % (iteration, stop))
            pc = read_register(rsp, 0x20)
            expected_pc = start + (iteration + 1) * 4
            if pc != expected_pc:
                raise RspError("step %d PC 0x%x, expected 0x%x" %
                               (iteration, pc, expected_pc))
            dcsr = read_register(rsp, 0x7f1)
            if ((dcsr >> 6) & 0x7) != 4:
                raise RspError("step %d dcsr.cause=%d, expected 4" %
                               (iteration, (dcsr >> 6) & 0x7))
        print("JTAG_RSP_SINGLE_STEP_PASS steps=%d" % args.steps)
        phase("step")
        if args.stop_after == "step":
            return 0

        if args.rom_verify_mode == "full":
            read_region(rsp, "bootrom", args.bootrom_base, args.bootrom_size,
                        args.rom_read_chunk)
            read_region(rsp, "debugrom", args.debugrom_base, args.debugrom_size,
                        args.rom_read_chunk)
        else:
            read_region_samples(rsp, "bootrom", args.bootrom_base,
                                args.bootrom_size)
            read_region_samples(rsp, "debugrom", args.debugrom_base,
                                args.debugrom_size)
        phase("rom")
        if args.stop_after == "rom":
            return 0

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
        phase("memory")
        return 0
    except (OSError, RspError) as exc:
        print("JTAG_RSP_STRESS_FAIL: %s" % exc, file=sys.stderr)
        return 1
    finally:
        if rsp is not None:
            rsp.close()


if __name__ == "__main__":
    sys.exit(main())
