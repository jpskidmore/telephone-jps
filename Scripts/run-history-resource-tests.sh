#!/bin/sh
# Targeted local components only; requires existing Debug framework products.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
frameworks=${1:?Pass the path to locally built Debug framework products}
frameworks=$(CDPATH= cd -- "$frameworks" && pwd)
sdk=$(xcrun --sdk macosx --show-sdk-path)
scratch_dir=${JPS_RESOURCE_TEST_DIR:-$(mktemp -d /private/tmp/jps-telephone-resources.XXXXXX)}
mkdir -p "$scratch_dir"
xcrun swiftc -parse-as-library -F "$frameworks" -framework UseCases -framework Domain \
    -Xlinker -rpath -Xlinker "$frameworks" Telephone/SimplePropertyListStorage.swift \
    Tests/HistoryPersistenceRegressionHarness.swift -o "$scratch_dir"/history-persistence-regression
"$scratch_dir"/history-persistence-regression
for source in AKNetworkReachability NameServers; do
    xcrun clang -arch arm64 -isysroot "$sdk" -mmacosx-version-min=15.6 -fobjc-arc -fmodules \
        -F "$frameworks" -I Telephone -include Tests/ResourceLifecycleBoundary.h \
        -c "Telephone/$source.m" -o "$scratch_dir/$source-resource-regression.o"
done
xcrun clang -arch arm64 -isysroot "$sdk" -mmacosx-version-min=15.6 -fobjc-arc -fmodules \
    -F "$frameworks" -I Telephone Tests/ResourceLifecycleRegressionHarness.m \
    "$scratch_dir"/AKNetworkReachability-resource-regression.o "$scratch_dir"/NameServers-resource-regression.o \
    -framework Foundation -framework SystemConfiguration -framework UseCases -framework Domain \
    -Wl,-rpath,"$frameworks" -o "$scratch_dir"/resource-lifecycle-regression
"$scratch_dir"/resource-lifecycle-regression

xcrun swiftc -parse-as-library -import-objc-header Tests/FoundationOnly.h -F "$frameworks" -framework UseCases -framework Domain \
    -Xlinker -rpath -Xlinker "$frameworks" Telephone/BackgroundActivityUserAgentEventTarget.swift \
    Telephone/AKSIPUserAgentEventSource.swift Tests/BackgroundActivityRegressionHarness.swift \
    -o "$scratch_dir"/background-activity-regression
"$scratch_dir"/background-activity-regression

# Exercise the nullable Objective-C initializer through its actual Swift import.
xcrun clang -arch arm64 -isysroot "$sdk" -mmacosx-version-min=15.6 -fobjc-arc -fmodules \
    -I Telephone -DTELEPHONE_RESOURCE_NO_MAIN -c Tests/ResourceLifecycleRegressionHarness.m \
    -o "$scratch_dir"/resource-lifecycle-boundary-functions.o
xcrun swiftc -parse-as-library -import-objc-header Tests/NameServersFailableBridge.h \
    -Xcc -ITelephone Tests/NameServersFailableRegressionHarness.swift \
    "$scratch_dir"/NameServers-resource-regression.o "$scratch_dir"/resource-lifecycle-boundary-functions.o \
    -framework Foundation -framework SystemConfiguration -o "$scratch_dir"/dns-failable-regression
"$scratch_dir"/dns-failable-regression
