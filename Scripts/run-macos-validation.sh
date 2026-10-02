#!/bin/sh
# Native validation only. Does not sign, deploy, make calls, or change settings.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "Native validation requires an Apple silicon Mac with Xcode and macOS 15.6+." >&2
    exit 69
fi
for tool in xcodebuild xcrun python3 rg strings; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing prerequisite: $tool" >&2
        exit 69
    }
done
python3 - <<'PYTHON'
import platform
version = tuple(int(part) for part in platform.mac_ver()[0].split(".")[:2])
if version < (15, 6):
    raise SystemExit("Native validation requires macOS 15.6 or later")
PYTHON
xcrun --sdk macosx --show-sdk-path >/dev/null
xcodebuild -version
./Scripts/verify-vendor-security.sh
./Scripts/run-recording-tests.sh

# The four checked-in schemes below cover all four XCTest bundles. Fresh result
# paths avoid xcodebuild's refusal to overwrite an existing .xcresult bundle.
mkdir -p build/validation
run_dir=$(mktemp -d "$project_root/build/validation/run.XXXXXX")
echo "Native validation artifacts: $run_dir"
for scheme in Domain UseCasesTests TelephoneTests ReceiptValidationTests; do
    xcodebuild -project Telephone.xcodeproj -scheme "$scheme" \
        -configuration Debug -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$run_dir/DerivedData" \
        -resultBundlePath "$run_dir/$scheme.xcresult" \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
        "CLANG_MODULE_CACHE_PATH=$run_dir/ModuleCache" \
        'OTHER_CFLAGS=$(inherited) -ffile-prefix-map=$(SRCROOT)=.' test
done

# An explicit target works on a clean checkout without an auto-created app scheme.
xcodebuild -project Telephone.xcodeproj -target Telephone \
    -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO "SYMROOT=$run_dir/Products" "OBJROOT=$run_dir/Intermediates" \
    "CLANG_MODULE_CACHE_PATH=$run_dir/ModuleCache" \
    'OTHER_CFLAGS=$(inherited) -ffile-prefix-map=$(SRCROOT)=.' build

echo "Native harness, four XCTest bundles, and unsigned Release build passed."
echo "App launch, signing, sandbox behavior, audio, and live SIP remain separate checks."
