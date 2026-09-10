import hashlib
import contextlib
import io
import json
from unittest.mock import patch
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('smoke', Path(__file__).parents[1] / 'whisper_smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)

class AssetChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / 'weight.bin').write_bytes(b'valid')
        self.file = dict(path='weight.bin', size_bytes=5, sha256=hashlib.sha256(b'valid').hexdigest())

    def test_valid_asset(self):
        smoke.verify(self.root, [self.file])

    def test_wrong_hash_same_size(self):
        (self.root / 'weight.bin').write_bytes(b'wrong')
        with self.assertRaises(ValueError): smoke.verify(self.root, [self.file])

    def test_missing_and_wrong_size(self):
        for name in ('absent', 'weight.bin'):
            with self.assertRaises(ValueError): smoke.verify(self.root, [dict(self.file, path=name, size_bytes=9)])

    def test_unsafe_paths(self):
        for name in ('../outside', '/tmp/outside', 'folder/../../outside', 'a\\b'):
            with self.assertRaises(ValueError): smoke.asset_path(self.root, name)

    def test_symlink(self):
        (self.root / 'alias').symlink_to(self.root / 'weight.bin')
        with self.assertRaises(ValueError): smoke.verify(self.root, [dict(self.file, path='alias')])

    def test_duplicate_and_empty(self):
        for files in ([], [self.file, self.file]):
            with self.assertRaises(ValueError): smoke.verify(self.root, files)

class FailureRows(unittest.TestCase):
    def test_missing_model_emits_failure_without_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            (root / 'benchmark/corpus/audio').mkdir(parents=True)
            (root / 'benchmark/corpus/audio/sample.wav').write_bytes(b'audio')
            model = dict(repository='example/model', revision='pinned', resolved_folder='model',
                         files=[dict(path='absent', size_bytes=1, sha256='0' * 64)])
            candidate = dict(id='whisperkit-medium', model=model, engine=dict(source_revision='engine'))
            (root / 'benchmark/model-manifest.json').write_text(json.dumps(dict(candidates=[candidate])))
            tok = dict(candidate_id='whisperkit-medium', revision='tokenizer', files=[])
            (root / 'benchmark/whisper-tokenizers.json').write_text(json.dumps(dict(tokenizers=[tok])))
            sample = dict(sample_id='SMOKE-001', audio_path='audio/sample.wav', duration_ms=1,
                          audio_sha256=hashlib.sha256(b'audio').hexdigest())
            (root / 'benchmark/corpus/manifest.jsonl').write_text(json.dumps(sample))
            output = io.StringIO()
            with patch.object(smoke, 'ROOT', root), patch.object(smoke, 'CACHE', root / 'cache'), \
                 patch('sys.argv', ['smoke', 'whisperkit-medium', '--binary', '/unused']), \
                 patch.object(smoke.subprocess, 'check_output', return_value='16'), \
                 patch.object(smoke.subprocess, 'run') as launch, contextlib.redirect_stdout(output):
                with self.assertRaises(SystemExit) as caught:
                    smoke.main()
            self.assertEqual(caught.exception.code, 1)
            launch.assert_not_called()
            row = json.loads(output.getvalue())
            self.assertFalse(row['success'])
            self.assertIsNone(row['raw_text'])
            self.assertIn('missing/wrong size', row['error_code'])

if __name__ == '__main__': unittest.main()
