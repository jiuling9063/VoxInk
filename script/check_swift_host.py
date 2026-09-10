#!/usr/bin/env python3
"""Exercise the Swift host against all pinned resident models, with asset verification."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from whisper_smoke import ROOT, CACHE, verify


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host',type=Path,required=True)
    parser.add_argument('--qwen-binary',type=Path,required=True)
    parser.add_argument('--whisper-binary',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();os.umask(0o077);args.output.mkdir(parents=True,exist_ok=False)
    manifest=json.loads((ROOT/'benchmark/model-manifest.json').read_text())
    tokens=json.loads((ROOT/'benchmark/whisper-tokenizers.json').read_text())['tokenizers']
    samples=[json.loads(line) for line in (ROOT/'benchmark/corpus/manifest.jsonl').read_text().splitlines()]
    audio=[]
    for sample in samples:
        path=ROOT/'benchmark/corpus'/sample['audio_path']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==sample['audio_sha256']
        audio.extend(['--audio',str(path)])
    summary={}
    host_hash=hashlib.sha256(args.host.read_bytes()).hexdigest()
    for candidate in manifest['candidates']:
        engine=candidate['id'];model=candidate['model']
        binary=args.qwen_binary if engine.startswith('qwen') else args.whisper_binary
        if engine.startswith('qwen'):
            modelargs=['--resident','--manifest',str(ROOT/'benchmark/model-manifest.json')]
            inventories=[(CACHE/'qwen3-speech/models'/model['repository'],model['files'])]
        else:
            token=next(t for t in tokens if t['candidate_id']==engine)
            modelroot=CACHE/'whisper-models'/model['revision'];tokroot=CACHE/'tokenizers'/token['revision']
            modelargs=[str(modelroot/model['resolved_folder']),str(tokroot),'--resident']
            inventories=[(modelroot,model['files']),(tokroot,token['files'])]
        for folder,files in inventories:verify(folder,files)
        with (args.output/f'{engine}.json').open('x') as stdout,(args.output/f'{engine}.stderr.log').open('x') as stderr:
            result=subprocess.run([str(args.host.resolve()),'--worker',str(binary.resolve()),'--model-args-json',json.dumps(modelargs),'--worker-stderr',str((args.output/f'{engine}.worker.stderr.log').resolve()),*audio],
                                  stdout=stdout,stderr=stderr,timeout=600,env=dict(os.environ,QWEN3_CACHE_DIR=str(CACHE)))
        assert result.returncode==0,engine+' host failed'
        payload=json.loads((args.output/f'{engine}.json').read_text())
        assert len(payload['results'])==len(samples)
        assert all(r['success'] and r['raw_text'].strip() and r['load_ms']==payload['load_ms'] for r in payload['results'])
        try:os.kill(payload['pid'],0)
        except ProcessLookupError:pass
        else:raise AssertionError('worker still alive after host shutdown')
        for folder,files in inventories:verify(folder,files)
        assert hashlib.sha256(args.host.read_bytes()).hexdigest()==host_hash,'host rebuilt during verification'
        summary[engine]=dict(success=True,resident_pid=payload['pid'],results=len(payload['results']),load_ms=payload['load_ms'],
                             worker_reaped=True,host_sha256=host_hash,worker_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
        (args.output/'summary.json').write_text(json.dumps(summary,indent=2));print(engine,summary[engine],flush=True)

if __name__=='__main__':main()
