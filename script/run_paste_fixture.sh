#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
FIXTURE="/tmp/VoxInkPasteFixture.app"
mkdir -p "$FIXTURE/Contents/MacOS"
/usr/bin/xcrun swiftc -swift-version 6 "$ROOT/app/Checks/PasteFixture.swift" \
  -o "$FIXTURE/Contents/MacOS/VoxInkPasteFixture" -framework AppKit
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VoxInkPasteFixture</string>
<key>CFBundleIdentifier</key><string>local.voxink.paste-fixture</string>
<key>CFBundleName</key><string>VoxInk 本地粘贴测试框</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$FIXTURE"
/usr/bin/open -n "$FIXTURE"
