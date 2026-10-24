#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/flclash-model-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_root/Sources/Model.swift" \
  "$project_root/Sources/Backend.swift" \
  "$project_root/Tests/ModelTests.swift" \
  -o "$test_build/FlClashModelTests"
"$test_build/FlClashModelTests"
