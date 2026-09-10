#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d /tmp/voxink-model-check.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library \
  "$project_root"/benchmark/qwen-smoke/Sources/VoxInkQwenSmokeCore/*.swift \
  "$project_root/benchmark/qwen-smoke/Checks/ModelVerificationChecks.swift" \
  -o "$check_dir/check-model-contract"
"$check_dir/check-model-contract"
