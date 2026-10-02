#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "Recording tests require an Apple silicon Mac and the macOS SDK." >&2
    exit 69
fi
command -v xcrun >/dev/null 2>&1 || { echo "Missing prerequisite: xcrun" >&2; exit 69; }
xcrun --find clang >/dev/null
xcrun --find lipo >/dev/null
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
for archive in ThirdParty/LAME/lib/libmp3lame.a ThirdParty/OpusEnc/lib/libopusenc.a \
    ThirdParty/Opus/lib/libopus.a ThirdParty/Ogg/lib/libogg.a; do
    test -s "$archive" || { echo "Missing archive: $archive" >&2; exit 66; }
    xcrun lipo "$archive" -verify_arch arm64
done
mkdir -p build/tests

xcrun clang -arch arm64 -isysroot "$sdk_path" -fobjc-arc -fblocks -Os -mmacosx-version-min=15.6 \
    -I Telephone \
    -I ThirdParty/LAME/include \
    -I ThirdParty/Opus/include/opus \
    -I ThirdParty/OpusEnc/include/opus \
    Tests/RecordingHardeningHarness.m Telephone/AKStereoRecording.m \
    ThirdParty/LAME/lib/libmp3lame.a \
    ThirdParty/OpusEnc/lib/libopusenc.a \
    ThirdParty/Opus/lib/libopus.a \
    ThirdParty/Ogg/lib/libogg.a \
    -framework Foundation -framework AudioToolbox \
    -o build/tests/recording-hardening-harness

build/tests/recording-hardening-harness
