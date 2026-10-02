#!/bin/sh
# Compile in an isolated checkout. No app launch, app-hosted XCTest, SIP or mic.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "Isolated native validation requires an Apple silicon Mac with Xcode." >&2
    exit 69
fi
for tool in xcodebuild xcrun python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing prerequisite: $tool" >&2; exit 69; }
done
xcodebuild -version
xcrun --sdk macosx --show-sdk-path
python3 Scripts/verify-dependency-manifests.py
python3 Tests/test_audio_recovery_integration.py
python3 Tests/test_recording_lifecycle_model.py
./Scripts/run-audio-device-tests.sh
./Scripts/run-recording-tests.sh
mkdir -p build/validation
run_dir=$(mktemp -d "$project_root/build/validation/audio.XXXXXX")
echo "Isolated validation output: $run_dir"
xcodebuild -project Telephone.xcodeproj -target Telephone \
    -configuration Release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO "SYMROOT=$run_dir/Products" "OBJROOT=$run_dir/Intermediates" \
    "CLANG_MODULE_CACHE_PATH=$run_dir/ModuleCache" \
    'OTHER_CFLAGS=$(inherited) -ffile-prefix-map=$(SRCROOT)=.' build
printf '%s\n' "Standalone policy/recording harnesses and unsigned Release build passed." \
    "No application launch, signing, installation, app-hosted XCTest or live audio/SIP acceptance was performed."
