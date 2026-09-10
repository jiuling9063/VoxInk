#!/usr/bin/env python3
"""Local development checks for speech presence, not transcription accuracy."""
import argparse
import array
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import subprocess
import sys
import wave


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_audio(path, samples):
    data = array.array("h", samples)
    if sys.byteorder != "little":
        data.byteswap()
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(16000)
        stream.writeframes(data.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checker", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    root = Path(__file__).resolve().parents[1]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    cases = []
    for index in range(1, 4):
        source = root / f"benchmark/corpus/audio/SMOKE-00{index}.wav"
        with wave.open(str(source), "rb") as stream:
            if (stream.getframerate(), stream.getnchannels(), stream.getsampwidth()) != (16000, 1, 2):
                raise RuntimeError("Expected prepared 16 kHz mono PCM16 development samples")
            samples = array.array("h", stream.readframes(stream.getnframes()))
            if sys.byteorder != "little":
                samples.byteswap()
        cases.append((source, True))
        for scale in (0.01, 0.001):
            target = out / f"SMOKE-00{index}-gain-{scale}.wav"
            write_audio(target, (int(value * scale) for value in samples))
            cases.append((target, True))
    # A 350 ms excerpt from known speech exercises short/head/tail coverage.
    count = 5600
    start = max(range(0, len(samples) - count, 800), key=lambda p: sum(value * value for value in samples[p:p + count]))
    voice = list(samples[start:start + count])
    rng = random.Random(12345)
    generated = [
        ("short-voice", voice, True),
        ("tail-voice", [0] * 48000 + voice, True),
        ("head-voice", voice + [0] * 48000, True),
        ("silence", [0] * 48000, False),
        ("white-noise", [rng.randint(-3000, 3000) for _ in range(48000)], False),
        ("tone", [int(4000 * math.sin(2 * math.pi * 440 * i / 16000)) for i in range(48000)], False),
        ("clicks", [10000 if i % 4000 == 0 else 0 for i in range(48000)], False),
        ("short-noise", [rng.randint(-20, 20) for _ in range(5600)], False),
    ]
    for name, values, expected in generated:
        path = out / (name + ".wav")
        write_audio(path, values)
        cases.append((path, expected))
    cases.append((root / "app/Tests/VoxInkCoreTests/Fixtures/noise-regression.wav", False))
    before = {str(path): digest(path) for path, _ in cases}
    checker = args.checker.resolve(strict=True)
    with (out / "results.jsonl").open("x") as stdout, (out / "checker.log").open("x") as stderr:
        subprocess.run(["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)",
                        str(checker), *(str(path) for path, _ in cases)], stdout=stdout, stderr=stderr,
                       timeout=120, check=True)
    rows = [json.loads(line) for line in (out / "results.jsonl").read_text().splitlines()]
    if len(rows) != len(cases):
        raise RuntimeError("Unexpected result count")
    for row, (path, expected) in zip(rows, cases):
        if row["sample"] != path.name or row["assessment"]["hasSpeech"] != expected:
            raise RuntimeError(f"Speech presence mismatch: {path.name}")
        if digest(path) != before[str(path)]:
            raise RuntimeError("Analysis changed an input file")
    summary = dict(passed=len(rows), classifier="SoundAnalysis version1", macos=platform.mac_ver()[0],
                   checker_sha256=digest(checker), input_sha256=before, files_unchanged=True,
                   minimum_ms=min(row["milliseconds"] for row in rows),
                   maximum_ms=max(row["milliseconds"] for row in rows),
                   scope="Development speech-presence checks; gain reduction is not real whispering")
    (out / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: value for key, value in summary.items() if key != "input_sha256"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
