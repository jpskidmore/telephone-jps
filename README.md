<p align="center">
  <img src="docs/assets/jps-telephone-blue-icon.png" width="180" alt="jps Telephone blue app icon">
</p>

<h1 align="center">jps Telephone</h1>

<p align="center">
  A blue-branded macOS SIP softphone with optional automatic, two-channel call recording.
</p>

<p align="center">
  <a href="https://github.com/jpskidmore/telephone-jps/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/jpskidmore/telephone-jps"></a>
  <img alt="macOS 15.6 or later" src="https://img.shields.io/badge/macOS-15.6%2B-147EFB?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/architecture-Apple%20silicon-000000?logo=apple">
  <a href="LICENSE"><img alt="GPL version 3" src="https://img.shields.io/badge/license-GPLv3-blue"></a>
</p>

> [!IMPORTANT]
> The unreleased [audio-recovery changes](docs/AUDIO_RECOVERY.md) contain repeated failed audio opens and add explicit recovery. A first hardware timeout can still block; real-device acceptance remains separate.
> Call recording is disabled by default. Only enable it when recording is lawful and everyone whose consent is required has consented.

## Download

Download the tested application ZIP from the [latest GitHub release](https://github.com/jpskidmore/telephone-jps/releases/latest). The release also contains a complete source ZIP, checksums, and the verification report for the exact build.

This build targets Apple silicon and macOS 15.6 or later. It is ad-hoc signed but not Apple-notarized. After unzipping and moving the app to **Applications**, macOS may require you to Control-click the app and choose **Open** the first time.

## What it does

jps Telephone retains the original Telephone SIP calling experience and adds:

- a distinct blue icon, app name, and bundle identity;
- independent Keychain storage for SIP credentials used by this edition;
- an opt-in **Automatically record all calls** preference;
- a recording-folder chooser;
- stereo separation in every output: **your microphone on the left, the remote party on the right**;
- simple OGG, MP3, and Source choices without exposing codec settings;
- background finalization and compression so ending a call does not freeze the interface;
- collision-safe, private recording files and stronger failure recovery.

The complete history of the custom edition—including why each change exists—is in [JPS_CHANGES.md](JPS_CHANGES.md). Release-by-release notes are in [CHANGELOG.md](CHANGELOG.md).

## Recording formats

| Choice | Output | Intended use |
| --- | --- | --- |
| **OGG** | 24 kbit/s variable-bitrate Ogg Opus | Smallest files; highest space saving, with acceptable voice-quality loss |
| **MP3** | 64 kbit/s independent-stereo MP3 | Broad compatibility and good voice quality at a modest size |
| **Source** | 16-bit stereo PCM WAV at the call-audio sample rate | No additional lossy encoding; preserves the decoded audio supplied by PJSIP |

“Source” means lossless decoded call audio. It is not a copy of the original RTP packets or their compressed SIP codec bitstream.

To enable recording, open **jps Telephone → Preferences → General**, choose a folder and format, then tick **Automatically record all calls (ensure everyone consents)**. Connected calls show a red **● REC** indicator. The default destination is `Downloads/jps Telephone Recordings`.

More detail is available in [RECORDING.md](RECORDING.md).

## Build from source

The repository contains the application source, tests, blue artwork, the exact prebuilt arm64 dependency libraries used for the 2.0 releases, and unmodified upstream dependency archives under `ThirdParty Sources/`.

Requirements:

- Xcode with the macOS SDK;
- Apple silicon Mac;
- Python 3 and `rg` for the dependency/release verification scripts.

Build the release configuration:

```sh
xcodebuild \
  -project Telephone.xcodeproj \
  -scheme Telephone \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_MODULE_CACHE_PATH=build/ModuleCache \
  'OTHER_CFLAGS=$(inherited) -ffile-prefix-map=$(SRCROOT)=.' \
  build
```

Run the ordinary (unsanitized) focused recording tests and dependency checks:

```sh
./Scripts/run-recording-tests.sh
./Scripts/verify-vendor-security.sh
```

For the recording harness, all four XCTest bundles and an unsigned Release build,
use `./Scripts/run-macos-validation.sh` on a clean macOS test account. This runner
has not been executed in the Linux cleanup environment. See
[VALIDATION.md](docs/VALIDATION.md) for prerequisites and remaining release checks.

For a local or downloadable ad-hoc build, sign nested code and apply the
documented ad-hoc-only library-validation exception:

```sh
./Scripts/sign-adhoc-release.sh \
  "build/DerivedData/Build/Products/Release/jps Telephone.app"
./Scripts/verify-adhoc-release.sh \
  "build/DerivedData/Build/Products/Release/jps Telephone.app"
```

Do not use the ad-hoc signing script for a Developer ID release. A Developer ID
build should keep normal library validation and sign the app and embedded
frameworks with the same Apple Team ID.

## Dependency builds

The complete [dependency rebuild guide](docs/DEPENDENCY_BUILDS.md) covers the six
bundled source archives: Opus, libogg, LAME, libopusenc, LibreSSL, and PJSIP. It uses
an isolated staging directory, the checked-in PJSIP configuration and patches, and
explicit arm64/macOS 15.6 settings. Its commands were checked against the bundled
source but have not been executed on macOS during the current cleanup.

Verify the source manifest and prebuilt archive inventory on macOS or Linux:

```sh
python3 Scripts/verify-dependency-manifests.py
```

This checks seven source files and all 24 bundled static archives, including every
library referenced by the project. Hash agreement establishes snapshot integrity,
not upstream authenticity or source-to-binary reproducibility. Full architecture
and entitlement checks still require macOS. See [validation status and commands](docs/VALIDATION.md)
and [dependency licence/source inventory](ThirdParty/ENCODERS.md).

## Project lineage and licence

This is a modified edition of [64characters/Telephone](https://github.com/64characters/Telephone), based on upstream commit [`14067fb1`](https://github.com/64characters/Telephone/commit/14067fb1). The original copyright and licence notices are retained. This repository begins with a clean source-snapshot commit; upstream history remains available from the original project.

Telephone and this modified edition are distributed under the [GNU General Public License version 3](LICENSE). Third-party components retain their own licences; see their included source and [ThirdParty/ENCODERS.md](ThirdParty/ENCODERS.md).

This project is provided without warranty. It is not affiliated with or endorsed by the original Telephone maintainers.
