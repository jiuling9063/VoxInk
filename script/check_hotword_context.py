#!/usr/bin/env python3
"""Reproduce context bias checks locally; a completed run is not a quality pass."""
import argparse
import array
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import wave


def write_private(path, text):
    with path.open("x") as stream:
        path.chmod(0o600)
        stream.write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--cache-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    worker = args.worker.resolve(strict=True)
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False, mode=0o700)
    rng = random.Random(20260909)
    for name, values in [("silence", [0] * 48000),
                         ("low-noise", [rng.randint(-20, 20) for _ in range(48000)])]:
        path = out / (name + ".wav")
        with wave.open(str(path), "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(16000)
            samples = array.array("h", values)
            if sys.byteorder != "little":
                samples.byteswap()
            audio.writeframes(samples.tobytes())
        path.chmod(0o600)

    samples = [(f"SMOKE-00{i}", root / f"benchmark/corpus/audio/SMOKE-00{i}.wav") for i in range(1, 4)]
    samples += [(name, out / (name + ".wav")) for name in ("silence", "low-noise")]
    variants = [("baseline", []), ("short", ["紫藤星云研究所", "榛果电报码"]),
                ("budget", [f"紫藤星云研究所{i}" for i in range(32)])]
    jobs = [dict(request_id=f"{sample}-{variant}", sample_id=sample,
                 audio_path=str(path.resolve(strict=True)), hotwords=words)
            for sample, path in samples for variant, words in variants]
    write_private(out / "plan.json", json.dumps(jobs, ensure_ascii=False, indent=2))
    environment = os.environ.copy()
    environment["QWEN3_CACHE_DIR"] = str(args.cache_root.resolve(strict=True))
    command = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)",
               str(worker), "--batch-plan", str(out / "plan.json"), "--experimental-hotwords",
               "--manifest", str(root / "benchmark/model-manifest.json")]
    write_private(out / "responses.jsonl", "")
    write_private(out / "worker.log", "")
    with (out / "responses.jsonl").open("w") as stdout, (out / "worker.log").open("w") as stderr:
        subprocess.run(command, env=environment, stdout=stdout, stderr=stderr, timeout=240, check=True)
    rows = [json.loads(line) for line in (out / "responses.jsonl").read_text().splitlines()]
    if [row["request_id"] for row in rows] != [job["request_id"] for job in jobs]:
        raise RuntimeError("Response IDs or row count did not match plan")
    summaries = []
    for row, job in zip(rows, jobs):
        result = row.get("result")
        if not result or row.get("error_code"):
            raise RuntimeError("Worker returned an inference or request error")
        if not 0 <= result["context_tokens"] <= 256:
            raise RuntimeError("Context token budget exceeded")
        text = result["raw_text"]
        summaries.append(dict(request_id=row["request_id"], output_chars=len(text),
                              output_sha256=hashlib.sha256(text.encode()).hexdigest(),
                              context_tokens=result["context_tokens"], hotword_count=result["hotword_count"],
                              transcribe_ms=result["transcribe_ms"], peak_rss_bytes=result["peak_rss_bytes"],
                              contains_test_hint=any(word in text for word in job["hotwords"])))
    negative = [row for row in summaries if row["request_id"].startswith(("silence-", "low-noise-"))]
    summary = dict(worker_sha256=hashlib.sha256(worker.read_bytes()).hexdigest(),
                   completed_requests=len(rows), network_denied=True,
                   negative_no_text_gate_passed=all(row["output_chars"] == 0 for row in negative),
                   rows=summaries)
    write_private(out / "summary.json", json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: value for key, value in summary.items() if key != "rows"}))


if __name__ == "__main__":
    main()
