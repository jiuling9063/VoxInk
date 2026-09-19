import contextlib
import json
import os
from pathlib import Path
import sys
import time

from check_polish_model import digest
from polish_guard import clean_fillers, messages, validate


def load_model(directory):
    os.environ['HF_HUB_OFFLINE'] = '1'
    manifest = json.loads((directory / 'verified.json').read_text())
    if not isinstance(manifest, list) or not manifest:
        raise ValueError('Empty model manifest')
    for entry in manifest:
        path = (directory / entry['file']).resolve()
        if not path.is_relative_to(directory.resolve()) or digest(path, 'sha256') != entry['sha256']:
            raise ValueError('Model verification failed')
    from mlx_lm import load
    return load(str(directory))


def polish(source, model, tokenizer, max_tokens=1024):
    if not isinstance(source, str) or not source.strip() or len(source) > 2000:
        raise ValueError('Invalid input')
    from mlx_lm import stream_generate
    from mlx_lm.sample_utils import make_sampler
    started = time.monotonic()
    cleaned = clean_fillers(source)
    prompt = tokenizer.apply_chat_template(messages(cleaned or source), tokenize=False, add_generation_prompt=True,
                                           enable_thinking=False)
    output = ''
    last = None
    for response in stream_generate(model, tokenizer, prompt, max_tokens=max_tokens, sampler=make_sampler(temp=0)):
        output += response.text
        last = response
    result = validate(source, output, last.finish_reason if last else None)
    result['generationSeconds'] = time.monotonic() - started
    return result


def serve(model, tokenizer, load_seconds, input_stream, output_stream):
    def emit(value):
        print(json.dumps(value, ensure_ascii=False), file=output_stream, flush=True)
    emit(dict(type='ready', protocol_version=1, pid=os.getpid(), load_ms=load_seconds * 1000))
    while True:
        line = input_stream.readline(32769)
        if not line:
            return
        if len(line) > 32768 or not line.endswith(b'\n'):
            raise ValueError('Invalid request frame')
        request = json.loads(line)
        request_id = request['request_id']
        try:
            limit = request.get('max_tokens', 1024)
            if not isinstance(limit, int) or not 64 <= limit <= 4096:
                raise ValueError('Invalid token budget')
            with contextlib.redirect_stdout(sys.stderr):
                result = polish(request['text'], model, tokenizer, limit)
            emit(dict(request_id=request_id, result=result))
        except Exception:
            emit(dict(request_id=request_id, error_code='polish_failed'))


def run():
    directory = Path(sys.argv[1])
    started = time.monotonic()
    with contextlib.redirect_stdout(sys.stderr):
        model, tokenizer = load_model(directory)
    if '--resident' in sys.argv[2:]:
        serve(model, tokenizer, time.monotonic() - started, sys.stdin.buffer, sys.stdout)
    else:
        source = json.loads(sys.stdin.buffer.read(16385))
        with contextlib.redirect_stdout(sys.stderr):
            result = polish(source, model, tokenizer)
        print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    try:
        run()
    except Exception:
        sys.exit(1)
