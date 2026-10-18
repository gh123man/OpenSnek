import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "review_packet.py"
spec = importlib.util.spec_from_file_location("review_packet", SCRIPT)
review_packet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review_packet)


class ReviewPacketTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.root / "example.txt").write_text("before\n")
        self.commit()
        self.base = self.git("rev-parse", "HEAD").strip()
        (self.root / "example.txt").write_text("after\n")
        self.commit()
        self.output = Path(self.temporary.name) / "packet"

    def git(self, *args):
        return subprocess.check_output(["git", "-c", "core.hooksPath=/dev/null",
            "-c", "commit.gpgsign=false", "-C", str(self.root), *args], text=True)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def test_packet_pins_the_range_even_after_head_moves(self):
        metadata = review_packet.create_packet(self.root, self.base, "HEAD", self.output, [])
        patch = (self.output / "changes.diff").read_text()
        self.assertIn("+after", patch)
        (self.root / "example.txt").write_text("later\n")
        self.commit()
        self.assertNotEqual(metadata["head_sha"], self.git("rev-parse", "HEAD").strip())
        self.assertEqual(json.loads((self.output / "review.json").read_text())["base_sha"], self.base)
        self.assertEqual((self.output / "changes.diff").read_text(), patch)

    def test_dirty_checkout_and_repo_local_output_are_rejected(self):
        with self.assertRaises(ValueError):
            review_packet.create_packet(self.root, self.base, "HEAD", self.root / "report", [])
        (self.root / "untracked.txt").write_text("not committed")
        with self.assertRaises(ValueError):
            review_packet.create_packet(self.root, self.base, "HEAD", self.output, [])
        self.assertFalse(self.output.exists())

    def test_invalid_ref_and_empty_range_do_not_create_packet(self):
        with self.assertRaises(subprocess.CalledProcessError):
            review_packet.create_packet(self.root, "missing-ref", "HEAD", self.output, [])
        with self.assertRaises(ValueError):
            review_packet.create_packet(self.root, "HEAD", "HEAD", self.output, [])
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
