import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_resident_worker import validate_response


class ResidentValidationTests(unittest.TestCase):
    def setUp(self):
        self.envelope = {'request_id': 'r1', 'result': {
            'sample_id': 'S1', 'success': True, 'raw_text': '开发语音样本'}}

    def check(self, envelope):
        return validate_response(envelope, 'r1', 'S1', qwen_baseline=True)

    def test_accepts_matching_nonempty_baseline(self):
        self.assertIs(self.check(self.envelope), self.envelope['result'])

    def test_rejects_stale_or_cross_sample_success(self):
        for field, value in [('request_id', 'old'), ('sample_id', 'other')]:
            envelope = copy.deepcopy(self.envelope)
            (envelope if field == 'request_id' else envelope['result'])[field] = value
            with self.assertRaises(ValueError): self.check(envelope)

    def test_rejects_empty_or_unsuccessful_speech_result(self):
        for field, value in [('raw_text', ''), ('raw_text', ' \n'), ('raw_text', None), ('success', False)]:
            envelope = copy.deepcopy(self.envelope); envelope['result'][field] = value
            with self.assertRaises(ValueError): self.check(envelope)

    def test_rejects_any_prompt_evidence_in_baseline(self):
        for field, value in [('output_policy', 'simplified_prompt_v1'), ('output_policy', 'hotwords_v1'),
                             ('context_tokens', 13), ('hotword_count', 2)]:
            envelope = copy.deepcopy(self.envelope); envelope['result'][field] = value
            with self.assertRaises(ValueError): self.check(envelope)


if __name__ == '__main__': unittest.main()
