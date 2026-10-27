#!/bin/bash
set -euo pipefail
settings_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/widget-settings-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$settings_root/AppSettings.swift" "$settings_root/MenuCustomization.swift" \
  "$settings_root/Tests/SettingsTests.swift" -o "$test_build/SettingsTests"
"$test_build/SettingsTests"
