#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d /tmp/nikki-preview-tests.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library "$root/Sources/SiteLatency.swift" "$root/Tests/PreviewProbeTests.swift" -o "$tmp/tests"
"$tmp/tests"
