import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]

class WorkerChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        code = '''import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from asr_worker import serve

def factory(r):
    code = "import time; time.sleep(30)" if r.get('sample_id') == 'slow' else "import json; print(json.dumps(dict(success=True, raw_text='ok')))"
    if r.get('sample_id') == 'crash': code = 'import os; os._exit(4)'
    if r.get('sample_id') == 'inference': code = \"import sys,time; print('VOXINK_PHASE transcribing',file=sys.stderr,flush=True); time.sleep(30)\"
    return [sys.executable, '-c', code], []
serve(factory, Path(sys.argv[2]), timeout=1)
'''
        self.proc = subprocess.Popen([sys.executable, '-c', code, str(ROOT), self.temp.name], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.cleanup)
        self.events = queue.Queue()
        def read():
            for line in self.proc.stdout: self.events.put(json.loads(line))
        threading.Thread(target=read, daemon=True).start()
        self.assertEqual(self.event()['type'], 'control_ready')

    def cleanup(self):
        if self.proc.stdin and not self.proc.stdin.closed: self.proc.stdin.close()
        try: self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired: self.proc.kill(); self.proc.wait()
        self.proc.stdout.close(); self.proc.stderr.close()

    def send(self, **request):
        self.proc.stdin.write(json.dumps(request)+'\n');self.proc.stdin.flush()

    def event(self): return self.events.get(timeout=10)

    def start(self, rid='r', sample='slow'):
        self.send(type='transcribe', request_id=rid, sample_id=sample)
        item=self.event();self.assertEqual(item['type'],'started');return item['pid']

    def assert_dead(self,pid):
        with self.assertRaises(ProcessLookupError): os.kill(pid,0)

    def test_cancel_then_new_request(self):
        pid=self.start()
        self.send(type='cancel',request_id='r')
        self.assertEqual(self.event()['type'],'cancelled');self.assert_dead(pid)
        self.start('next','good');self.assertEqual(self.event()['type'],'result')

    def test_inference_phase_then_cancel_has_no_late_result(self):
        pid=self.start('inflight','inference')
        self.assertEqual(self.event()['type'],'transcribing')
        self.send(type='cancel',request_id='inflight')
        self.assertEqual(self.event()['type'],'cancelled');self.assert_dead(pid)
        self.start('fresh','good')
        item=self.event();self.assertEqual(item['type'],'result');self.assertEqual(item['request_id'],'fresh')

    def test_parent_disconnect_cleans_child(self):
        pid=self.start();self.proc.stdin.close();self.proc.wait(timeout=10);self.assert_dead(pid)

    def test_crash_then_new_request(self):
        self.start('bad','crash');self.assertEqual(self.event()['type'],'failed')
        self.start('next','good');self.assertEqual(self.event()['type'],'result')

    def test_timeout(self):
        pid=self.start();self.assertEqual(self.event()['error_code'],'timeout');self.assert_dead(pid)

    def test_busy_and_duplicate(self):
        self.start()
        self.send(type='transcribe',request_id='other',sample_id='good')
        self.assertEqual(self.event()['error_code'],'busy')
        self.send(type='cancel',request_id='r');self.assertEqual(self.event()['type'],'cancelled')
        self.send(type='transcribe',request_id='r',sample_id='good')
        self.assertEqual(self.event()['error_code'],'duplicate_request')

    def test_malformed_json_does_not_crash(self):
        self.proc.stdin.write('bad json\n');self.proc.stdin.flush()
        self.assertEqual(self.event()['type'],'error')
        self.start('next','good');self.assertEqual(self.event()['type'],'result')

if __name__=='__main__':unittest.main()
