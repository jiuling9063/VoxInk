import contextlib
import json
import os
from pathlib import Path
import sys

from check_polish_model import digest
from polish_guard import messages, validate


def run():
    os.environ["HF_HUB_OFFLINE"] = "1"
    source = json.loads(sys.stdin.buffer.read(16385))
    if not isinstance(source, str) or not source.strip() or len(source) > 2000:
        raise ValueError("Invalid input")
    directory = Path(sys.argv[1])
    manifest = json.loads((directory / "verified.json").read_text())
    for entry in manifest:
        path = (directory / entry["file"]).resolve()
        if not path.is_relative_to(directory.resolve()) or digest(path, "sha256") != entry["sha256"]:
            raise ValueError("Model verification failed")
    with contextlib.redirect_stdout(sys.stderr):
        from mlx_lm import load, stream_generate
        from mlx_lm.sample_utils import make_sampler
        model, tokenizer = load(str(directory))
        prompt = tokenizer.apply_chat_template(messages(source), tokenize=False, add_generation_prompt=True)
        output = ""
        last = None
        for response in stream_generate(model, tokenizer, prompt, max_tokens=1024, sampler=make_sampler(temp=0)):
            output += response.text
            last = response
        result = validate(source, output, last.finish_reason if last else None)
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    try:
        run()
    except Exception:
        sys.exit(1)
