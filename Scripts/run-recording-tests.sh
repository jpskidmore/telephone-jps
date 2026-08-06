#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
mkdir -p build/tests

clang -fobjc-arc -fblocks -Os -mmacosx-version-min=15.6 \
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
