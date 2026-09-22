#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
WORK="$(mktemp -d /tmp/voxink-probe-tests.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
SOURCES="$ROOT/benchmark/app-store-probe"
xcrun swiftc -swift-version 6 -parse-as-library "$SOURCES/DownloadContract.swift" \
  "$SOURCES/DownloadContractTests.swift" -o "$WORK/tests"
"$WORK/tests"
xcrun swiftc -swift-version 6 -typecheck -parse-as-library "$SOURCES/DownloadContract.swift" \
  "$SOURCES/DownloadService.swift"
xcrun swiftc -swift-version 6 -typecheck -parse-as-library "$SOURCES/DownloadContract.swift" \
  "$SOURCES/DownloadProbe.swift" "$SOURCES/Probe.swift"
xcrun swiftc -swift-version 6 -typecheck -parse-as-library "$SOURCES/DownloadContract.swift" \
  "$SOURCES/ServicesProbe.swift"
bash -n "$ROOT/script/run_app_store_probe.sh" "$ROOT/script/build_services_probe.sh"
printf 'PASS Swift 6 type checks and build-script syntax\n'
