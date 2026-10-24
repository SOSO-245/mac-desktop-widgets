#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-resets-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library \
  "$project_dir/Sources/Model.swift" "$project_dir/Tests/ModelTests.swift" \
  -o "$test_build_dir/ModelTests"
"$test_build_dir/ModelTests" "$project_dir/Tests/Fixtures"
