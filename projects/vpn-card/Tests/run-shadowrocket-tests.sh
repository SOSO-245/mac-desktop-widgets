#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/shadowrocket-model-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_root/Sources/Model.swift" \
  "$project_root/Sources/ShadowrocketBackend.swift" \
  "$project_root/Sources/ShadowrocketNodeControl.swift" \
  "$project_root/Sources/ShadowrocketReader.swift" \
  "$project_root/Tests/ShadowrocketTests.swift" \
  -o "$test_build/ShadowrocketModelTests"
"$test_build/ShadowrocketModelTests"
