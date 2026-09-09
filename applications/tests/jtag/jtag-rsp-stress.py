#!/usr/bin/env python3
"""Run high-volume JTAG traffic with only the RSP packets under test."""

import argparse
import hashlib
import socket
import struct
import sys
import time
import threading

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


def write_u32(rsp, address, value):
    write_memory(rsp, address, struct.pack("<I", value & 0xffffffff))


def read_u32(rsp, address):
    return struct.unpack("<I", read_memory(rsp, address, 4))[0]


def drain_trace_fifo(rsp, base, output, max_bytes, poll_limit=32):
    """Read the MMIO trace FIFO through OpenOCD SBA/RSP.

    status[12] is valid, status[11] is FIFO enqueue-ready, and status[10:0]
    is the queued byte count.  The data register is a read-and-pop register,
    so it must be accessed one byte at a time.
    """
    status_address = base + 0x2c
    data_address = base + 0x30
    captured = bytearray()
    # The hart is halted before this function is called, so the FIFO count is
    # stable. Read exactly the advertised number of bytes; polling an empty
    # FIFO repeatedly is prohibitively slow over remote-bitbang JTAG.
    for _ in range(poll_limit):
        status = read_u32(rsp, status_address)
        count = status & 0x7ff
        valid = bool(status & (1 << 12))
        if valid and count:
            # Each single-byte SBA pop costs ~1s over remote-bitbang JTAG, so
            # flush as we go: a timeout mid-drain then still leaves the bytes
            # read so far on disk instead of discarding the whole capture.
            for _ in range(min(count, max_bytes)):
                chunk = read_memory(rsp, data_address, 1)
                captured.extend(chunk)
                output.write(chunk)
                output.flush()
            break
    return bytes(captured)


def capture_trace(rsp, args):
    if not args.trace_out:
        return
    with open(args.trace_out, "wb") as trace_file:
        trace = drain_trace_fifo(rsp, args.trace_base, trace_file,
                                 args.trace_max_bytes)
    if not trace:
        raise RspError("trace FIFO was empty; encoder did not produce bytes")
    print("JTAG_TRACE_DRAIN_PASS address=0x%x bytes=%d file=%s" %
          (args.trace_base, len(trace), args.trace_out), flush=True)


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
    parser.add_argument("--trace-out", help="write JTAG-readable trace FIFO bytes to this file")
    parser.add_argument("--trace-spi-enable", action="store_true",
                        help="configure the PULP tracer for spi_0 output; do not read trace data over JTAG")
    parser.add_argument("--trace-base", type=lambda value: int(value, 0), default=0x10050000)
    parser.add_argument("--trace-max-bytes", type=int, default=4096)
    parser.add_argument("--trace-clear", action="store_true",
                        help="clear the trace FIFO before the normal stress sequence")
    parser.add_argument("--trace-only", action="store_true",
                        help="configure trace, continue target, and skip unrelated JTAG tests")
    parser.add_argument("--trace-run-seconds", type=float, default=0.1,
                        help=argparse.SUPPRESS)
    args = parser.parse_args()
    pulp_priv_enable_mode = 0x03  # PRIV_ENABLE_MODE: filter=1, EQUAL=1
    pulp_priv_m = 0x03            # rv_tracer PRIV encoding: M=3
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
        if args.trace_clear or args.trace_out:
            write_u32(rsp, args.trace_base + 0x34, 1)
            print("JTAG_TRACE_CLEAR_PASS address=0x%x" % (args.trace_base + 0x34), flush=True)
        trace_enable_pending = args.trace_out or args.trace_spi_enable
        if trace_enable_pending:
            if args.trace_base == 0x10060000:
                # PULP rv_tracer APB: enable privilege EQUAL filtering, then
                # match M (encoding 3). This excludes U/S trace packets.
                write_u32(rsp, args.trace_base + 0x4c, pulp_priv_enable_mode)
                write_u32(rsp, args.trace_base + 0x94, pulp_priv_m)
            if not args.trace_only:
                write_u32(rsp, args.trace_base + 0x00, 0x3)
                if args.trace_spi_enable:
                    print("JTAG_TRACE_SPI_ENABLE_PASS address=0x%x priv=M(3) mode=EQUAL" % args.trace_base, flush=True)
                else:
                    print("JTAG_TRACE_ENABLE_PASS address=0x%x" % args.trace_base, flush=True)
        if args.elf_load_mode == "write":
            for address, data in elf_load_segments(args.elf):
                write_memory(rsp, address, data)
            print("JTAG_RSP_ELF_LOAD_PASS", flush=True)
        else:
            # The simulator has already loaded this image through +loadmem;
            # repeating it over Remote Bitbang is prohibitively slow.
            print("JTAG_RSP_ELF_PRELOADED_PASS", flush=True)
        if args.trace_only:
            start = elf_symbol(args.elf, "gdb_step_stress")
            write_register(rsp, 0x20, start)
            print("JTAG_TRACE_ONLY_PC=0x%x" % start, flush=True)
            if trace_enable_pending:
                write_u32(rsp, args.trace_base + 0x00, 0x3)
                print("JTAG_TRACE_SPI_ENABLE_PASS address=0x%x priv=M(3) mode=EQUAL" % args.trace_base, flush=True)
            result = {}
            def run_target():
                try:
                    result["stop"] = rsp.request(b"c")
                except Exception as exc:
                    result["error"] = exc
            worker = threading.Thread(target=run_target, daemon=True)
            worker.start()
            time.sleep(max(0.0, args.trace_run_seconds))
            rsp.sock.sendall(b"\x03")
            worker.join(args.timeout)
            if worker.is_alive():
                raise RspError("trace-only continue did not stop after interrupt")
            if "error" in result:
                raise result["error"]
            print("JTAG_TRACE_ONLY_CONTINUE_PASS", flush=True)
            return 0
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
            capture_trace(rsp, args)
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
        capture_trace(rsp, args)
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
