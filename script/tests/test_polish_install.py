import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from setup_polish_runtime import migrate_model, migrate_python, publish_configuration, verify_internal_links


class PolishInstallTests(unittest.TestCase):
    def test_external_runtime_link_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            runtime = root / "runtime"
            runtime.mkdir()
            (runtime / "python").symlink_to(root / "developer-python")
            with self.assertRaises(ValueError):
                verify_internal_links(runtime)

    def test_internal_runtime_link_is_allowed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "python3.12").write_bytes(b"fixture")
            (root / "python").symlink_to("python3.12")
            verify_internal_links(root)

    def test_runtime_probe_failure_keeps_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder)
            configuration = {"python": "previous-python"}
            publish_configuration(destination, configuration)
            with patch("setup_polish_runtime.subprocess.run", side_effect=RuntimeError("probe failed")):
                with self.assertRaises(RuntimeError):
                    migrate_python(configuration, destination)
            self.assertEqual(json.loads((destination / "runtime.json").read_text()), configuration)

    def prepare(self, root):
        source = root / "source" / "revision"
        source.mkdir(parents=True)
        manifest = []
        for name in ["config.json", "tokenizer.json", "model.safetensors"]:
            content = b"fixture"
            (source / name).write_bytes(content)
            manifest.append({"file": name, "sha256": hashlib.sha256(content).hexdigest()})
        (source / "verified.json").write_text(json.dumps(manifest))
        return source

    def test_copy_is_independent_and_repeatable(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = self.prepare(root)
            destination = root / "installed"
            target = migrate_model(source, destination)
            self.assertEqual(migrate_model(source, destination), target)
            (source / "model.safetensors").write_bytes(b"changed")
            self.assertEqual((target / "model.safetensors").read_bytes(), b"fixture")
            publish_configuration(destination, {"model": str(target)})
            self.assertEqual(json.loads((destination / "runtime.json").read_text())["model"], str(target))

    def test_corrupt_source_keeps_previous_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = self.prepare(root)
            destination = root / "installed"
            destination.mkdir()
            publish_configuration(destination, {"model": "previous"})
            (source / "model.safetensors").write_bytes(b"broken")
            with self.assertRaises(ValueError):
                migrate_model(source, destination)
            self.assertEqual(json.loads((destination / "runtime.json").read_text()), {"model": "previous"})

    def test_manifest_cannot_copy_outside_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = self.prepare(root)
            (source / "verified.json").write_text(json.dumps([{"file": "../secret", "sha256": "unused"}]))
            with self.assertRaises(ValueError):
                migrate_model(source, root / "installed")


if __name__ == "__main__":
    unittest.main()
