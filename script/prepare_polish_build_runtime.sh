#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_RUNTIME="${VOXINK_POLISH_BUILD_RUNTIME:-$HOME/Library/Caches/VoxInkBuild/polish-python-3.12.13}"
if ! command -v uv >/dev/null; then
  echo "Building the bundled runtime requires uv on the developer machine." >&2
  exit 69
fi
# uv is used only on the build machine. Users receive the tested runtime in the App.
uv python install 3.12.13
if [[ ! -x "$BUILD_RUNTIME/bin/python3.12" ]]; then
  uv venv "$BUILD_RUNTIME" --python 3.12.13 --managed-python
fi
MACOSX_DEPLOYMENT_TARGET=15.0 uv pip sync --python "$BUILD_RUNTIME/bin/python3.12" \
  --python-platform aarch64-apple-darwin --only-binary :all: --require-hashes \
  "$ROOT/benchmark/polish-requirements.lock"
printf 'Build runtime: %s\n' "$BUILD_RUNTIME/bin/python3.12"
