#!/usr/bin/env python3
"""Real-model stage-0 process lifecycle checks. No transcript in summary."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import threading
import time
from whisper_smoke import ROOT


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--qwen-binary',type=Path,required=True)
    p.add_argument('--whisper-binary',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--candidate',choices=['qwen3-asr-0.6b-mlx-4bit','whisperkit-large-v3-turbo','whisperkit-medium'])
    args=p.parse_args();os.umask(0o077);args.output.mkdir(parents=True,exist_ok=False)
    policy='(version 1)(allow default)(deny network*)'
    probe=['/usr/bin/python3','-c','import socket; s=socket.socket(); s.bind(("127.0.0.1",0))']
    baseline=subprocess.run(probe,capture_output=True)
    blocked=subprocess.run(['/usr/bin/sandbox-exec','-p',policy,*probe],capture_output=True)
    assert baseline.returncode==0 and blocked.returncode!=0 and b'Operation not permitted' in blocked.stderr
    summary={'network_control':{'baseline_exit':baseline.returncode,'sandbox_exit':blocked.returncode,'policy':policy},'candidates':{}}
    for engine in ([args.candidate] if args.candidate else ['qwen3-asr-0.6b-mlx-4bit','whisperkit-large-v3-turbo','whisperkit-medium']):
        binary=args.qwen_binary if engine.startswith('qwen') else args.whisper_binary
        directory=args.output/engine;directory.mkdir()
        stderr=(directory/'supervisor.stderr.log').open('w')
        proc=subprocess.Popen([sys.executable,str(ROOT/'script/asr_worker.py'),'--candidate',engine,
                               '--binary',str(binary.resolve()),'--log-dir',str(directory/'jobs')],
                              stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr,text=True)
        events=queue.Queue()
        def read(stream=proc.stdout, target=events):
            for line in stream: target.put(json.loads(line))
        reader=threading.Thread(target=read,daemon=True);reader.start()
        records=[]
        def event(kind):
            item=events.get(timeout=650)
            while item['type']=='transcribing' and kind!='transcribing':
                records.append(item)
                item=events.get(timeout=650)
            # Persist protocol events, with transcript removed from the public summary.
            records.append(item)
            if item['type']!=kind: raise RuntimeError(f"expected {kind}, got {item['type']}")
            return item
        def send(**item): proc.stdin.write(json.dumps(item)+'\n');proc.stdin.flush()
        def start(rid):
            send(type='transcribe',request_id=rid,sample_id='SMOKE-001')
            return event('started')['pid']
        def dead(pid):
            try: os.kill(pid,0)
            except ProcessLookupError: return True
            return False
        status={}
        try:
            event('control_ready')
            pid=start('cancel-during-startup');t=time.monotonic()
            send(type='cancel',request_id='cancel-during-startup');event('cancelled')
            assert dead(pid);status['cancel_startup_ms']=round((time.monotonic()-t)*1000)
            pid=start('cancel-during-inference');event('transcribing');t=time.monotonic()
            send(type='cancel',request_id='cancel-during-inference');event('cancelled')
            assert dead(pid);status['cancel_inference_ms']=round((time.monotonic()-t)*1000)
            start('after-cancel');result=event('result');status['offline_transcribe_success']=result['result']['success']
            pid=start('forced-crash');event('transcribing');os.killpg(pid,signal.SIGKILL);event('failed')
            start('after-crash');event('result');status['restart_after_crash']=True
            pid=start('parent-disconnect');event('transcribing');proc.stdin.close();proc.wait(timeout=15)
            assert dead(pid);status['parent_disconnect_cleanup']=True
            status['binary_sha256']=hashlib.sha256(binary.read_bytes()).hexdigest()
            status['success']=True
        except Exception as exc:
            status.update(success=False,error=type(exc).__name__+': '+str(exc))
        finally:
            if not proc.stdin.closed: proc.stdin.close()
            try: proc.wait(timeout=15)
            except subprocess.TimeoutExpired: proc.kill();proc.wait()
            reader.join(timeout=2);proc.stdout.close();stderr.close()
            (directory/'events.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
            summary['candidates'][engine]=status
            (args.output/'summary.json').write_text(json.dumps(summary,indent=2))
            print(engine,status,flush=True)
    if not all(s['success'] for s in summary['candidates'].values()):raise SystemExit(1)

if __name__=='__main__':main()
