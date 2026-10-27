Version **3.7/build 166** is published as [public GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.7). It includes the latest history, Contacts, audio and recording fixes through #69. **920 fresh local suite cases passed**, and all seven release downloads match their recorded hashes. No local installation was performed. Read [3.7 publication proof](docs/releases/3.7-verification.md).

For current status, the ordered roadmap and maintenance instructions, start with
[Current maintenance](docs/MAINTENANCE.md). Older release and audit records are
dated evidence, not outstanding work or new test results.

Historical version **3.5/build 162** added one compact dialler, configurable Guided routes and combined call history. It was built, tested, installed and published locally. Read [the dial-plan guide](docs/DIAL_PLANS.md) and [3.5 release notes](docs/releases/3.5.md).

<p align="center">

  <img src="docs/assets/jps-telephone-blue-icon.png" width="180" alt="jps Telephone blue app icon">
</p>

<h1 align="center">jps Telephone</h1>

<p align="center">
  A blue-branded macOS SIP softphone with optional automatic, two-channel call recording.
</p>

<p align="center">
  <a href="https://github.com/jpskidmore/telephone-jps/releases/tag/v3.7">Latest release: 3.7 (166)</a>
  <a href="https://github.com/jpskidmore/telephone-jps/releases/tag/v2.1.8">Retained baseline: 2.1.8 (160)</a>
  <img alt="macOS 15.6 or later" src="https://img.shields.io/badge/macOS-15.6%2B-147EFB?logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/architecture-Apple%20silicon-000000?logo=apple">
  <a href="LICENSE"><img alt="GPL version 3" src="https://img.shields.io/badge/license-GPLv3-blue"></a>
</p>

