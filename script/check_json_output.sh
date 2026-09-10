#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/voxink-output-check.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library \
  "$project_root"/benchmark/qwen-smoke/Sources/VoxInkQwenSmokeCore/*.swift \
  "$project_root/benchmark/qwen-smoke/Checks/JSONOutputChecks.swift" \
  -o "$check_dir/check-json-output"
"$check_dir/check-json-output" > "$check_dir/stdout" 2> "$check_dir/stderr"
python3 - "$check_dir" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
lines=(root/'stdout').read_text().splitlines()
assert len(lines)==1, 'stdout must contain exactly one JSON record'
assert json.loads(lines[0])=={'status':'ok'}
assert 'upstream diagnostic' in (root/'stderr').read_text()
print('PASS JSON stdout and diagnostic stderr isolation')
PY
