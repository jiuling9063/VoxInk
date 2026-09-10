#!/usr/bin/env python3
"""Pinned local WhisperKit smoke. Downloads weights only with --prepare."""
import argparse
import hashlib
import json
import platform
from pathlib import Path, PurePosixPath
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path.home() / 'Library/Caches/VoxInkBenchmark'


def asset_path(root, name):
    parts = PurePosixPath(name).parts
    if not parts or name.startswith('/') or '..' in parts or '\\' in name:
        raise ValueError('unsafe asset path')
    path = root.joinpath(*parts)
    if any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError('symlink asset path')
    return path


def verify(root, files):
    if not files or len({f['path'] for f in files}) != len(files):
        raise ValueError('empty or duplicate asset inventory')
    for f in files:
        path = asset_path(root, f['path'])
        if not path.is_file() or path.stat().st_size != f['size_bytes']:
            raise ValueError('missing/wrong size: ' + f['path'])
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != f['sha256']:
            raise ValueError('wrong hash: ' + f['path'])


def prepare(model, root):
    for f in model['files']:
        try:
            verify(root, [f])
            continue
        except ValueError:
            pass
        dest = asset_path(root, f['path'])
        dest.parent.mkdir(parents=True, exist_ok=True)
        part = dest.with_name(dest.name + '.part')
        if part.is_symlink():
            raise ValueError('symlink staging path')
        url = f"https://huggingface.co/{model['repository']}/resolve/{model['revision']}/{f['path']}"
        print('Downloading ' + f['path'], file=sys.stderr, flush=True)
        result = subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error',
                                 '--retry', '2', '--max-time', '600', '--output', str(part), url], capture_output=True)
        if result.returncode:
            raise RuntimeError('download failed: ' + f['path'])
        verify(part.parent, [dict(f, path=part.name)])
        part.replace(dest)
    verify(root, model['files'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', choices=['whisperkit-large-v3-turbo', 'whisperkit-medium'])
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--sample', default='SMOKE-001')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'benchmark/model-manifest.json').read_text())
    candidate = next(c for c in manifest['candidates'] if c['id'] == args.candidate)
    model = candidate['model']
    root = CACHE / 'whisper-models' / model['revision']
    tokenizer = next(t for t in json.loads((ROOT / 'benchmark/whisper-tokenizers.json').read_text())['tokenizers'] if t['candidate_id'] == args.candidate)
    tokroot = CACHE / 'tokenizers' / tokenizer['revision']
    if args.prepare:
        prepare(model, root)
        prepare(tokenizer, tokroot)
        return
    if args.binary is None:
        parser.error('--binary is required for inference')
    corpus = ROOT / 'benchmark/corpus'
    sample = next(s for s in map(json.loads, (corpus / 'manifest.jsonl').read_text().splitlines()) if s['sample_id'] == args.sample)
    audio = asset_path(corpus, sample['audio_path'])
    if hashlib.sha256(audio.read_bytes()).hexdigest() != sample['audio_sha256']:
        raise ValueError('audio hash mismatch')
    row = dict(run_id=str(uuid.uuid4()), sample_id=args.sample, engine=args.candidate,
               engine_version=candidate['engine']['source_revision'], model_revision=model['revision'],
               tokenizer_revision=tokenizer['revision'], language='zh', audio_sha256=sample['audio_sha256'],
               device_profile=dict(os=platform.mac_ver()[0], architecture=platform.machine(),
                                   cpu=subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
                                   memory_bytes=int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True))),
               duration_ms=sample['duration_ms'], measurement='debug_new_process_smoke',
               success=False, raw_text=None, error_code=None)
    try:
        verify(root, model['files'])
        verify(tokroot, tokenizer['files'])
        result = subprocess.run([str(args.binary.resolve()), str(root / model['resolved_folder']), str(tokroot), str(audio)],
                                stdout=subprocess.PIPE, timeout=600)
        if result.returncode:
            raise RuntimeError('inference_exit_' + str(result.returncode))
        payload = json.loads(result.stdout)
        verify(root, model['files'])
        verify(tokroot, tokenizer['files'])
        row.update(payload)
        if not row['success']:
            row['error_code'] = 'empty_transcript'
    except Exception as error:
        row['error_code'] = str(error)
    print(json.dumps(row, ensure_ascii=False))
    if not row['success']:
        sys.exit(1)


if __name__ == '__main__':
    main()
