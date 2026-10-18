import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check_device_validation.py"
spec = importlib.util.spec_from_file_location("device_validation", SCRIPT)
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class DeviceValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "evidence.md").write_text("Captured changed write/readback/restore")
        self.catalog = {"schemaVersion": 1, "profiles": [{"id": "mouse", "transport": "bluetooth",
            "productIDs": [216], "isLocallyValidated": False,
            "capabilities": {"dpi_stages": True, "poll_rate": False}}]}
        self.manifest = {"schema_version": 1, "devices": [{"profile_id": "mouse", "transport": "bluetooth",
            "product_ids": ["0x00D8"], "features": {"dpi_stages": {
                "status": "contributor_validated", "source": "https://github.com/contributor",
                "evidence": ["evidence.md"]}}, "limitations": ["Poll rate unexposed"]}]}

    def test_registered_identity_and_supported_claim_with_evidence_passes(self):
        self.assertEqual(validation.validate(self.manifest, self.catalog, self.root), [])

    def test_unknown_identity_unsupported_claim_and_missing_evidence_fail(self):
        for mutation in ["identity", "capability", "evidence", "credit", "maintainer"]:
            with self.subTest(mutation=mutation):
                import copy
                manifest = copy.deepcopy(self.manifest)
                device = manifest["devices"][0]
                claim = device["features"]["dpi_stages"]
                if mutation == "identity":
                    device["product_ids"] = ["0xFFFF"]
                elif mutation == "capability":
                    device["features"]["poll_rate"] = claim
                elif mutation == "evidence":
                    claim["evidence"] = ["missing.md"]
                elif mutation == "credit":
                    claim["source"] = ""
                else:
                    claim["status"] = "maintainer_validated"
                self.assertTrue(validation.validate(manifest, self.catalog, self.root))

    def test_evidence_cannot_escape_checkout(self):
        self.manifest["devices"][0]["features"]["dpi_stages"]["evidence"] = ["../outside.md"]
        self.assertTrue(validation.validate(self.manifest, self.catalog, self.root))

    def test_unknown_status_and_duplicate_device_fail(self):
        self.manifest["devices"][0]["features"]["dpi_stages"]["status"] = "probably_validated"
        self.assertTrue(validation.validate(self.manifest, self.catalog, self.root))
        self.manifest["devices"].append(self.manifest["devices"][0])
        self.assertTrue(validation.validate(self.manifest, self.catalog, self.root))


if __name__ == "__main__":
    unittest.main()
