import importlib.util
import os
from unittest import mock
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "validation_receipt.py"
spec = importlib.util.spec_from_file_location("validation_receipt", SCRIPT)
receipt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receipt)


class ValidationReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git_environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, env=self.git_environment)
        (self.root / "source.swift").write_text("original")
        subprocess.run(["git", "-C", str(self.root), "add", "source.swift"], check=True, env=self.git_environment)
        self.context = {"toolchain": "fixture", "hardware": "0"}

    def test_identical_source_and_environment_can_reuse_success(self):
        before = receipt.fingerprint(self.root, self.context)
        receipt.record(self.root, before, self.context)
        self.assertTrue(receipt.reusable(self.root, self.context))
        self.assertFalse(receipt.reusable(self.root, {"toolchain": "changed"}))

    def test_tracked_untracked_and_mode_changes_invalidate(self):
        before = receipt.fingerprint(self.root, self.context)
        receipt.record(self.root, before, self.context)
        (self.root / "untracked.swift").write_text("new source")
        self.assertFalse(receipt.reusable(self.root, self.context))
        (self.root / "untracked.swift").unlink()
        (self.root / "source.swift").chmod(0o755)
        self.assertFalse(receipt.reusable(self.root, self.context))
        (self.root / "source.swift").chmod(0o644)
        (self.root / "source.swift").write_text("edited")
        self.assertFalse(receipt.reusable(self.root, self.context))

    def test_changes_during_validation_cannot_be_recorded_as_success(self):
        before = receipt.fingerprint(self.root, self.context)
        (self.root / "source.swift").write_text("edited during test")
        with self.assertRaises(ValueError):
            receipt.record(self.root, before, self.context)
        self.assertFalse(receipt.reusable(self.root, self.context))

    def test_irrelevant_path_prefix_keeps_resolved_tool_context(self):
        receipt.platform.platform()  # Prime stdlib platform discovery before mocking version commands.
        with mock.patch.object(receipt.subprocess, "check_output", return_value="fixture version"):
            before = receipt.tool_context()
            with mock.patch.dict(os.environ, {"PATH": str(self.root) + os.pathsep + os.environ["PATH"]}):
                self.assertEqual(before, receipt.tool_context())

    def test_hook_git_environment_cannot_redirect_source_fingerprint(self):
        before = receipt.fingerprint(self.root, self.context)
        with mock.patch.dict(os.environ, {"GIT_DIR": str(self.root / "missing.git")}):
            self.assertEqual(receipt.fingerprint(self.root, self.context), before)

    def test_fresh_run_invalidates_old_success_before_checks(self):
        before = receipt.fingerprint(self.root, self.context)
        receipt.record(self.root, before, self.context)
        receipt.invalidate(self.root)
        self.assertFalse(receipt.reusable(self.root, self.context))

    def test_missing_or_stale_receipt_does_not_pass(self):
        self.assertFalse(receipt.reusable(self.root, self.context))
        before = receipt.fingerprint(self.root, self.context)
        receipt.record(self.root, before, self.context, now=10)
        self.assertFalse(receipt.reusable(self.root, self.context, now=4000))


if __name__ == "__main__":
    unittest.main()
