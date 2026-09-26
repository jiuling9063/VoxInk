#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/VoxInk.app}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 66
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
OUTPUT="${2:-$ROOT/output/release-$VERSION/VoxInk-$VERSION-macOS-arm64.dmg}"
GUIDE="${3:-$ROOT/docs/安装与使用.md}"
if [[ ! -f "$GUIDE" ]]; then
  echo "Installation guide not found: $GUIDE" >&2
  exit 66
fi

STAGE="$(mktemp -d /tmp/voxink-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/VoxInk"
/usr/bin/ditto --norsrc --noextattr "$APP" "$STAGE/VoxInk/VoxInk.app"
/bin/ln -s /Applications "$STAGE/VoxInk/应用程序"
cp "$GUIDE" "$STAGE/VoxInk/"

mkdir -p "$(dirname "$OUTPUT")"
/usr/bin/hdiutil create -volname "VoxInk $VERSION" -srcfolder "$STAGE/VoxInk" -ov -format UDZO "$OUTPUT" >/dev/null
printf 'DMG: %s\n' "$OUTPUT"
