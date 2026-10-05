#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then
    echo "Foundation regression tests require macOS and the Swift SDK." >&2
    exit 69
fi
command -v xcrun >/dev/null 2>&1 || { echo "Missing prerequisite: xcrun" >&2; exit 69; }
xcrun --find swiftc >/dev/null
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/telephone-foundation-regression.XXXXXX")
trap 'rm -rf "$build_directory"' EXIT HUP INT TERM

# A small real UseCases module lets the production adapters compile unchanged,
# without linking the app or accessing its user's defaults, sound, or SIP state.
xcrun swiftc -swift-version 6 -emit-module -emit-library -module-name UseCases \
    -emit-module-path "$build_directory/UseCases.swiftmodule" \
    -Xlinker -install_name -Xlinker @rpath/libUseCases.dylib \
    "$project_root/UseCases/Timer.swift" \
    "$project_root/UseCases/TimerFactory.swift" \
    "$project_root/UseCases/Sound.swift" \
    "$project_root/UseCases/Ringtone.swift" \
    "$project_root/UseCases/RepeatingSound.swift" \
    "$project_root/UseCases/PurchaseReminderSettings.swift" \
    -o "$build_directory/libUseCases.dylib"

# Match the application's approachable-concurrency isolated conformance rule.
# DeviceGUID is compiled, but tests inject CF properties and never query IOKit.
xcrun swiftc -swift-version 6 -enable-upcoming-feature InferIsolatedConformances \
    -I "$build_directory" -L "$build_directory" -lUseCases \
    -Xlinker -rpath -Xlinker "$build_directory" \
    "$project_root/Telephone/FoundationToUseCasesTimerAdapter.swift" \
    "$project_root/Telephone/FoundationToUseCasesTimerAdapterFactory.swift" \
    "$project_root/Telephone/UserDefaultsPurchaseReminderSettings.swift" \
    "$project_root/ReceiptValidation/DeviceGUID.swift" \
    "$project_root/Tests/FoundationRegressionHarness.swift" \
    -o "$build_directory/foundation-regression-harness"

"$build_directory/foundation-regression-harness"
