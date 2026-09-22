import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from download_polish_model import allowed_model_file, checked_path, install


class PolishDownloadTests(unittest.TestCase):
    def test_rejects_escaping_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ("../outside", "/outside"):
                with self.assertRaises(ValueError):
                    checked_path(Path(folder), name)

    def test_readiness_requires_all_hashes_and_supports_retry(self):
        revision = "a" * 40
        payload = {"config.json": b"{}", "tokenizer.json": b"{}", "model.safetensors": b"weights"}
        entries = [SimpleNamespace(rfilename=name, size=len(data),
                                   lfs=SimpleNamespace(sha256=hashlib.sha256(data).hexdigest()))
                   for name, data in payload.items()]
        api = SimpleNamespace(model_info=lambda *args, **kwargs: SimpleNamespace(sha=revision, siblings=entries))
        corrupt = True

        def download(*args, local_dir, **kwargs):
            self.assertFalse((local_dir / "verified.json").exists())
            for name, data in payload.items():
                if not (local_dir / name).exists():
                    (local_dir / name).write_bytes(b"corrupt" if corrupt and name.endswith("safetensors") else data)

        fake = SimpleNamespace(HfApi=lambda: api, snapshot_download=download)
        with tempfile.TemporaryDirectory() as folder, patch.dict(sys.modules, {"huggingface_hub": fake}):
            root = Path(folder)
            with self.assertRaises(ValueError):
                install("test/model", revision, root)
            self.assertFalse((root / "verified.json").exists())
            corrupt = False
            install("test/model", revision, root)
            self.assertEqual(len(json.loads((root / "verified.json").read_text())), 3)
            (root / "model.safetensors").write_bytes(b"damaged")
            install("test/model", revision, root)
            self.assertEqual((root / "model.safetensors").read_bytes(), b"weights")

    def test_requires_pinned_revision(self):
        with patch.dict(sys.modules, {"huggingface_hub": SimpleNamespace(HfApi=None, snapshot_download=None)}):
            with self.assertRaises(ValueError):
                install("test/model", "main", Path("unused"))

    def test_only_explicit_data_and_license_names_are_allowed(self):
        for name in ("config.json", "tokenizer.json", "model.safetensors", "model-00001-of-00003.safetensors", "LICENSE", "README.md", "chat_template.jinja"):
            self.assertTrue(allowed_model_file(name), name)
        for name in ("model.py", "setup.sh", "weights.bin", "plugin.dylib", "unknown.json", "sub/config.json", "../config.json", "model.safetensors.py", "config.json/evil"):
            self.assertFalse(allowed_model_file(name), name)

    def test_repository_code_is_never_requested_or_marked_verified(self):
        revision = "b" * 40
        payload = {"config.json": b"{}", "tokenizer.json": b"{}", "model.safetensors": b"weights", "README.md": b"license information", "model.py": b"raise RuntimeError", "setup.sh": b"exit 1"}
        entries = [SimpleNamespace(rfilename=name, size=len(data), lfs=SimpleNamespace(sha256=hashlib.sha256(data).hexdigest())) for name, data in payload.items()]
        expected = {name for name in payload if allowed_model_file(name)}
        requested = []
        def download(*args, local_dir, allow_patterns, **kwargs):
            requested.extend(allow_patterns)
            for name in allow_patterns:
                (local_dir / name).write_bytes(payload[name])
        api = SimpleNamespace(model_info=lambda *a, **k: SimpleNamespace(sha=revision, siblings=entries))
        fake = SimpleNamespace(HfApi=lambda: api, snapshot_download=download)
        with tempfile.TemporaryDirectory() as folder, patch.dict(sys.modules, {"huggingface_hub": fake}):
            root = Path(folder)
            install("test/model", revision, root)
            self.assertEqual(set(requested), expected)
            self.assertEqual({e["file"] for e in json.loads((root / "verified.json").read_text())}, expected)
            self.assertFalse((root / "model.py").exists())

    def test_missing_required_data_fails_before_downloading(self):
        revision = "c" * 40
        api = SimpleNamespace(model_info=lambda *a, **k: SimpleNamespace(sha=revision, siblings=[]))
        def unexpected(*a, **k): self.fail("must not download incomplete model")
        with tempfile.TemporaryDirectory() as folder, patch.dict(sys.modules, {"huggingface_hub": SimpleNamespace(HfApi=lambda: api, snapshot_download=unexpected)}):
            ready = Path(folder) / "verified.json"
            ready.write_text("[]")
            with self.assertRaises(ValueError): install("test/model", revision, Path(folder))
            self.assertFalse(ready.exists())
