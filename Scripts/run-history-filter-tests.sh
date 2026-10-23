#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then
    echo "Native history filter regressions require macOS and its AppKit SDK." >&2
    exit 69
fi
command -v xcrun >/dev/null 2>&1 || { echo "Missing prerequisite: xcrun" >&2; exit 69; }
build_directory=${JPS_HISTORY_FILTER_TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/telephone-history-filter.XXXXXX")}
mkdir -p "$build_directory"
if [ -z "${JPS_HISTORY_FILTER_TEST_DIR:-}" ]; then trap 'rm -rf "$build_directory"' EXIT HUP INT TERM; fi

# Real, minimal UseCases dependency graph; no app frameworks, SIP or Contacts.
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos15.6" -emit-module -emit-library -module-name UseCases \
    -emit-module-path "$build_directory/UseCases.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libUseCases.dylib \
    "$project_root/UseCases/MatchedContact.swift" "$project_root/UseCases/URI.swift" \
    "$project_root/UseCases/ServiceAddress.swift" "$project_root/UseCases/Transport.swift" \
    "$project_root/UseCases/String+IPAddress.swift" -o "$build_directory/libUseCases.dylib"

# An optional historical controller enables before/after reproduction without
# changing production source. No source rewriting is performed.
controller_source=${JPS_HISTORY_FILTER_CONTROLLER_SOURCE:-$project_root/Telephone/CallHistoryViewController.swift}
xcrun swiftc -swift-version 6 -target "$(uname -m)-apple-macos15.6" -enable-upcoming-feature InferIsolatedConformances \
    -import-objc-header "$project_root/Tests/FoundationOnly.h" \
    -I "$build_directory" -L "$build_directory" -lUseCases \
    -Xlinker -rpath -Xlinker "$build_directory" \
    "$controller_source" "$project_root/Telephone/CallHistoryView.swift" \
    "$project_root/Telephone/PresentationCallHistoryRecord.swift" \
    "$project_root/Telephone/PresentationContact.swift" \
    "$project_root/Tests/HistoryFilterRegressionHarness.swift" \
    -o "$build_directory/history-filter-regression-harness"
"$build_directory/history-filter-regression-harness" "$@"
