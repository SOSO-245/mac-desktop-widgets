#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/node-picker-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$project_root/Sources/ClientSwitchButton.swift" \
  "$project_root/Sources/NodePicker.swift" \
  "$project_root/Tests/NodePickerInteractionTests.swift" \
  -o "$test_build/NodePickerInteractionTests"
"$test_build/NodePickerInteractionTests"
