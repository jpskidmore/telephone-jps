#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then
    echo "Audio device controller tests require macOS and the Foundation SDK." >&2
    exit 69
fi
command -v xcrun >/dev/null 2>&1 || { echo "Missing prerequisite: xcrun" >&2; exit 69; }
xcrun --find clang >/dev/null
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/telephone-audio-device-tests.XXXXXX")
trap 'rm -rf "$build_directory"' EXIT HUP INT TERM

# Compile the same gate used by the application against an injected fake. No
# application host, vendor archives, PJSUA, CoreAudio, SIP, or hardware access.
xcrun clang -isysroot "$sdk_path" -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -I "$project_root/Telephone" \
    "$project_root/Tests/AudioDeviceControllerHarness.m" \
    "$project_root/Telephone/AKAudioDeviceController.m" \
    -framework Foundation \
    -o "$build_directory/audio-device-controller-harness"

"$build_directory/audio-device-controller-harness"
