import json
from pathlib import Path
import platform
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from install_polish_bundle import checksum, install, verify_payload


class PolishBundleTests(unittest.TestCase):
    def fixture(self, root):
        bundle = root / "bundle"
        payload = bundle / "payload"
        payload.mkdir(parents=True)
        (payload / "model").mkdir()
        for name in ("python", "worker", "model/weights"):
            (payload / name).write_text("fixture")
        manifest = {"format": 1, "system": sys.platform, "machine": platform.machine(),
                    "python": "python", "worker": "worker", "model": "model",
                    "files": {name: {"kind": "file", "sha256": checksum(payload / name)}
                              for name in ("python", "worker", "model/weights")}}
        (bundle / "manifest.json").write_text(json.dumps(manifest))
        return bundle, manifest

    def test_damaged_package_never_replaces_config(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle, manifest = self.fixture(root)
            (bundle / "payload/python").write_text("damaged")
            with self.assertRaises(ValueError):
                verify_payload(bundle / "payload", manifest)

    def test_failed_smoke_preserves_previous_install(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle, _ = self.fixture(root)
            destination = root / "installed"
            destination.mkdir()
            (destination / "runtime.json").write_text('{"python":"old"}')
            with patch("install_polish_bundle.smoke_test", side_effect=RuntimeError("failed")):
                with self.assertRaises(RuntimeError):
                    install(bundle, destination)
            self.assertEqual(json.loads((destination / "runtime.json").read_text()), {"python": "old"})
            self.assertEqual(list((destination / "installations").iterdir()), [])

    def test_success_uses_destination_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle, _ = self.fixture(root)
            destination = root / "different location"
            with patch("install_polish_bundle.smoke_test") as smoke:
                config = install(bundle, destination)
            smoke.assert_called_once_with(config)
            self.assertTrue(all(Path(value).is_relative_to(destination) for value in config.values()))
            self.assertEqual(json.loads((destination / "runtime.json").read_text()), config)

    def test_wrong_architecture_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle, manifest = self.fixture(root)
            manifest["machine"] = "unsupported"
            (bundle / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                install(bundle, root / "installed")
            self.assertFalse((root / "installed").exists())


if __name__ == "__main__":
    unittest.main()
