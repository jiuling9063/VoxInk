#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
APP_BUILD="${VOXINK_APP_BUILD:-/tmp/voxink-app-xcode-beta}"
WORKER_BUILD="${VOXINK_WORKER_BUILD:-/tmp/voxink-qwen-xcode-beta}"
APP_CONFIGURATION="${VOXINK_APP_CONFIGURATION:-debug}"
SIGN_IDENTITY="${VOXINK_SIGN_IDENTITY:--}"
PROJECT_KEY="$(printf '%s' "$ROOT" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-16)"
APP_DEST="$HOME/Library/Caches/VoxInkDevelopment/$PROJECT_KEY/VoxInk.app"
case "${1:-}" in
  ""|--verify|--build-only|--package-only) ;;
  *) echo "Usage: $0 [--verify|--build-only|--package-only]" >&2; exit 64 ;;
esac
case "$APP_CONFIGURATION" in
  debug|release) ;;
  *) echo "VOXINK_APP_CONFIGURATION must be debug or release." >&2; exit 64 ;;
esac
if [[ "$SIGN_IDENTITY" != - ]]; then
  if [[ ! "$SIGN_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "Set VOXINK_SIGN_IDENTITY to the 40-character certificate hash from security find-identity -v -p codesigning." >&2
    exit 64
  fi
  identities="$(/usr/bin/security find-identity -v -p codesigning)"
  if ! /usr/bin/grep -Fqi " $SIGN_IDENTITY " <<< "$identities"; then
    echo "Requested signing identity is not available; current App has not been changed." >&2
    exit 65
  fi
fi

# Compare complete executable paths, so other installed copies remain running.
stopped_pids=()
if [[ "${1:-}" != --package-only ]]; then
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
fi
/usr/bin/swift build --package-path "$ROOT/app" --scratch-path "$APP_BUILD" -c "$APP_CONFIGURATION" --product VoxInk
/usr/bin/swift build --package-path "$ROOT/benchmark/qwen-smoke" --scratch-path "$WORKER_BUILD" \
  -c release --product voxink-qwen-smoke --disable-automatic-resolution
APP_BIN="$(/usr/bin/swift build --package-path "$ROOT/app" --scratch-path "$APP_BUILD" -c "$APP_CONFIGURATION" --show-bin-path)"
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
for localization in "$ROOT/app/Localization/"*.lproj; do
  /usr/bin/ditto --norsrc --noextattr "$localization" "$BUNDLE/Contents/Resources/$(basename "$localization")"
done
mkdir -p "$BUNDLE/Contents/Resources/Polish"
cp "$ROOT/script/polish_worker.py" "$ROOT/script/polish_guard.py" "$ROOT/script/check_polish_model.py" "$ROOT/script/download_polish_model.py" "$BUNDLE/Contents/Resources/Polish/"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>zh-Hant</string><string>en</string><string>ja</string><string>ko</string></array>
<key>CFBundleExecutable</key><string>VoxInk</string>
<key>CFBundleIdentifier</key><string>local.voxink.preview</string>
<key>CFBundleName</key><string>语落 VoxInk</string>
<key>CFBundleIconFile</key><string>VoxInk.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.9</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>语落需要麦克风录制你的语音，并仅在本机转换为文字。点击开始录音后才会采集。</string>
</dict></plist>
PLIST
bash "$ROOT/script/prepare_polish_build_runtime.sh"
POLISH_BUILD_PYTHON="${VOXINK_POLISH_BUILD_RUNTIME:-$HOME/Library/Caches/VoxInkBuild/polish-python-3.12.13}/bin/python3.12"
"$POLISH_BUILD_PYTHON" -B "$ROOT/script/bundle_polish_runtime.py" --python "$POLISH_BUILD_PYTHON" \
  --destination "$BUNDLE/Contents/Resources/PolishRuntime" --identity "$SIGN_IDENTITY" \
  --requirements "$ROOT/benchmark/polish-requirements.lock"
sign_options=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != - ]]; then
  sign_options+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${sign_options[@]}" "$BUNDLE/Contents/Resources/Worker/voxink-qwen-smoke"
/usr/bin/codesign "${sign_options[@]}" --entitlements "$ROOT/app/VoxInk.entitlements" "$BUNDLE"
/usr/bin/codesign --verify --deep --strict "$BUNDLE"
if [[ "${1:-}" == --package-only ]]; then
  PACKAGE_ROOT="$(mktemp -d /tmp/voxink-package.XXXXXX)"
  /usr/bin/ditto --norsrc --noextattr "$BUNDLE" "$PACKAGE_ROOT/VoxInk.app"
  /usr/bin/codesign --verify --deep --strict "$PACKAGE_ROOT/VoxInk.app"
  printf 'Package: %s\nConfiguration: %s\n' "$PACKAGE_ROOT/VoxInk.app" "$APP_CONFIGURATION"
  if [[ "$SIGN_IDENTITY" == - ]]; then
    echo "Ad-hoc preview only; not notarized and upgrade permissions are not guaranteed."
  fi
  exit 0
fi
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