> [!IMPORTANT]
> **3.7 is published on GitHub; it has not been installed locally.** Fresh validation passed 920 suite cases, and all seven uploaded/downloaded asset sizes and SHA-256 hashes match. The immutable release source is [`58956a9`](https://github.com/jpskidmore/telephone-jps/commit/58956a9906cbe1221640a926446341e6a71fdcb9). Read [delivery proof](docs/releases/3.7-verification.md). Real provider/hardware/grant/playback and proficient VoiceOver acceptance remain pending in #62.
>
> Read [the verified repair map](docs/REPAIR_VERIFICATION.md), [tracked evidence](docs/audit-2.1.8/repair-progress.json), [3.0 notes](docs/releases/3.0.md) and [maintenance handover](docs/BUG_FIX_HANDOVER.md). The owner chose public repository visibility on 21 October 2026. Work stays on main, and all builds remain local with `[skip ci]` commits and no cloud dispatch.
>
> [Audio recovery](docs/AUDIO_RECOVERY.md) keeps repeated failures gated and moves native work off the interface thread. One native driver operation can still stall its worker; real SIP/audio and VoiceOver remain manual acceptance limits. [Recording recovery](docs/RECORDING_RECOVERY.md) retains captured audio after export failure.
> Call recording is disabled by default. Only enable it when recording is lawful and everyone whose consent is required has consented.

## Historical 3.5.1 hotfix — 8 October 2026

**3.5.1/build 163 was published and installed on 8 October 2026.** The Guided routes menu crash is fixed; the compact dialler, routing and combined history remain unchanged. For the 8 October 2026 release, all four local suites passed **665 test cases, zero failures**. Built from [`e111e5d`](https://github.com/jpskidmore/telephone-jps/commit/e111e5daee9e57f26c66c9a42d40b6f1f4f25edc), installed at `/Applications/jps Telephone.app`, and published as [GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.5.1). All seven uploads match local sizes and SHA-256 digests. The owner reported “tested - looks good”. Read [3.5.1 verification](docs/releases/3.5.1-verification.md). The separate 170 routing cases remain historical 3.5 evidence bound to unchanged inputs.

## Historical 3.5 release and Guided routes

Open **Settings → Dial plan** to set country/area defaults and assign outgoing
connections or blocks by number category. Add precise prefix exceptions and use
Test to preview the winning route without calling. Incoming, outgoing and missed
calls are consolidated across accounts; callbacks resolve today's plan and the
origin badge derives from the configured account name. Emergency routing stays
unset until a suitable provider is explicitly selected.

The [3.5 download page](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.5)
contains verified app/source ZIPs, guides, release notes, BUILD-VERIFICATION and
checksums. All 57 app file payloads and six symlinks match the signed/extracted/
installed copies; all 1,417 source ZIP payloads match the tagged commit. Read
[publication proof](docs/releases/3.5-verification.md), its
[JSON record](docs/releases/3.5-verification.json) and
[the user/maintenance guide](docs/DIAL_PLANS.md). The package is ad-hoc signed and
unnotarised; provider/physical-device and proficient VoiceOver acceptance remain
manual boundaries. That release was private when published; the owner chose public repository visibility on 21 October 2026.

## Historical 3.0 release and private access

Version **3.0/build 161** was published as Latest before the 3.5 preparation. All 50 baseline
findings #2–51 have recorded verified repairs; the full four-suite local run passed
**617 automated test cases, zero failures**. Component assertion counts and
manual limits are recorded separately in [VALIDATION.md](docs/VALIDATION.md).
The [3.0 download page](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.0)
contains the verified app/source ZIPs, release notes, repair records,
BUILD-VERIFICATION and checksums. The historical 3.0 installed app matched all 59 extracted app
file payloads; all 1,400 source ZIP file payloads match the release commit.
See [publication and package proof](docs/releases/3.0-verification.md) and its
[JSON record](docs/releases/3.0-verification.json).

At that historical publication, repository contents, issues and downloads required authorised GitHub access. Current repository access is public by the owner’s 21 October 2026 choice.
The historical [2.1.8 release](https://github.com/jpskidmore/telephone-jps/releases/tag/v2.1.8)
remains unchanged: build 160 from `9a32ae8`, with its original app/source ZIPs,
checksums and verification files. The accepted design is preserved: Icon rail
Settings with Titled sections and one Accounts-sized window, Dial bar with one
recent call, Pocket call cards, native close controls, UK English, Light/Dark,
green Online and red Offline.

All retained release tags and their uploaded assets are immutable. The v3.0 source ZIP
retains the preparation-time documentation snapshot at `6363412`; current main
documentation records completed publication without replacing that archive.

Apple silicon and macOS 15.6+. The published local 3.0 package is ad-hoc signed and
unnotarised. Its verification records retain the limits of the controlled tests;
they do not establish that every possible bug or live-device issue is eliminated.

## What it does

The interface is UK English only, with UK dates and 24-hour time. International
phone numbers and contact names remain supported.

jps Telephone retains the original Telephone SIP calling experience and adds:

- one compact dialler and combined incoming/outgoing/missed-call history;
- configurable country/area expansion, Guided routes, prefix exceptions and blocks;
- callbacks resolved by the current plan, with automatic account-name badges;
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

To enable recording, open **jps Telephone → Settings → General**, choose a folder and format, then tick **Automatically record all calls (ensure everyone consents)**. Connected calls show a red **● REC** indicator. The default destination is `Downloads/jps Telephone Recordings`.

More detail is available in [RECORDING.md](RECORDING.md).

## Build from source

The 50-issue repair gate and 3.0 publication are complete. Build future changes
locally from their exact main revision and record new verification evidence. Do not
launch cloud workflows; include `[skip ci]` in pushed commits. Preserve the
historical v2.1.8 and v3.0 tags/assets and the user's settings, credentials and call data.

The repository contains application source, tests, blue artwork, pinned arm64
dependency libraries and the unmodified upstream archives under
`ThirdParty Sources/`. The 3.0 physical-device UID repair includes a reviewed
CoreAudio driver archive rebuild; see [dependency provenance](docs/DEPENDENCY_BUILDS.md).

Requirements:

- Xcode with the macOS SDK;
- Apple silicon Mac;
- Python 3 and `rg` for the dependency/release verification scripts.

Build the release configuration:

```sh
jpsReleaseDerivedData=$(mktemp -d /private/tmp/jps-telephone-release.XXXXXX)
xcodebuild \
  -project Telephone.xcodeproj \
  -scheme Telephone \
  -configuration Release \
  -derivedDataPath "$jpsReleaseDerivedData" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_MODULE_CACHE_PATH="$jpsReleaseDerivedData/ModuleCache" \
  'OTHER_CFLAGS=$(inherited) -ffile-prefix-map=$(SRCROOT)=.' \
  build
```

Keep executable build products outside FileProvider/iCloud-managed storage;
generated FinderInfo and coordinated file opens interrupted an earlier local run.

Run the ordinary (unsanitized) focused recording tests and dependency checks:

```sh
./Scripts/run-recording-tests.sh
./Scripts/verify-vendor-security.sh
```

For the recording harness, four native test bundles and an unsigned Release
build, the combined entrypoint is `./Scripts/run-macos-validation.sh`. Keep its
hosted test environment isolated; normal app startup can load real user data.
The historical 3.5 four-suite run passed 664 cases locally using a synthetic nib-free Debug host.
The 8 October 3.5.1 release record reports 665 fresh cases for that release;
see [its test proof](docs/releases/3.5.1-tests.json). Neither result certifies later changed code.
See [VALIDATION.md](docs/VALIDATION.md) for exact reproduction, observed checks and
completed package/publication checks and remaining manual acceptance.

For a local or downloadable ad-hoc build, sign nested code and apply the
documented ad-hoc-only library-validation exception:

```sh
./Scripts/sign-adhoc-release.sh \
  "$jpsReleaseDerivedData/Build/Products/Release/jps Telephone.app"
./Scripts/verify-adhoc-release.sh \
  "$jpsReleaseDerivedData/Build/Products/Release/jps Telephone.app"
```

Do not use the ad-hoc signing script for a Developer ID release. A Developer ID
build should keep normal library validation and sign the app and embedded
frameworks with the same Apple Team ID.

## Dependency builds

The complete [dependency rebuild guide](docs/DEPENDENCY_BUILDS.md) covers the six
bundled source archives: Opus, libogg, LAME, libopusenc, LibreSSL, and PJSIP. It uses
an isolated staging directory, the checked-in PJSIP configuration and patches, and
explicit arm64/macOS 15.6 settings. The general six-library recipe remains
source-derived. The narrow 3.0 CoreAudio UID object/archive rebuild was executed
locally and has pinned hashes and native fixture provenance.

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
