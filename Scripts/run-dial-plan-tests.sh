#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_directory=$(mktemp -d /private/tmp/jps-dial-plan-regression.XXXXXX)
trap 'rm -rf "$build_directory"' EXIT HUP INT TERM
xcrun swiftc -swift-version 6 -strict-concurrency=complete \
    "$project_root/Telephone/DialPlan.swift" \
    "$project_root/Tests/DialPlanRegressionHarness.swift" \
    -o "$build_directory/dial-plan-tests"
"$build_directory/dial-plan-tests"
