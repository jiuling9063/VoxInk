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
from polish_worker import load_model, serve, SystemPromptCache


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

    def test_resident_passes_shared_system_cache_to_every_request(self):
        incoming = io.BytesIO(b'{"request_id":"a","text":"one"}\n'
                              b'{"request_id":"b","text":"two","language":"en"}\n')
        cache = object()
        with patch('polish_worker.polish', return_value=dict(accepted=True, text='ok')) as mock:
            serve(None, None, 0, incoming, io.StringIO(), cache)
        self.assertEqual([call.kwargs['prompt_cache'] for call in mock.call_args_list], [cache, cache])
        self.assertEqual(mock.call_args_list[1].kwargs['language'], 'en')

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


class SystemPromptCacheTests(unittest.TestCase):
    def setUp(self):
        self.model = Mock()
        self.tokenizer = Mock()
        self.mx = SimpleNamespace(array=lambda value: value, eval=Mock())
        self.factory = Mock(side_effect=lambda _: [SimpleNamespace(state=[], offset=0)])
        self.modules = patch.dict(sys.modules, {
            'mlx': SimpleNamespace(core=self.mx), 'mlx.core': self.mx,
            'mlx_lm.models.cache': SimpleNamespace(make_prompt_cache=self.factory),
        })
        self.modules.start()
        self.addCleanup(self.modules.stop)
        self.cache = SystemPromptCache(self.model, self.tokenizer)
        self.messages = [{'role': 'system', 'content': 'public'}, {'role': 'user', 'content': 'private'}]

    def test_reuses_only_system_prefix_and_copies_request_state(self):
        self.tokenizer.apply_chat_template.side_effect = [[1, 2], [1, 2, 3], [1, 2], [1, 2, 4]]
        suffix, options = self.cache.for_request(self.messages)
        self.assertEqual(suffix, [3])
        options['prompt_cache'][0].state.append('private dictation')
        suffix, next_options = self.cache.for_request(self.messages)
        self.assertEqual(suffix, [4])
        self.assertEqual(next_options['prompt_cache'][0].state, [])
        self.assertEqual(self.cache.cache[0].state, [])
        self.assertEqual(self.cache.tokens, [1, 2])
        self.assertEqual(self.factory.call_count, 1)
        self.model.assert_called_once()

    def test_language_switch_replaces_system_cache(self):
        self.tokenizer.apply_chat_template.side_effect = [[1, 2], [1, 2, 3], [5, 6], [5, 6, 7]]
        self.cache.for_request(self.messages)
        old = self.cache.cache
        suffix, _ = self.cache.for_request([{'role': 'system', 'content': 'English'}, self.messages[1]])
        self.assertEqual(suffix, [7])
        self.assertEqual(self.cache.tokens, [5, 6])
        self.assertIsNot(old, self.cache.cache)
        self.assertEqual(self.factory.call_count, 2)

    def test_template_mismatch_uses_full_prompt_without_cache(self):
        self.tokenizer.apply_chat_template.side_effect = [[1, 2], [1, 9, 3]]
        self.assertEqual(self.cache.for_request(self.messages), ([1, 9, 3], {}))

    def test_prefill_is_chunked(self):
        self.tokenizer.apply_chat_template.return_value = list(range(1100))
        self.cache.prepare(self.messages[0])
        self.assertEqual([len(call.args[0][0]) for call in self.model.call_args_list], [512, 512, 76])
