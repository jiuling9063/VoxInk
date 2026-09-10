#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
APP_BUILD="${VOXINK_APP_BUILD:-/tmp/voxink-app-xcode-beta}"
case "${1:-}" in
  ""|--build-only) ;;
  *) echo "Usage: $0 [--build-only]" >&2; exit 64 ;;
esac
/usr/bin/swift build --package-path "$ROOT/app" --scratch-path "$APP_BUILD" --product voxink-feedback-check
CHECK_BIN="$(/usr/bin/swift build --package-path "$ROOT/app" --scratch-path "$APP_BUILD" --show-bin-path)"
CHECK_ROOT="$(mktemp -d /tmp/voxink-feedback-check.XXXXXX)"
CHECK_BUNDLE="$CHECK_ROOT/VoxInkFeedbackCheck.app"
mkdir -p "$CHECK_BUNDLE/Contents/MacOS"
/usr/bin/ditto --norsrc --noextattr "$CHECK_BIN/voxink-feedback-check" "$CHECK_BUNDLE/Contents/MacOS/voxink-feedback-check"
cat > "$CHECK_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>voxink-feedback-check</string>
<key>CFBundleIdentifier</key><string>local.voxink.feedback-check</string>
<key>CFBundleName</key><string>VoxInk 浮层检查</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$CHECK_BUNDLE"
/usr/bin/codesign --verify --strict "$CHECK_BUNDLE"
echo "Visual checker: $CHECK_BUNDLE"
if [[ "${1:-}" != "--build-only" ]]; then /usr/bin/open "$CHECK_BUNDLE"; fi
