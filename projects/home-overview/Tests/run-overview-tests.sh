#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
TASK_TEST_BINARY="$(mktemp -t homeatlas-overview-tests)"
trap 'rm -f "$TASK_TEST_BINARY"' EXIT
xcrun swiftc -D CLIMATE_CURVE_TESTING -D HOME_ENERGY_TESTING \
  "$TASK_ROOT/Sources/Model.swift" \
  "$TASK_ROOT/Sources/DashboardData.swift" \
  "$TASK_ROOT/Sources/OverviewService.swift" \
  "$TASK_ROOT/Sources/ClimateHistory.swift" \
  "$TASK_ROOT/Tests/OverviewDataTests.swift" \
  -o "$TASK_TEST_BINARY"
"$TASK_TEST_BINARY"
