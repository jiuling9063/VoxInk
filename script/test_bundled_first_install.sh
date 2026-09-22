#!/bin/bash
# Opt-in network test: downloads the light model into a new disposable directory.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
STORE_FRESH_ROOT="$(mktemp -d /tmp/voxink-store-fresh-isolated.XXXXXX)"
export VOXINK_TEST_BUNDLED_RESOURCES="${VOXINK_TEST_BUNDLED_RESOURCES:-/Applications/VoxInk.app/Contents/Resources}"
export VOXINK_TEST_FRESH_ROOT="$STORE_FRESH_ROOT/model-data"
# Process children inherit these variables. Never reuse the developer's Hub/Xet
# caches or token file when checking the first-install experience.
export HF_HOME="$STORE_FRESH_ROOT/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export HUGGINGFACE_HUB_CACHE="$HF_HUB_CACHE"
export HF_ASSETS_CACHE="$HF_HOME/assets"
export HF_XET_CACHE="$HF_HOME/xet"
export HF_TOKEN_PATH="$HF_HOME/token"
export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
export HF_HUB_DISABLE_TELEMETRY=1
export HF_HUB_DISABLE_UPDATE_CHECK=1
export HF_TOKEN=""
export VOXINK_UI_LANGUAGE=zh-Hans
printf 'Isolated first-install files: %s\n' "$STORE_FRESH_ROOT"
swift test --package-path "$ROOT/app" --scratch-path "${VOXINK_TEST_SCRATCH:-/tmp/voxink-app-xcode-beta}" \
  --filter freshUserDownloadsAndRunsWithoutRuntimeConfiguration
