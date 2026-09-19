import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from download_polish_model import checked_path, install


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
