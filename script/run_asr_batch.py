#!/usr/bin/env python3
"""Development-only same-process cold/warm ASR comparison."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import subprocess
import uuid
import wave
from whisper_smoke import ROOT, CACHE, asset_path, verify


def make_plan(samples, seed):
    if not samples or len({s['sample_id'] for s in samples}) != len(samples):
        raise ValueError('empty or duplicate samples')
    rng = random.Random(seed)
    first = rng.choice(samples)
    jobs = []
    for phase, round_index in [('cold', 0), ('warmup', 0), ('warm', 1), ('warm', 2), ('warm', 3)]:
        ordered = [first] if phase != 'warm' else list(samples)
        if phase == 'warm': rng.shuffle(ordered)
        for sample in ordered:
            jobs.append(dict(sample, request_id=f'request-{len(jobs):04}', phase=phase, round=round_index))
    return jobs


def reconcile(jobs, text, process_error=None):
    received = {}
    protocol_error = False
    for line in text.splitlines():
        try:
            item = json.loads(line)
            key = item['request_id']
            if key in received or key not in {j['request_id'] for j in jobs}: raise ValueError('id')
            received[key] = item
        except (ValueError, KeyError, TypeError): protocol_error = True
    rows = []
    for job in jobs:
        item = received.get(job['request_id'], {})
        result = item.get('result')
        valid = (isinstance(result, dict) and isinstance(result.get('raw_text'), str)
                 and isinstance(result.get('success'), bool)
                 and all(type(result.get(k)) is int and result[k] >= 0
                         for k in ('load_ms', 'transcribe_ms', 'peak_rss_bytes')))
        success = bool(valid and result['success'] and result['raw_text'].strip())
        error = process_error or ('invalid_protocol' if protocol_error else None)
        error = error or item.get('error_code') or (None if success else 'missing_or_failed_result')
        row = dict(job, raw_text=result.get('raw_text') if isinstance(result, dict) else None,
                   success=success and error is None, error_code=error, resample_ms=0)
        for k in ('load_ms', 'transcribe_ms', 'peak_rss_bytes'):
            row[k] = result[k] if valid else None
        row['cold_transcribe_ms'] = row['transcribe_ms'] if row['phase'] == 'cold' else None
        row['warm_transcribe_ms'] = row['transcribe_ms'] if row['phase'] == 'warm' else None
        rows.append(row)
    if any(not r['success'] for r in rows if r['phase'] in ('cold', 'warmup')):
        for row in rows:
            if row['phase'] == 'warm':
                row['success'] = False
                row['error_code'] = row['error_code'] or 'warmup_not_completed'
    return rows


def percentile(values, q):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * q) - 1)] if values else None


def summarize(rows):
    warm = [r for r in rows if r['phase'] == 'warm']
    def group(items):
        times = [r['transcribe_ms'] for r in items if r['success']]
        return dict(attempts=len(items), failures=sum(not r['success'] for r in items),
                    independent_samples=len({r['sample_id'] for r in items}),
                    p50_ms=percentile(times, .5), p95_ms=percentile(times, .95))
    groups = dict(overall=group(warm))
    for name, condition in [('short', lambda ms: ms <= 10000),
                            ('medium', lambda ms: 10000 < ms < 30000),
                            ('long', lambda ms: 30000 <= ms <= 60000),
                            ('9_to_11_seconds', lambda ms: 9000 <= ms <= 11000)]:
        groups[name] = group([r for r in warm if condition(r['duration_ms'])])
    per_sample = {}
    for sid in sorted({r['sample_id'] for r in warm}):
        items = [r for r in warm if r['sample_id'] == sid]
        times = [r['transcribe_ms'] for r in items if r['success']]
        per_sample[sid] = dict(group(items), min_ms=min(times) if times else None,
                               max_ms=max(times) if times else None)
    return dict(status='DEVELOPMENT_ONLY_NOT_ACCEPTANCE', percentile_method='nearest_rank',
                warm_groups=groups, per_sample=per_sample,
                cold=[r['transcribe_ms'] for r in rows if r['phase'] == 'cold' and r['success']])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qwen-binary', type=Path, required=True)
    parser.add_argument('--whisper-binary', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=20260908)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.output.mkdir(parents=True, exist_ok=False)
    manifest_path = ROOT / 'benchmark/model-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    tokens = json.loads((ROOT / 'benchmark/whisper-tokenizers.json').read_text())['tokenizers']
    corpus = ROOT / 'benchmark/corpus'
    samples = [json.loads(line) for line in (corpus / 'manifest.jsonl').read_text().splitlines()]
    for sample in samples:
        audio = asset_path(corpus, sample['audio_path'])
        if hashlib.sha256(audio.read_bytes()).hexdigest() != sample['audio_sha256']:
            raise ValueError('audio hash mismatch')
        with wave.open(str(audio)) as wav:
            if (wav.getnchannels(), wav.getframerate(), wav.getsampwidth()) != (1, 16000, 2):
                raise ValueError('noncanonical audio')
            if round(wav.getnframes() / 16000 * 1000) != sample['duration_ms']:
                raise ValueError('audio duration mismatch')
        sample['audio_path'] = str(audio)
    jobs = make_plan(samples, args.seed)
    plan = args.output / 'plan.json'
    plan.write_text(json.dumps(jobs, ensure_ascii=False, indent=2))
    metadata = dict(run_id=str(uuid.uuid4()), seed=args.seed, build='release', device=platform.platform(),
                    cpu=subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
                    memory_bytes=int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
                    power=subprocess.check_output(['pmset', '-g', 'batt'], text=True),
                    thermal='not_measured', background_load='not_controlled',
                    independent_samples=len(samples), model_manifest_sha256=hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                    input_files_sha256={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                        for p in [ROOT/'benchmark/whisper-tokenizers.json',
                                                  ROOT/'benchmark/qwen-smoke/Package.resolved',
                                                  ROOT/'benchmark/whisper-smoke/Package.resolved']},
                    binaries={k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in [('qwen',args.qwen_binary),('whisper',args.whisper_binary)]})
    (args.output / 'metadata.json').write_text(json.dumps(metadata, indent=2))
    summaries = {}
    for candidate in manifest['candidates']:
        model = candidate['model']; engine = candidate['id']
        if engine.startswith('qwen'):
            root = CACHE / 'qwen3-speech/models' / model['repository']
            inventories = [(root, model['files'])]
            cmd = [str(args.qwen_binary.resolve()), '--batch-plan', str(plan.resolve()), '--manifest', str(manifest_path)]
        else:
            root = CACHE / 'whisper-models' / model['revision']
            token = next(t for t in tokens if t['candidate_id'] == engine)
            tokroot = CACHE / 'tokenizers' / token['revision']
            inventories = [(root, model['files']), (tokroot, token['files'])]
            cmd = [str(args.whisper_binary.resolve()), str(root/model['resolved_folder']), str(tokroot), '--batch-plan', str(plan.resolve())]
        raw = b''; error = None
        try:
            for folder, files in inventories: verify(folder, files)
            with (args.output / f'{engine}.stderr.log').open('wb') as stderr:
                try:
                    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=stderr, timeout=1800,
                                          env=dict(os.environ, QWEN3_CACHE_DIR=str(CACHE)))
                    raw = proc.stdout
                    if proc.returncode: error = f'process_exit_{proc.returncode}'
                except subprocess.TimeoutExpired as exc:
                    raw = exc.stdout or b''; error = 'process_timeout'
            for folder, files in inventories: verify(folder, files)
        except Exception as exc:
            error = 'verification_or_launch_failed'
            (args.output / f'{engine}.failure.txt').write_text(type(exc).__name__)
        (args.output / f'{engine}.raw.jsonl').write_bytes(raw)
        rows = reconcile(jobs, raw.decode('utf-8', errors='replace'), error)
        for row in rows:
            row.update(engine=engine, engine_version=candidate['engine']['source_revision'],
                       model_revision=model['revision'], run_id=metadata['run_id'],
                       tokenizer_revision=token['revision'] if not engine.startswith('qwen') else None)
        (args.output / f'{engine}.jsonl').write_text(''.join(json.dumps(r, ensure_ascii=False)+'\n' for r in rows))
        summaries[engine] = summarize(rows)
        print(engine, summaries[engine]['warm_groups']['overall'], flush=True)
    (args.output / 'summary.json').write_text(json.dumps(summaries, indent=2))
    if any(s['warm_groups']['overall']['failures'] for s in summaries.values()):
        raise SystemExit(1)

if __name__ == '__main__': main()
