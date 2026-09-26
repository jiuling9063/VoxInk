"""Offline A/B benchmark using fixed public samples, never stored dictations."""
import argparse
import json
from pathlib import Path
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'script'))
from polish_worker import load_model, polish, SystemPromptCache
from polish_guard import messages


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('model', type=Path)
    parser.add_argument('--rounds', type=int, default=3)
    args = parser.parse_args()
    started = time.monotonic()
    model, tokenizer = load_model(args.model)
    print(json.dumps({'load_seconds': time.monotonic() - started}), flush=True)
    cache = SystemPromptCache(model, tokenizer)
    started = time.monotonic()
    cache.prepare(messages('')[0])
    print(json.dumps({'system_prewarm_seconds': time.monotonic() - started,
                      'cached_tokens': len(cache.tokens)}), flush=True)
    samples = [
        ('zh', '今天呢，主要是那个在语文啊，语文的课程中呢，获得了什么呢？那个进步之星，进步之星的称号。'),
        ('zh', '我们，嗯，明天讨论这个方案，下午三点。'),
        ('zh', '请把会议安排在明天下午三点，不要修改参加人员名单。'),
        ('en', 'please keep the meeting at three tomorrow and do not change the names'),
        ('ja', '明日の会議は午後三時です。参加者の名前を変更しないでください。'),
    ]
    timings = {'baseline': [], 'cached': []}
    text_mismatches = 0
    decision_changes = 0
    acceptance_regressions = 0
    for language, source in samples:
        for round_index in range(args.rounds):
            results = {}
            modes = ['baseline', 'cached'] if round_index % 2 == 0 else ['cached', 'baseline']
            for mode in modes:
                result = polish(source, model, tokenizer, 256, language,
                                prompt_cache=cache if mode == 'cached' else None)
                results[mode] = result
                if language == 'zh':
                    timings[mode].append(result['generationSeconds'])
            equal = all(results['baseline'][key] == results['cached'][key] for key in ['accepted', 'text', 'reason'])
            text_mismatches += results['baseline']['text'] != results['cached']['text']
            decision_changes += any(results['baseline'][key] != results['cached'][key] for key in ['accepted', 'reason'])
            acceptance_regressions += results['baseline']['accepted'] and not results['cached']['accepted']
            print(json.dumps({'language': language, 'round': round_index, 'equal': equal,
                              'results': results}, ensure_ascii=False), flush=True)
    print(json.dumps({'chinese_median_seconds': {key: statistics.median(values) for key, values in timings.items()},
                      'text_mismatches': text_mismatches, 'decision_changes': decision_changes,
                      'acceptance_regressions': acceptance_regressions}), flush=True)
    if text_mismatches or acceptance_regressions:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
