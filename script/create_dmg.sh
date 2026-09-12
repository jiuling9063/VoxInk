#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Desktop/VoxInk-Notarized.81DtkW/VoxInk.app}"
OUTPUT="${2:-$ROOT/output/trial-0.1.0/VoxInk-0.1.0-trial.1-macOS-arm64.dmg}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 66
fi

STAGE="$(mktemp -d /tmp/voxink-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/VoxInk"
/usr/bin/ditto --norsrc --noextattr "$APP" "$STAGE/VoxInk/VoxInk.app"
/bin/ln -s /Applications "$STAGE/VoxInk/应用程序"
cp "$ROOT/docs/试用版说明-0.1.0.md" "$ROOT/docs/试用反馈模板.md" "$STAGE/VoxInk/"

mkdir -p "$(dirname "$OUTPUT")"
/usr/bin/hdiutil create -volname "VoxInk 0.1.0" -srcfolder "$STAGE/VoxInk" -ov -format UDZO "$OUTPUT" >/dev/null
printf 'DMG: %s\n' "$OUTPUT"
