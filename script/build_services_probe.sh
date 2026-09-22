#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
IDENTITY="${VOXINK_SIGN_IDENTITY:?Set VOXINK_SIGN_IDENTITY}"
WORK="$(mktemp -d /tmp/voxink-services-probe.XXXXXX)"
APP="$WORK/VoxInkServicesProbe.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -swift-version 6 -parse-as-library "$ROOT/benchmark/app-store-probe/DownloadContract.swift" \
  "$ROOT/benchmark/app-store-probe/ServicesProbe.swift" -o "$APP/Contents/MacOS/VoxInkServicesProbe"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
info = {
    'CFBundleExecutable': 'VoxInkServicesProbe',
    'CFBundleIdentifier': 'local.voxink.services-probe',
    'CFBundleName': 'VoxInk Services Probe',
    'CFBundlePackageType': 'APPL',
    'NSServices': [{
        'NSMenuItem': {'default': 'VoxInk 插入测试文字'},
        'NSMessage': 'insertProbeText',
        'NSPortName': 'VoxInkServicesProbe',
        'NSReturnTypes': ['NSStringPboardType'],
        'NSRequiredContext': {},
        'NSTimeout': '10000',
    }],
}
with open(sys.argv[1], 'wb') as output:
    plistlib.dump(info, output)
PY
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --entitlements "$ROOT/benchmark/app-store-probe/Services.entitlements" "$APP"
codesign --verify --strict "$APP"
printf 'Services probe: %s\n' "$APP"
