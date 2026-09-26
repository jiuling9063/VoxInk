import contextlib
import copy
import json
import os
from pathlib import Path
import sys
import time

from check_polish_model import digest
from polish_guard import clean_disfluencies, messages, validate, multilingual_messages, validate_multilingual


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
    return load(str(directory), tokenizer_config={"trust_remote_code": False, "local_files_only": True})


class SystemPromptCache:
    """Keep only public editing instructions; never retain a dictation's KV state."""

    def __init__(self, model, tokenizer):
        self.model = model
        self.tokenizer = tokenizer
        self.tokens = []
        self.cache = None

    def prepare(self, system_message):
        import mlx.core as mx
        from mlx_lm.models.cache import make_prompt_cache

        tokens = self.tokenizer.apply_chat_template(
            [system_message], tokenize=True, add_generation_prompt=False, enable_thinking=False)
        if tokens == self.tokens and self.cache is not None:
            return
        cache = make_prompt_cache(self.model)
        # Prefill in bounded chunks, as MLX generation does for long prompts.
        for start in range(0, len(tokens), 512):
            self.model(mx.array([tokens[start:start + 512]]), cache=cache)
            mx.eval([layer.state for layer in cache])
        self.tokens, self.cache = tokens, cache

    def for_request(self, prompt_messages):
        self.prepare(prompt_messages[0])
        tokens = self.tokenizer.apply_chat_template(
            prompt_messages, tokenize=True, add_generation_prompt=True, enable_thinking=False)
        if not self.tokens or tokens[:len(self.tokens)] != self.tokens or len(tokens) <= len(self.tokens):
            return tokens, {}
        # Generation mutates its cache. A private copy prevents prior input from
        # leaking into later requests or remaining in the resident system cache.
        return tokens[len(self.tokens):], {"prompt_cache": copy.deepcopy(self.cache)}


def polish(source, model, tokenizer, max_tokens=1024, language="zh", prompt_cache=None):
    if not isinstance(source, str) or not source.strip() or len(source) > 2000:
        raise ValueError('Invalid input')
    from mlx_lm import stream_generate
    from mlx_lm.sample_utils import make_sampler
    started = time.monotonic()
    if language not in {"auto", "zh", "yue", "en", "ja", "ko"}:
        raise ValueError("Unsupported language")
    cleaned = clean_disfluencies(source) if language == "zh" else source
    prompt_messages = messages(cleaned or source) if language == "zh" else multilingual_messages(source, language)
    if prompt_cache is None:
        prompt = tokenizer.apply_chat_template(prompt_messages, tokenize=False, add_generation_prompt=True,
                                               enable_thinking=False)
        options = {}
    else:
        prompt, options = prompt_cache.for_request(prompt_messages)
    output = ''
    last = None
    for response in stream_generate(model, tokenizer, prompt, max_tokens=max_tokens, sampler=make_sampler(temp=0), **options):
        output += response.text
        last = response
    validator = validate if language == "zh" else validate_multilingual
    result = validator(source, output, last.finish_reason if last else None)
    result['generationSeconds'] = time.monotonic() - started
    return result


def serve(model, tokenizer, load_seconds, input_stream, output_stream, prompt_cache=None):
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
                result = polish(request['text'], model, tokenizer, limit, language=request.get('language', 'zh'),
                                prompt_cache=prompt_cache)
            emit(dict(request_id=request_id, result=result))
        except Exception:
            emit(dict(request_id=request_id, error_code='polish_failed'))


def run():
    directory = Path(sys.argv[1])
    started = time.monotonic()
    with contextlib.redirect_stdout(sys.stderr):
        model, tokenizer = load_model(directory)
    if '--resident' in sys.argv[2:]:
        with contextlib.redirect_stdout(sys.stderr):
            prompt_cache = SystemPromptCache(model, tokenizer)
            prompt_cache.prepare(messages("")[0])
        serve(model, tokenizer, time.monotonic() - started, sys.stdin.buffer, sys.stdout, prompt_cache)
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
