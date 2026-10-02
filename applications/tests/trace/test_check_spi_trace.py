"""Regression tests for accepting empty exclusions and rejecting broken captures."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import check_spi_trace


class CheckSPITraceTests(unittest.TestCase):
    def check(self, testcase="test_iaddr_equal_match", pcs=(0x8000032C,),
              decode_rc=0, extra="", skipped=0, nibbles="a5\n",
              deframe="SPI_DEFRAME_PASS packets=1\n", monitor=True,
              privilege="Machine", cause=8):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            decoded = f"privilege: {privilege}\n"
            decoded += f"Trap(Trap {{ info: Info {{ ecause: {cause}, tval: 0 }} }})\n"
            decoded += "".join(
                f"TRACE_INSTRUCTION pc=0x{pc:016x} encoding=0x0013 addi zero, zero, 0\n"
                for pc in pcs
            )
            decoded += (
                f"PULP_ETRACE_RECONSTRUCT packets={int(bool(pcs))} "
                f"instructions={len(pcs)} skipped={skipped}\n" + extra
            )
            (root / "sim.log").write_text(
                "TRACE_PRIV_EXCEPTION_BEGIN\n"
                + ("TRACE_SPI_RECONSTRUCT_SUMMARY packets=1\n" if monitor else "")
            )
            (root / "deframe.log").write_text(deframe)
            (root / "decode.log").write_text(decoded)
            (root / "decode.rc").write_text(str(decode_rc))
            (root / "trace.nibbles").write_text(nibbles)
            nm = SimpleNamespace(stdout="8000032c t traced_block\n8000032c t user_block\n")
            with patch("sys.argv", ["check_spi_trace.py", testcase, "workload.riscv", directory]), \
                    patch("check_spi_trace.subprocess.run", return_value=nm), \
                    contextlib.redirect_stdout(io.StringIO()):
                check_spi_trace.main()

    def test_matching_address(self):
        self.check()

    def test_all_range_addresses(self):
        self.check("test_iaddr_range_match", pcs=(0x8000032C, 0x80000330, 0x80000334, 0x80000338))

    def test_user_exception(self):
        self.check("test_privilege_exception_trace", privilege="User",
                   pcs=(0x8000032C, 0x80000330, 0x80000334, 0x80000338))

    def test_wrong_exception_cause_and_privilege_fail(self):
        with self.assertRaisesRegex(SystemExit, "cause 8 is missing"):
            self.check("test_privilege_exception_trace", cause=2, privilege="User")
        with self.assertRaisesRegex(SystemExit, "unexpected exception trace privileges"):
            self.check("test_privilege_exception_trace", privilege="Machine")

    def test_mixed_privilege_context_fails(self):
        with self.assertRaisesRegex(SystemExit, "unexpected matching trace privileges"):
            self.check(privilege="Machine\nprivilege: User")

    def test_empty_exclusions_are_expected(self):
        for testcase in ("test_iaddr_equal_exclude", "test_iaddr_range_exclude",
                         "test_privilege_us_range_iaddr_exclude_m"):
            with self.subTest(testcase=testcase):
                self.check(testcase, pcs=(), decode_rc=2, nibbles="")

    def test_missing_spi_monitor_fails(self):
        with self.assertRaisesRegex(SystemExit, "SPI monitor summary is missing"):
            self.check(monitor=False)

    def test_empty_matching_capture_fails(self):
        with self.assertRaisesRegex(SystemExit, "emitted no instructions"):
            self.check(pcs=(), nibbles="")

    def test_wrong_address_fails(self):
        with self.assertRaisesRegex(SystemExit, "unexpected PCs"):
            self.check(pcs=(0x80000330,))

    def test_incomplete_range_fails(self):
        with self.assertRaisesRegex(SystemExit, "unexpected PCs"):
            self.check("test_iaddr_range_match")

    def test_truncation_and_decode_errors_fail(self):
        for error in ("truncated E-Trace tail", "undecodable E-Trace payload"):
            with self.subTest(error=error), self.assertRaises(SystemExit):
                self.check(extra=error)
        with self.assertRaisesRegex(SystemExit, "partial packet"):
            self.check(deframe="SPI_DEFRAME_TRUNCATED\nSPI_DEFRAME_PASS\n")

    def test_skipped_payload_fails(self):
        with self.assertRaisesRegex(SystemExit, "decoder skipped"):
            self.check(skipped=1)

    def test_exclusion_rejects_spi_data_and_wrong_decoder_status(self):
        with self.assertRaisesRegex(SystemExit, "drove SPI data"):
            self.check("test_iaddr_equal_exclude", pcs=(), decode_rc=2)
        with self.assertRaisesRegex(SystemExit, "expected 2"):
            self.check("test_iaddr_equal_exclude", pcs=(), decode_rc=0, nibbles="")


if __name__ == "__main__":
    unittest.main()
