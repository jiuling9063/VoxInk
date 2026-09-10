import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time
import unittest

ROOT=Path(__file__).resolve().parents[2]

class ResidentIOChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build=tempfile.TemporaryDirectory()
        cls.binary=Path(cls.build.name)/'resident-io'
        env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer')
        subprocess.run(['xcrun','swiftc','-parse-as-library',str(ROOT/'benchmark/worker-protocol/Sources/VoxInkWorkerProtocol/ResidentProtocol.swift'),
                        str(ROOT/'benchmark/worker-protocol/Checks/ResidentIO.swift'),'-o',str(cls.binary)],check=True,env=env,capture_output=True)

    @classmethod
    def tearDownClass(cls):cls.build.cleanup()

    def setUp(self):
        self.proc=subprocess.Popen([str(self.binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,env=dict(os.environ,VOXINK_EXIT_DELAY="1"))
        self.addCleanup(self.cleanup)
        self.lines=queue.Queue()
        def read():
            for line in self.proc.stdout:self.lines.put(line)
        self.reader=threading.Thread(target=read,daemon=True);self.reader.start()

    def cleanup(self):
        if not self.proc.stdin.closed:self.proc.stdin.close()
        try:self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait()
        self.reader.join(timeout=1);self.proc.stdout.close()

    def frame(self,sample='S1'):
        return (json.dumps(dict(request_id='r1',sample_id=sample,audio_path='/tmp/语音.wav'),ensure_ascii=False)+'\n').encode()

    def test_short_request_does_not_wait_for_4096_bytes(self):
        self.proc.stdin.write(self.frame());self.proc.stdin.flush()
        self.assertEqual(self.lines.get(timeout=3),b'r1\n')

    def test_split_unicode_frame(self):
        data=self.frame()
        split=data.index('语'.encode())+1
        for part in (data[:split],data[split:]):self.proc.stdin.write(part);self.proc.stdin.flush()
        self.assertEqual(self.lines.get(timeout=3),b'r1\n')

    def test_oversized_unterminated_frame_exits(self):
        self.proc.stdin.write(b'x'*65537);self.proc.stdin.flush()
        self.proc.wait(timeout=3);self.assertNotEqual(self.proc.returncode,0)

    def test_invalid_json_exits(self):
        self.proc.stdin.write(b'bad json\n');self.proc.stdin.flush()
        self.proc.wait(timeout=3);self.assertNotEqual(self.proc.returncode,0)

    def test_duplicate_request_exits(self):
        self.proc.stdin.write(self.frame());self.proc.stdin.flush()
        self.assertEqual(self.lines.get(timeout=3),b'r1\n')
        self.proc.stdin.write(self.frame());self.proc.stdin.flush()
        self.proc.wait(timeout=3);self.assertNotEqual(self.proc.returncode,0)

    def test_queue_overflow_exits(self):
        self.proc.stdin.write(self.frame('slow'));self.proc.stdin.flush()
        self.assertEqual(self.lines.get(timeout=3),b'r1\n')
        self.proc.stdin.write(self.frame()*17);self.proc.stdin.flush()
        self.proc.wait(timeout=3);self.assertNotEqual(self.proc.returncode,0)

    def test_owner_eof_stops_busy_consumer(self):
        self.proc.stdin.write(self.frame('slow'));self.proc.stdin.flush()
        self.assertEqual(self.lines.get(timeout=3),b'r1\n')
        start=time.monotonic();self.proc.stdin.close();self.proc.wait(timeout=3)
        self.assertEqual(self.proc.returncode,0)
        self.assertLess(time.monotonic()-start,1, 'owner EOF must not wait for engine atexit hooks')

if __name__=='__main__':unittest.main()
