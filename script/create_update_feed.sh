#!/bin/bash
set -euo pipefail

if [[ $# != 1 || ! -f "$1" ]]; then
  echo "Usage: $0 /path/to/VoxInk-VERSION-macOS-arm64.dmg" >&2
  exit 64
fi
directory="$(cd "$(dirname "$1")" && pwd)"
image="$(basename "$1")"
if [[ ! "$image" =~ ^VoxInk-([0-9]+\.[0-9]+\.[0-9]+)-macOS-arm64\.dmg$ ]]; then
  echo "Unexpected release filename: $image" >&2
  exit 64
fi
version="${BASH_REMATCH[1]}"
tools="${VOXINK_APP_BUILD:-/tmp/voxink-app-xcode-beta}/artifacts/sparkle/Sparkle/bin"
stage="$(mktemp -d "$directory/.appcast.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ln "$directory/$image" "$stage/$image"
tag_url="https://github.com/jiuling9063/VoxInk/releases"
"$tools/generate_appcast" --account local.voxink.preview --maximum-deltas 0 \
  --download-url-prefix "https://jiuling9063.github.io/VoxInk/v$version/" --full-release-notes-url "$tag_url/tag/v$version" "$stage"
mv "$stage/appcast.xml" "$directory/appcast.xml"
