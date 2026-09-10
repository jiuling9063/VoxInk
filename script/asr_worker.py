#!/usr/bin/env python3
"""Stage-0 JSONL supervisor: one disposable model process per request."""
import argparse
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import threading
import time
import uuid
from whisper_smoke import ROOT, CACHE, verify, asset_path


class Child:
    def __init__(self, command, directory, env=None):
        self.stdout = (directory / 'stdout.jsonl').open('w+b')
        self.stderr = (directory / 'stderr.log').open('w+b')
        self.phase_emitted = False
        try:
            self.process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=self.stdout,
                                            stderr=self.stderr, start_new_session=True, env=env)
        except BaseException:
            self.close()
            raise

    def stop(self):
        # Stop the whole group before acknowledging cancellation.
        try: os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: self.process.wait(timeout=2)
        except subprocess.TimeoutExpired: pass
        try: os.killpg(self.process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        self.process.wait(timeout=5)

    def transcribing(self):
        if self.phase_emitted: return False
        # pread keeps the writer's shared file offset unchanged.
        length = os.fstat(self.stderr.fileno()).st_size
        tail = os.pread(self.stderr.fileno(), min(length, 4096), max(0, length - 4096))
        if b'VOXINK_PHASE transcribing\n' in tail:
            self.phase_emitted = True
            return True
        return False

    def result(self):
        self.stdout.seek(0)
        data = self.stdout.read(2_000_001)
        if len(data) > 2_000_000: raise ValueError('output too large')
        return json.loads(data)

    def close(self):
        self.stdout.close()
        self.stderr.close()


def serve(factory, log_dir, timeout=600, source=sys.stdin, sink=sys.stdout):
    events = queue.Queue()
    def read():
        while True:
            line = source.readline(65537)
            if not line:
                events.put(None)
                return
            if len(line) > 65536:
                events.put(None)
                return
            events.put(line)
    threading.Thread(target=read, daemon=True).start()
    def emit(value):
        sink.write(json.dumps(value, ensure_ascii=False) + '\n')
        sink.flush()
    active = None
    seen = set()
    try:
        emit(dict(type='control_ready', protocol_version=1, model_resident=False))
        while True:
            try: line = events.get(timeout=.05)
            except queue.Empty: line = ''
            if line is None: break
            if line:
                rid = None
                try:
                    request = json.loads(line)
                    if not isinstance(request, dict): raise ValueError('object required')
                    action = request.get('type')
                    rid = request.get('request_id')
                    if action == 'shutdown': break
                    if not isinstance(rid, str) or not rid or len(rid) > 128:
                        raise ValueError('invalid request id')
                    if action == 'cancel':
                        if active and active[0] == rid:
                            active[1].stop(); active[1].close(); active = None
                            emit(dict(type='cancelled', request_id=rid))
                        else: emit(dict(type='error', request_id=rid, error_code='not_active'))
                    elif action == 'transcribe':
                        if active:
                            emit(dict(type='error', request_id=rid, error_code='busy'))
                        elif rid in seen:
                            emit(dict(type='error', request_id=rid, error_code='duplicate_request'))
                        else:
                            seen.add(rid)
                            command, inventories = factory(request)
                            for root, files in inventories: verify(root, files)
                            directory = log_dir / str(uuid.uuid4())
                            directory.mkdir(mode=0o700)
                            child = Child(command, directory, dict(os.environ, QWEN3_CACHE_DIR=str(CACHE), VOXINK_WORKER_PHASES="1"))
                            active = (rid, child, time.monotonic(), inventories)
                            emit(dict(type='started', request_id=rid, pid=child.process.pid))
                    else: raise ValueError('unknown action')
                except (ValueError, KeyError, OSError, StopIteration) as error:
                    emit(dict(type='error', request_id=rid if isinstance(rid, str) else None,
                              error_code='invalid_request_or_assets', error_type=type(error).__name__, errno=getattr(error, 'errno', None)))
            if active:
                rid, child, started, inventories = active
                if child.transcribing():
                    emit(dict(type="transcribing", request_id=rid))
                code = child.process.poll()
                if time.monotonic() - started > timeout:
                    child.stop(); child.close(); active = None
                    emit(dict(type='failed', request_id=rid, error_code='timeout'))
                elif code is not None:
                    try:
                        for root, files in inventories: verify(root, files)
                        result = child.result()
                        if code != 0 or not isinstance(result, dict) or result.get('success') is not True:
                            raise ValueError('inference failed')
                        if not isinstance(result.get('raw_text'), str) or not result['raw_text'].strip():
                            raise ValueError('empty transcript')
                        emit(dict(type='result', request_id=rid, result=result))
                    except (ValueError, OSError):
                        emit(dict(type='failed', request_id=rid, error_code='process_or_output_failed'))
                    finally:
                        child.stop(); child.close(); active = None
    finally:
        if active:
            active[1].stop(); active[1].close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--candidate', required=True)
    p.add_argument('--binary', type=Path, required=True)
    p.add_argument('--log-dir', type=Path, required=True)
    p.add_argument('--timeout', type=float, default=600)
    args = p.parse_args()
    if args.timeout <= 0: p.error('timeout must be positive')
    os.umask(0o077)
    args.log_dir.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((ROOT/'benchmark/model-manifest.json').read_text())
    candidate = next(c for c in manifest['candidates'] if c['id'] == args.candidate)
    model = candidate['model']
    samples = [json.loads(s) for s in (ROOT/'benchmark/corpus/manifest.jsonl').read_text().splitlines()]
    def factory(request):
        sample = next(s for s in samples if s['sample_id'] == request['sample_id'])
        audio = asset_path(ROOT/'benchmark/corpus', sample['audio_path'])
        import hashlib
        if hashlib.sha256(audio.read_bytes()).hexdigest() != sample['audio_sha256']:
            raise ValueError('audio mismatch')
        if args.candidate.startswith('qwen'):
            inventories = [(CACHE/'qwen3-speech/models'/model['repository'], model['files'])]
            cmd = [str(args.binary.resolve()), '--audio', str(audio), '--sample-id', sample['sample_id'],
                   '--manifest', str(ROOT/'benchmark/model-manifest.json')]
        else:
            token = next(t for t in json.loads((ROOT/'benchmark/whisper-tokenizers.json').read_text())['tokenizers'] if t['candidate_id']==args.candidate)
            inventories = [(CACHE/'whisper-models'/model['revision'], model['files']),
                           (CACHE/'tokenizers'/token['revision'], token['files'])]
            cmd = [str(args.binary.resolve()), str(CACHE/'whisper-models'/model['revision']/model['resolved_folder']),
                   str(CACHE/'tokenizers'/token['revision']), str(audio)]
        return ['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', *cmd], inventories
    serve(factory, args.log_dir, args.timeout)

if __name__ == '__main__': main()
