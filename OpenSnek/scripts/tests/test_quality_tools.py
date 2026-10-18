import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


class DiagnosticGateTests(unittest.TestCase):
    def check_log(self, text):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "build.log"
            log.write_text(text)
            return subprocess.run(
                [sys.executable, str(SCRIPTS / "check_swift_diagnostics.py"), str(log)],
                capture_output=True, text=True,
            )

    def test_long_body_warning_fails_even_when_compiler_succeeds(self):
        result = self.check_log("File.swift:1: warning: getter for property 'body' took 212ms to type-check (limit: 200ms)\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("long-body", result.stderr)

    def test_unrelated_warning_is_not_promoted(self):
        result = self.check_log("File.swift:1: warning: unrelated deprecated API\nBuild complete!\n")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ansi_colored_long_body_warning_fails(self):
        result = self.check_log("\033[33mwarning: \033[0mbody took 201ms to type-check (limit: 200ms)\n")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_log_fails_closed(self):
        result = subprocess.run([sys.executable, str(SCRIPTS / "check_swift_diagnostics.py"), "/missing/build.log"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)


class CheckedCommandTests(unittest.TestCase):
    def test_original_command_failure_is_not_hidden_by_tee(self):
        result = subprocess.run(["bash", str(SCRIPTS / "checked_command.sh"), "bash", "-c", "exit 17"], capture_output=True)
        self.assertEqual(result.returncode, 17)

    def test_successful_command_with_prohibited_warning_fails(self):
        result = subprocess.run(["bash", str(SCRIPTS / "checked_command.sh"), "printf",
            "warning: body took 222ms to type-check (limit: 200ms)\\n"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)


class WindowReceiptTests(unittest.TestCase):
    def receipt_result(self, *, role="app", count=1, wrong_bundle=False, missing=False):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "OpenSnek.app"
            receipt = Path(directory) / "receipt.json"
            if not missing:
                receipt.write_text(json.dumps({"schemaVersion": 1, "pid": os.getpid(),
                    "bundlePath": str(bundle) + (".wrong" if wrong_bundle else ""),
                    "role": role, "visibleWindowCount": count}))
            return subprocess.run([sys.executable, str(SCRIPTS / "wait_for_app_window.py"),
                str(receipt), str(bundle), "--timeout", "0"], capture_output=True, text=True)

    def test_visible_foreground_app_passes(self):
        self.assertEqual(self.receipt_result().returncode, 0)

    def test_service_hidden_window_wrong_bundle_and_missing_receipt_fail(self):
        for options in [{"role": "service"}, {"count": 0}, {"wrong_bundle": True}, {"missing": True}]:
            with self.subTest(options=options):
                self.assertNotEqual(self.receipt_result(**options).returncode, 0)


if __name__ == "__main__":
    unittest.main()
