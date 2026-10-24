#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_build="$(mktemp -d "${TMPDIR:-/tmp}/site-card-tests.XXXXXX")"
trap 'rm -rf "$test_build"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
 "$project_root/Sources/Model.swift" "$project_root/Sources/Backend.swift" \
 "$project_root/Sources/ShadowrocketBackend.swift" "$project_root/Sources/SiteLatency.swift" \
 "$project_root/Tests/SiteTests.swift" -o "$test_build/SiteTests"
"$test_build/SiteTests"
