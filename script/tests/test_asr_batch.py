import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1]))
import json
import unittest
from run_asr_batch import make_plan, reconcile, summarize

class BatchChecks(unittest.TestCase):
    def setUp(self):
        self.samples = [dict(sample_id=f'S{i}', duration_ms=10000+i*2000, audio_path='unused') for i in range(3)]
        self.plan = make_plan(self.samples, 42)

    def payload(self, job, ms=100):
        return json.dumps(dict(request_id=job['request_id'], result=dict(raw_text='文本', success=True,
                            load_ms=10, transcribe_ms=ms, peak_rss_bytes=100)))

    def test_reproducible_plan(self):
        self.assertEqual(self.plan, make_plan(self.samples, 42))
        self.assertEqual(len(self.plan), 11)
        for n in (1,2,3):
            self.assertEqual({j['sample_id'] for j in self.plan if j['round']==n}, {'S0','S1','S2'})

    def test_warmup_excluded_and_unique_samples(self):
        rows = reconcile(self.plan, '\n'.join(self.payload(j, 9999 if j['phase'] != 'warm' else 100) for j in self.plan))
        overall = summarize(rows)['warm_groups']['overall']
        self.assertEqual(overall, dict(attempts=9, failures=0, independent_samples=3, p50_ms=100, p95_ms=100))

    def test_missing_result_retained(self):
        rows = reconcile(self.plan, '\n'.join(self.payload(j) for j in self.plan[:-1]))
        self.assertEqual(len(rows), 11)
        self.assertFalse(rows[-1]['success'])
        self.assertEqual(summarize(rows)['warm_groups']['overall']['failures'], 1)

    def test_duplicate_or_malformed_invalidates_protocol(self):
        for text in [self.payload(self.plan[0])+'\n'+self.payload(self.plan[0]), 'not json', '[]']:
            self.assertTrue(all(not r['success'] for r in reconcile(self.plan, text)))

    def test_process_error_preserves_text_but_rejects_scores(self):
        rows = reconcile(self.plan, self.payload(self.plan[0]), 'process_timeout')
        self.assertEqual(rows[0]['raw_text'], '文本')
        self.assertFalse(rows[0]['success'])

    def test_failed_warmup_cannot_produce_scored_warm_results(self):
        rows = reconcile(self.plan, '\n'.join(self.payload(j) for j in self.plan if j['phase'] != 'warmup'))
        self.assertTrue(all(not r['success'] for r in rows if r['phase'] == 'warm'))

    def test_slow_success_and_groups_preserved(self):
        rows = reconcile(self.plan, '\n'.join(self.payload(j, 9000 if i==10 else 100) for i,j in enumerate(self.plan)))
        summary = summarize(rows)
        self.assertEqual(summary['warm_groups']['overall']['p95_ms'], 9000)
        self.assertEqual(summary['warm_groups']['9_to_11_seconds']['independent_samples'], 1)
        self.assertIsNone(summary['warm_groups']['long']['p95_ms'])

if __name__ == '__main__': unittest.main()
