#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
APP_BUILD="${VOXINK_APP_BUILD:-/tmp/voxink-app-xcode-beta}"
WORKER_BUILD="${VOXINK_WORKER_BUILD:-/tmp/voxink-qwen-xcode-beta}"
PROJECT_KEY="$(printf '%s' "$ROOT" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-16)"
APP_DEST="$HOME/Library/Caches/VoxInkDevelopment/$PROJECT_KEY/VoxInk.app"
case "${1:-}" in
  ""|--verify|--build-only) ;;
  *) echo "Usage: $0 [--verify|--build-only]" >&2; exit 64 ;;
esac

# Compare complete executable paths, so other installed copies remain running.
stopped_pids=()
for pid in $(/usr/bin/pgrep -x VoxInk || true); do
  process_path="$(/bin/ps -p "$pid" -o comm=)"
  if [[ "$process_path" == "$APP_DEST/Contents/MacOS/VoxInk" || "$process_path" == "$ROOT/dist/VoxInk.app/Contents/MacOS/VoxInk" ]]; then
    kill "$pid" || true
    stopped_pids+=("$pid")
  fi
done
for pid in ${stopped_pids[@]+"${stopped_pids[@]}"}; do
  for _ in {1..100}; do
    if ! /bin/kill -0 "$pid" 2>/dev/null; then break; fi
    /bin/sleep 0.1
  done
  if /bin/kill -0 "$pid" 2>/dev/null; then
    echo "VoxInk did not finish cleanup within 10 seconds; build aborted (PID $pid)." >&2
    exit 70
  fi
done
/usr/bin/swift build --package-path "$ROOT/app" --scratch-path "$APP_BUILD" --product VoxInk
/usr/bin/swift build --package-path "$ROOT/benchmark/qwen-smoke" --scratch-path "$WORKER_BUILD" \
  -c release --product voxink-qwen-smoke --disable-automatic-resolution
APP_BIN="$(/usr/bin/swift build --package-path "$ROOT/app" --scratch-path "$APP_BUILD" --show-bin-path)"
WORKER_BIN="$(/usr/bin/swift build --package-path "$ROOT/benchmark/qwen-smoke" --scratch-path "$WORKER_BUILD" -c release --show-bin-path)"

# Stage outside the synced workspace to avoid inherited resource-fork attributes.
STAGE="$(mktemp -d /tmp/voxink-stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/VoxInk.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/Worker"
cp "$APP_BIN/VoxInk" "$BUNDLE/Contents/MacOS/VoxInk"
for resource in "$APP_BIN/"*.bundle; do
  /usr/bin/ditto --norsrc --noextattr "$resource" "$BUNDLE/Contents/Resources/$(basename "$resource")"
done
ICONSET="$STAGE/VoxInk.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$ROOT/app/Sources/VoxInkUI/Resources/logo-rain-impression-v2.png" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$ROOT/app/Sources/VoxInkUI/Resources/logo-rain-impression-v2.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/VoxInk.icns"
cp "$WORKER_BIN/voxink-qwen-smoke" "$BUNDLE/Contents/Resources/Worker/"
for resource in "$WORKER_BIN/"*.bundle; do
  /usr/bin/ditto --norsrc --noextattr "$resource" "$BUNDLE/Contents/Resources/Worker/$(basename "$resource")"
done
# MLX explicitly searches for a colocated mlx.metallib before bundle fallbacks.
cp "$WORKER_BIN/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
  "$BUNDLE/Contents/Resources/Worker/mlx.metallib"
cp "$ROOT/benchmark/model-manifest.json" "$BUNDLE/Contents/Resources/"
cp "$ROOT/app/ThirdPartyNotices.txt" "$BUNDLE/Contents/Resources/"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VoxInk</string>
<key>CFBundleIdentifier</key><string>local.voxink.preview</string>
<key>CFBundleName</key><string>语落 VoxInk</string>
<key>CFBundleIconFile</key><string>VoxInk.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>语落需要麦克风录制你的语音，并仅在本机转换为文字。点击开始录音后才会采集。</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$BUNDLE"
mkdir -p "$ROOT/dist"
mkdir -p "$(dirname "$APP_DEST")"
/usr/bin/ditto --norsrc --noextattr "$BUNDLE" "$APP_DEST"
/usr/bin/xattr -cr "$APP_DEST"
/usr/bin/codesign --verify --strict "$APP_DEST"
# Keep only a shortcut in the synced workspace: File Provider reattaches
# disallowed attributes immediately even after xattr -cr on real .app bundles.
if [[ -L "$ROOT/dist/VoxInk.app" ]]; then
  /bin/rm "$ROOT/dist/VoxInk.app"
elif [[ -d "$ROOT/dist/VoxInk.app" ]]; then
  /bin/rm -rf "$ROOT/dist/VoxInk.app"
fi
/bin/ln -s "$APP_DEST" "$ROOT/dist/VoxInk.app"
if [[ "${1:-}" != --build-only ]]; then
  /usr/bin/open "$APP_DEST"
fi
if [[ "${1:-}" == --verify ]]; then
  sleep 2
  running_pids=()
  for pid in $(/usr/bin/pgrep -x VoxInk || true); do
    if [[ "$(/bin/ps -p "$pid" -o comm=)" == "$APP_DEST/Contents/MacOS/VoxInk" ]]; then
      running_pids+=("$pid")
    fi
  done
  if [[ "${#running_pids[@]}" != 1 ]]; then
    echo "Expected one VoxInk instance at $APP_DEST; found ${#running_pids[@]}." >&2
    exit 70
  fi
  printf 'Verified single instance: %s\n' "${running_pids[0]}"
fi
printf 'App: %s\n' "$ROOT/dist/VoxInk.app"
