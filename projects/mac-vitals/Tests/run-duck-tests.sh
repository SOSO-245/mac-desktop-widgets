#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
task_dir=$(mktemp -d /tmp/mac-duck-tests.XXXXXX)
trap 'rm -rf "$task_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library Sources/Metrics.swift Sources/DuckWeather.swift Sources/DuckPower.swift Sources/PowerWater.swift Sources/ToolboxShared.swift Tests/DuckSkinTests.swift -o "$task_dir/tests"
"$task_dir/tests"
