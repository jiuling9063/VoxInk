#!/usr/bin/env python3
"""Opt-in SiliconFlow comparison using the application's real client and guards.

SILICONFLOW_API_KEY must be supplied in the environment, never as an argument.
Only the three explicitly selected corpus samples and fixed test text are sent.
"""
import argparse
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--scratch-path', default='/tmp/voxink-style-build')
    args = parser.parse_args()
    if not os.environ.get('SILICONFLOW_API_KEY'):
        parser.error('Set SILICONFLOW_API_KEY in the environment.')
    for sample in ('SMOKE-001', 'SMOKE-002', 'SMOKE-003'):
        if not (args.corpus / (sample + '.wav')).is_file():
            parser.error('Missing required corpus WAV files.')
    args.report.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['VOXINK_LIVE_CORPUS'] = str(args.corpus.resolve())
    env['VOXINK_LIVE_REPORT'] = str(args.report.resolve())
    root = Path(__file__).resolve().parent.parent
    result = subprocess.run(['/usr/bin/swift', 'test', '--package-path', str(root / 'app'),
                             '--scratch-path', args.scratch_path, '--filter', 'CloudModelLiveTests'], env=env)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
