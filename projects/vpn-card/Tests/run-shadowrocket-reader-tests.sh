#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/shadowrocket-reader-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_root/Sources/Model.swift" \
  "$project_root/Sources/ShadowrocketBackend.swift" \
  "$project_root/Sources/ShadowrocketNodeControl.swift" \
  "$project_root/Sources/ShadowrocketReader.swift" \
  "$project_root/Tests/ShadowrocketReaderTests.swift" \
  -o "$test_build/ShadowrocketReaderTests"
"$test_build/ShadowrocketReaderTests"
