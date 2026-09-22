import io
import hashlib
import tempfile
from types import SimpleNamespace
from unittest.mock import Mock
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from polish_worker import load_model, serve


class ResidentPolishTests(unittest.TestCase):
    def test_multiple_requests_keep_model_and_limits(self):
        incoming = io.BytesIO(b'{"request_id":"a","text":"one","max_tokens":128}\n'
                              b'{"request_id":"b","text":"two","max_tokens":256}\n')
        outgoing = io.StringIO()
        model, tokenizer = object(), object()
        with patch('polish_worker.polish', return_value=dict(accepted=True, text='ok', reason='test')) as mock:
            serve(model, tokenizer, 0.1, incoming, outgoing)
        rows = [json.loads(line) for line in outgoing.getvalue().splitlines()]
        self.assertEqual(rows[0]['type'], 'ready')
        self.assertEqual([r['request_id'] for r in rows[1:]], ['a', 'b'])
        self.assertEqual(mock.call_args_list[0].args, ('one', model, tokenizer, 128))
        self.assertEqual(mock.call_args_list[1].args, ('two', model, tokenizer, 256))

    def test_bad_request_does_not_break_next_one(self):
        incoming = io.BytesIO(b'{"request_id":"a","text":"one","max_tokens":99999}\n'
                              b'{"request_id":"b","text":"two","max_tokens":128}\n')
        outgoing = io.StringIO()
        with patch('polish_worker.polish', return_value=dict(accepted=True, text='ok', reason='test')):
            serve(None, None, 0, incoming, outgoing)
        rows = [json.loads(line) for line in outgoing.getvalue().splitlines()]
        self.assertEqual(rows[1]['error_code'], 'polish_failed')
        self.assertTrue(rows[2]['result']['accepted'])

    def test_oversized_request_is_rejected(self):
        with self.assertRaises(ValueError):
            serve(None, None, 0, io.BytesIO(b'x' * 32769), io.StringIO())

    def test_model_load_explicitly_disallows_remote_code_and_network(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "config.json").write_bytes(b"{}")
            (root / "verified.json").write_text(json.dumps([{"file": "config.json", "sha256": hashlib.sha256(b"{}").hexdigest()}]))
            loader = Mock(return_value=("model", "tokenizer"))
            with patch.dict(sys.modules, {"mlx_lm": SimpleNamespace(load=loader)}):
                self.assertEqual(load_model(root), ("model", "tokenizer"))
            loader.assert_called_once_with(str(root), tokenizer_config={"trust_remote_code": False, "local_files_only": True})
