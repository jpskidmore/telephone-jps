#!/bin/bash
# Build a reproducible ad-hoc local test release from the exact checked-out SHA.
set -euo pipefail
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
./Scripts/verify-vendor-security.sh
python3 Tests/test_audio_recovery_integration.py
python3 Tests/test_recording_lifecycle_model.py
./Scripts/run-audio-device-tests.sh
./Scripts/run-recording-tests.sh
# Additional bounded bug regressions can run without a signed application host.
if [ -x Scripts/run-foundation-regression-tests.sh ]; then
    ./Scripts/run-foundation-regression-tests.sh
fi

run_dir="$project_root/build/test-release"
test ! -e "$run_dir" || { echo 'Use a clean checkout for a test release.' >&2; exit 73; }
mkdir -p "$run_dir/distribution"
for scheme in Domain UseCasesTests TelephoneTests ReceiptValidationTests; do
    xcodebuild -project Telephone.xcodeproj -scheme "$scheme" \
        -configuration Debug -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$run_dir/TestDerivedData" \
        -resultBundlePath "$run_dir/$scheme.xcresult" \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
        "CLANG_MODULE_CACHE_PATH=$run_dir/ModuleCache" \
        'OTHER_CFLAGS=$(inherited) -ffile-prefix-map=$(SRCROOT)=.' test
done
xcodebuild -project Telephone.xcodeproj -target Telephone \
    -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO "SYMROOT=$run_dir/Products" "OBJROOT=$run_dir/Intermediates" \
    "CLANG_MODULE_CACHE_PATH=$run_dir/ModuleCache" \
    'OTHER_CFLAGS=$(inherited) -ffile-prefix-map=$(SRCROOT)=.' build
app_path="$run_dir/Products/Release/jps Telephone.app"
./Scripts/sign-adhoc-release.sh "$app_path"
./Scripts/verify-adhoc-release.sh "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app_path/Contents/Info.plist")
source_sha=$(git rev-parse HEAD)
dist="$run_dir/distribution"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$dist/jps-Telephone-${version}-arm64.zip"
git archive --format=zip --prefix="telephone-jps-${version}/" \
    --output="$dist/jps-Telephone-${version}-source.zip" "$source_sha"
{
    printf '# Build verification\n\nVersion: %s\nBuild: %s\nSource commit: %s\n\n' "$version" "$build_number" "$source_sha"
    sw_vers
    xcodebuild -version
    printf 'macOS SDK: '
    xcrun --sdk macosx --show-sdk-version
    printf '\nPassed: dependency verification, audio recovery and recording harnesses, portable lifecycle checks, four XCTest suites, arm64 Release build, ad-hoc signing and bundle verification.\n'
    if [ -x Scripts/run-foundation-regression-tests.sh ]; then
        printf 'Passed: standalone production Foundation/receipt regression harness.\n'
    fi
    printf '\nThis is an ad-hoc signed local test build, not notarized. Live SIP, real audio devices, VoiceOver and visual acceptance remain manual tests.\n'
} > "$dist/BUILD-VERIFICATION.md"
cp "docs/releases/${version}.md" "$dist/RELEASE-NOTES.md"
(
    cd "$dist"
    shasum -a 256 ./*.zip BUILD-VERIFICATION.md RELEASE-NOTES.md > SHA256SUMS.txt
)
printf 'Packaged %s (%s) from %s\n' "$version" "$build_number" "$source_sha"
