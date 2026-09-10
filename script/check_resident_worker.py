#!/usr/bin/env python3
"""Verify resident model reuse, request errors, duplicate rejection, and owner EOF."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
from whisper_smoke import ROOT, CACHE, verify


def validate_response(envelope, request_id, sample_id, *, qwen_baseline=False):
    result = envelope.get('result')
    if envelope.get('request_id') != request_id or not isinstance(result, dict):
        raise ValueError('response does not match the request')
    if result.get('sample_id') != sample_id or result.get('success') is not True:
        raise ValueError('response does not match a successful sample')
    if not isinstance(result.get('raw_text'), str) or not result['raw_text'].strip():
        raise ValueError('speech sample returned empty text')
    if qwen_baseline and (result.get('output_policy') is not None
                          or result.get('context_tokens') not in (None, 0)
                          or result.get('hotword_count') not in (None, 0)):
        raise ValueError('baseline response unexpectedly used a prompt or hotwords')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qwen-binary', type=Path, required=True)
    parser.add_argument('--whisper-binary', type=Path)
    parser.add_argument('--qwen-only', action='store_true')
    parser.add_argument('--qwen-cache-root', type=Path, default=CACHE,
                        help='QWEN3_CACHE_DIR root, including qwen3-speech/models')
    parser.add_argument('--iterations', type=int, help='Number of sequential requests per engine, cycling through development samples')
    parser.add_argument('--simplified-output', action='store_true', help='Enable the App Qwen prompt; not the baseline configuration')
    parser.add_argument('--output', type=Path, required=True)
    args=parser.parse_args()
    if not args.qwen_only and args.whisper_binary is None:parser.error('--whisper-binary is required unless --qwen-only is set')
    if args.iterations is not None and args.iterations < 1:parser.error('--iterations must be positive')
    os.umask(0o077);args.output.mkdir(parents=True,exist_ok=False)
    manifest=json.loads((ROOT/'benchmark/model-manifest.json').read_text())
    tokens=json.loads((ROOT/'benchmark/whisper-tokenizers.json').read_text())['tokenizers']
    samples=[json.loads(s) for s in (ROOT/'benchmark/corpus/manifest.jsonl').read_text().splitlines()]
    if not samples:raise ValueError('development corpus is empty')
    for sample in samples:
        if hashlib.sha256((ROOT/'benchmark/corpus'/sample['audio_path']).read_bytes()).hexdigest()!=sample['audio_sha256']:
            raise ValueError('audio hash mismatch')
    summary={}
    for c in manifest['candidates']:
        if args.qwen_only and not c['id'].startswith('qwen'):continue
        engine=c['id'];model=c['model'];binary=args.qwen_binary if engine.startswith('qwen') else args.whisper_binary
        if engine.startswith('qwen'):
            inventories=[(args.qwen_cache_root/'qwen3-speech/models'/model['repository'],model['files'])]
            modelargs=['--resident','--manifest',str(ROOT/'benchmark/model-manifest.json')]
            if args.simplified_output:modelargs.append('--simplified-output')
        else:
            t=next(t for t in tokens if t['candidate_id']==engine)
            modelroot=CACHE/'whisper-models'/model['revision'];tokroot=CACHE/'tokenizers'/t['revision']
            inventories=[(modelroot,model['files']),(tokroot,t['files'])]
            modelargs=[str(modelroot/model['resolved_folder']),str(tokroot),'--resident']
        for folder,files in inventories:verify(folder,files)
        directory=args.output/engine;directory.mkdir();records=[]
        status=dict(binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),model_revision=model['revision'],
                    unique_audio_samples=len(samples),
                    output_policy='simplified_prompt_v1' if engine.startswith('qwen') and args.simplified_output else 'baseline')
        if engine.startswith('qwen'): status['model_cache_root'] = str(args.qwen_cache_root.resolve())
        def launch(suffix):
            log=directory/f'{suffix}.stderr.log'
            stderr=log.open('w')
            proc=subprocess.Popen(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary.resolve()),*modelargs],
                                  stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr,text=True,
                                  env=dict(os.environ,QWEN3_CACHE_DIR=str(args.qwen_cache_root.resolve()),VOXINK_WORKER_PHASES='1'))
            q=queue.Queue()
            def read():
                try:
                    for line in proc.stdout:q.put(json.loads(line))
                except Exception as error:q.put(error)
                finally:q.put(None)
            reader=threading.Thread(target=read,daemon=True);reader.start()
            return proc,q,stderr,log,reader
        def receive(q):
            result=q.get(timeout=180)
            if not isinstance(result,dict):raise RuntimeError('worker EOF or malformed output')
            records.append(result);return result
        def send(proc,rid,sample,path=None):
            req=dict(request_id=rid,sample_id=sample['sample_id'],audio_path=path or str(ROOT/'benchmark/corpus'/sample['audio_path']))
            proc.stdin.write(json.dumps(req)+'\n');proc.stdin.flush()
        def close(proc,stderr,reader):
            if not proc.stdin.closed:proc.stdin.close()
            try:proc.wait(timeout=10)
            except subprocess.TimeoutExpired:proc.kill();proc.wait()
            reader.join(timeout=2);proc.stdout.close();stderr.close()
        proc=q=stderr=reader=None
        try:
            proc,q,stderr,log,reader=launch('reuse')
            ready=receive(q);assert ready['type']=='ready' and ready['protocol_version']==1
            status['resident_pid']=ready['pid'];status['load_ms']=ready['load_ms']
            count=args.iterations if args.iterations is not None else len(samples)
            for n in range(count):
                sample=samples[n % len(samples)]
                send(proc,str(n),sample);result=receive(q)
                validate_response(result, str(n), sample['sample_id'],
                                  qwen_baseline=engine.startswith('qwen') and not args.simplified_output)
                assert result['result']['load_ms']==ready['load_ms'] and proc.poll() is None
                if engine.startswith('qwen') and args.simplified_output:
                    assert result['result']['output_policy']=='simplified_prompt_v1'
                if (n + 1) % 10 == 0: print(engine, f'{n + 1}/{count} responses verified', flush=True)
            status['same_process_results']=count
            send(proc,'missing',samples[0],'/voxink-intentionally-missing.wav')
            error=receive(q);assert error['request_id']=='missing' and error.get('error_code')
            send(proc,'recovered',samples[0])
            validate_response(receive(q), 'recovered', samples[0]['sample_id'],
                              qwen_baseline=engine.startswith('qwen') and not args.simplified_output)
            status['request_failure_recovery']=True
            send(proc,'recovered',samples[0]);proc.wait(timeout=10)
            assert proc.returncode!=0;status['duplicate_rejected']=True
            close(proc,stderr,reader);proc=None
            proc,q,stderr,log,reader=launch('owner-eof')
            assert receive(q)['type']=='ready'
            offset=log.stat().st_size
            send(proc,'inflight-eof',samples[-1])
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                with log.open('rb') as stream:
                    stream.seek(offset)
                    if b'VOXINK_PHASE transcribing' in stream.read():break
                time.sleep(.01)
            else:raise RuntimeError('no inference marker')
            start=time.monotonic();proc.stdin.close();proc.wait(timeout=10)
            status['owner_eof_ms']=round((time.monotonic()-start)*1000);assert proc.returncode==0
            reader.join(timeout=2)
            # EOF during inference must not publish a terminal transcription.
            leftovers=[]
            while not q.empty():leftovers.append(q.get_nowait())
            assert not any(isinstance(item,dict) and item.get('request_id')=='inflight-eof' for item in leftovers)
            status['no_late_result']=True
            for folder,files in inventories:verify(folder,files)
            status['success']=True
        except Exception as error:
            status.update(success=False,error=type(error).__name__+': '+str(error))
        finally:
            if proc is not None:close(proc,stderr,reader)
            (directory/'events.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
            summary[engine]=status;(args.output/'summary.json').write_text(json.dumps(summary,indent=2))
            print(engine,status,flush=True)
    if not all(s['success'] for s in summary.values()):raise SystemExit(1)

if __name__=='__main__':main()
