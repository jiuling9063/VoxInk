#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SOURCE_APP="${VOXINK_PROBE_SOURCE_APP:-/Applications/VoxInk.app}"
IDENTITY="${VOXINK_SIGN_IDENTITY:?Set VOXINK_SIGN_IDENTITY to the installed App signing identity}"
WORK="$(mktemp -d /tmp/voxink-store-probe.XXXXXX)"
APP="$WORK/VoxInkSandboxProbe.app"
mkdir -p "$APP/Contents/MacOS" "$WORK/fixtures"
xcrun swiftc -swift-version 6 -parse-as-library "$ROOT/benchmark/app-store-probe/Probe.swift" \
  "$ROOT/benchmark/app-store-probe/DownloadContract.swift" "$ROOT/benchmark/app-store-probe/DownloadProbe.swift" \
  -o "$APP/Contents/MacOS/VoxInkSandboxProbe"
ditto --norsrc --noextattr "$SOURCE_APP/Contents/Resources" "$APP/Contents/Resources"
SERVICE="$APP/Contents/XPCServices/DownloadProbe.xpc"
mkdir -p "$SERVICE/Contents/MacOS" "$SERVICE/Contents/Resources"
xcrun swiftc -swift-version 6 -parse-as-library "$ROOT/benchmark/app-store-probe/DownloadContract.swift" \
  "$ROOT/benchmark/app-store-probe/DownloadTransfer.swift" \
  "$ROOT/benchmark/app-store-probe/DownloadService.swift" -o "$SERVICE/Contents/MacOS/DownloadProbe"
python3 - "$ROOT/benchmark/model-manifest.json" "$APP/Contents/Resources" "$SERVICE/Contents/Resources" <<'PY'
import json,pathlib,sys
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text())
model=next(c['model'] for c in manifest['candidates'] if c['id']=='qwen3-asr-0.6b-mlx-4bit')
config=next(f for f in model['files'] if f['path']=='config.json')
for directory in sys.argv[2:]:
    pathlib.Path(directory,'download-fixture.json').write_text(json.dumps(config))
PY
cat > "$SERVICE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DownloadProbe</string>
<key>CFBundleIdentifier</key><string>local.voxink.sandbox-probe.download</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>XPCService</key><dict><key>ServiceType</key><string>Application</string></dict>
</dict></plist>
PLIST
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VoxInkSandboxProbe</string>
<key>CFBundleIdentifier</key><string>local.voxink.sandbox-probe</string>
<key>CFBundleName</key><string>VoxInk Sandbox Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSMicrophoneUsageDescription</key><string>仅用于验证沙盒录音，录制 1 秒后立即删除，不识别、不上传。</string>
</dict></plist>
PLIST
# Child tools inherit the parent's sandbox; embedded libraries retain their signatures.
for executable in "$APP/Contents/Resources/Worker/voxink-qwen-smoke" "$APP/Contents/Resources/PolishRuntime/bin/python3.12"; do
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ROOT/benchmark/app-store-probe/Child.entitlements" "$executable"
done
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ROOT/benchmark/app-store-probe/Download.entitlements" "$SERVICE"
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ROOT/benchmark/app-store-probe/App.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
# APFS copy-on-write fixtures avoid downloads and protect the installed model cache.
python3 - "$WORK/fixtures" <<'PY'
import pathlib,subprocess,sys,wave
root=pathlib.Path(sys.argv[1]); support=pathlib.Path.home()/'Library/Application Support/VoxInk'
asr=support/'Models/bc441bd1e4295c1f42d9879f056049a925b6e013'
polish=support/'Polish/models/3b1b1768f8f8cf8351c712464f906e86c2b8269e'
for src,name in [(asr,'asr'),(polish,'polish')]:
    if not src.is_dir(): raise SystemExit('Missing installed model: '+str(src))
    subprocess.run(['/bin/cp','-cR',str(src),str(root/name)],check=True)
with wave.open(str(root/'silence.wav'),'wb') as w:
    w.setparams((1,2,16000,0,'NONE','not compressed')); w.writeframes(b'\0\0'*16000)
PY
printf 'Probe: %s\nFixtures: %s\n' "$APP" "$WORK/fixtures"
