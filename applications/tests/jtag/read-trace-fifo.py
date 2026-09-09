#!/usr/bin/env python3
"""Minimal RSP/SBA trace FIFO reader for the Chipyard PULP trace backend."""
import argparse
import socket
import struct
import time

class Rsp:
    def __init__(self, host, port, timeout):
        self.s = socket.create_connection((host, port), timeout)
        self.s.settimeout(timeout)
        self.no_ack = False

    def req(self, payload):
        pkt = b"$" + payload + b"#%02x" % (sum(payload) & 255)
        self.s.sendall(pkt)
        if not self.no_ack and self.s.recv(1) != b"+":
            raise RuntimeError("RSP request not acknowledged")
        data = bytearray()
        while self.s.recv(1) != b"$":
            pass
        while True:
            c = self.s.recv(1)
            if c == b"#":
                break
            data += c
        self.s.recv(2)
        if not self.no_ack:
            self.s.sendall(b"+")
        return bytes(data)

    def monitor(self, command):
        encoded = command.encode().hex().encode()
        payload = b"qRcmd," + encoded
        pkt = b"$" + payload + b"#%02x" % (sum(payload) & 255)
        self.s.sendall(pkt)
        if not self.no_ack and self.s.recv(1) != b"+":
            raise RuntimeError("monitor request not acknowledged")
        result = b""
        # Read monitor replies directly because qRcmd may emit O packets.
        while True:
            data = bytearray()
            while self.s.recv(1) != b"$":
                pass
            while True:
                c = self.s.recv(1)
                if c == b"#": break
                data += c
            self.s.recv(2)
            if not self.no_ack:
                self.s.sendall(b"+")
            if data == b"OK": return result
            if data.startswith(b"O"):
                try: result += bytes.fromhex(data[1:].decode())
                except ValueError: pass
            else: return data

    def read(self, address, length):
        data = self.req(b"m%x,%x" % (address, length))
        if data.startswith(b"E"): raise RuntimeError(data.decode())
        return bytes.fromhex(data.decode())

    def write32(self, address, value):
        data = struct.pack("<I", value)
        escaped = bytearray()
        for c in data:
            if c in b"$#}*":
                escaped.extend((ord("}"), c ^ 0x20))
            else:
                escaped.append(c)
        response = self.req(b"X%x,%x:" % (address, len(data)) + escaped)
        if response != b"OK":
            raise RuntimeError("SBA write failed at 0x%x: %r" % (address, response))

    def close(self):
        try: self.req(b"D")
        except Exception: pass
        self.s.close()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=3338)
    p.add_argument("--base", type=lambda x: int(x, 0), default=0x10060000)
    p.add_argument("--out", required=True)
    p.add_argument("--run-seconds", type=float, default=0.5)
    p.add_argument("--max-bytes", type=int, default=4096)
    a = p.parse_args()
    rsp = Rsp(a.host, a.port, 300)
    try:
        rsp.req(b"qSupported")
        if rsp.req(b"QStartNoAckMode") == b"OK":
            rsp.no_ack = True
        rsp.monitor("riscv set_mem_access sysbus")
        rsp.monitor("reset halt")
        rsp.write32(a.base + 0x34, 1)
        rsp.write32(a.base + 0x4c, 0x3)
        rsp.write32(a.base + 0x94, 0x3)
        rsp.write32(a.base + 0x00, 3)
        time.sleep(a.run_seconds)
        status = struct.unpack("<I", rsp.read(a.base + 0x2c, 4))[0]
        count = min(status & 0x7ff, a.max_bytes) if status & (1 << 12) else 0
        trace = bytearray()
        if count:
            trace += rsp.read(a.base + 0x30, count)
        with open(a.out, "wb") as f: f.write(trace)
        print("SBA_TRACE_READ status=0x%08x bytes=%d out=%s" %
              (status, len(trace), a.out), flush=True)
        if not trace: raise RuntimeError("trace FIFO is empty")
    finally:
        rsp.close()

if __name__ == "__main__": main()
