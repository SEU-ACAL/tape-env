#!/usr/bin/env python3
"""Capture the PULP trace FIFO after a short M-mode run through RSP/SBA."""
import argparse
import importlib.util
import struct
import time
import threading

_spec = importlib.util.spec_from_file_location(
    "jtag_rsp_stress", __file__.replace("capture-pulp-trace.py", "jtag-rsp-stress.py"))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=3338)
    p.add_argument("--base", type=lambda x: int(x, 0), default=0x10060000)
    p.add_argument("--out", required=True)
    p.add_argument("--run-seconds", type=float, default=0.01)
    p.add_argument("--max-bytes", type=int, default=128)
    p.add_argument("--timeout", type=float, default=900)
    p.add_argument("--step", action="store_true",
                   help="single-step one M-mode instruction before draining")
    p.add_argument("--steps", type=int, default=1,
                   help="number of RSP single-step instructions (with --step)")
    p.add_argument("--pc", type=lambda x: int(x, 0),
                   help="set the halted hart PC before --step/continue")
    a = p.parse_args()
    rsp = _mod.Rsp(a.host, a.port, a.timeout)
    try:
        print("PULP_CAPTURE_CONNECT", flush=True)
        rsp.request(b"qSupported")
        if rsp.request(b"QStartNoAckMode") == b"OK":
            rsp.no_ack = True
        print("PULP_CAPTURE_RSP_READY", flush=True)
        rsp.monitor("riscv set_mem_access sysbus")
        print("PULP_CAPTURE_MEM_ACCESS", flush=True)
        rsp.monitor("reset halt")
        print("PULP_CAPTURE_RESET_HALT", flush=True)
        _mod.write_u32(rsp, a.base + 0x34, 1)
        # PRIV_ENABLE_MODE=0x03: filter enabled, EQUAL mode.
        _mod.write_u32(rsp, a.base + 0x4c, 0x3)
        # Controller window maps APB byte offsets at base + 0x40 + 4*word.
        # PRIV_MATCH is APB word 0x15, hence controller offset 0x94.
        # PRIV_MATCH=0x15: M-mode encoding is 3.
        _mod.write_u32(rsp, a.base + 0x94, 0x3)
        _mod.write_u32(rsp, a.base + 0x00, 3)
        print("PULP_CAPTURE_CONFIGURED", flush=True)
        if a.pc is not None:
            _mod.write_register(rsp, 0x20, a.pc)
            print("PULP_CAPTURE_PC=0x%x" % a.pc, flush=True)
        if a.step:
            if a.steps < 1:
                raise RuntimeError("--steps must be positive")
            for step_index in range(a.steps):
                stop = rsp.request(b"s")
                if not stop.startswith((b"T05", b"S05")):
                    raise RuntimeError("single-step did not stop: %r" % (stop,))
                print("PULP_CAPTURE_STEP=%d" % (step_index + 1), flush=True)
        else:
            # Run through the normal RSP continue path, then interrupt the hart
        # with the protocol break byte.  OpenOCD's monitor `resume`/`halt`
        # pair can wait indefinitely with remote-bitbang.
            result = {}
            def run_target():
                try:
                    result["stop"] = rsp.request(b"c")
                except Exception as exc:
                    result["error"] = exc
            worker = threading.Thread(target=run_target, daemon=True)
            worker.start()
            time.sleep(a.run_seconds)
            rsp.sock.sendall(b"\x03")
            worker.join(a.timeout)
            if worker.is_alive():
                raise RuntimeError("RSP continue did not stop after interrupt")
            if "error" in result:
                raise result["error"]
        status = _mod.read_u32(rsp, a.base + 0x2c)
        count = min(status & 0x7ff, a.max_bytes) if status & (1 << 12) else 0
        data = _mod.read_memory(rsp, a.base + 0x30, count) if count else b""
        with open(a.out, "wb") as f:
            f.write(data)
        print("PULP_TRACE_CAPTURE status=0x%08x bytes=%d out=%s" %
              (status, len(data), a.out), flush=True)
        if not data:
            raise RuntimeError("trace FIFO empty")
    finally:
        rsp.close()


if __name__ == "__main__":
    main()
