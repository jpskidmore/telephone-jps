# Changes in the jps edition

This document records the functional changes made to the original [Telephone](https://github.com/64characters/Telephone) source and explains why each group exists. This clean source snapshot is based on upstream commit [`14067fb1`](https://github.com/64characters/Telephone/commit/14067fb1); the complete earlier history remains available from the upstream repository.

## Edition identity and macOS compatibility

| Change | Purpose |
| --- | --- |
| Blue icon set and `jps Telephone` display name | Makes the custom build visually distinct from the original app and prevents users opening the wrong edition. |
| Bundle identifier `uk.jpsit.telephone` | Separates this edition's application identity and preferences from other Telephone builds. |
| Independent Keychain service namespace | Keeps SIP credentials isolated from the App Store app and earlier ad-hoc builds while allowing this edition to remember its own credentials. |
| macOS 15.6 deployment target and Apple silicon build | Matches the supported machine and current Xcode toolchain used for this release. |
| Fixed-size destination token field | Avoids an AppKit intrinsic-size update loop seen with newer macOS/Xcode versions. |
| Updated XIBs, Swift settings, and receipt/store compatibility code | Keeps the inherited interface and mixed Objective-C/Swift project building cleanly with the newer toolchain. |

## 1.8 — automatic stereo recording

| Change | Purpose |
| --- | --- |
| **Automatically record all calls** checkbox | Lets the user opt into automatic recording while keeping recording off by default. |
| PJSIP conference-bridge capture | Records both sides of a connected SIP call from the app's own media graph. |
| Separate local and remote mono tracks | Makes it possible to preserve speaker separation during finalization. |
| Local microphone on left; remote party on right | Produces predictable two-party stereo files that are easier to review, transcribe, and edit. |
| Red **● REC** indicator | Makes active recording visible during the call. |
| Hold and mute mirroring | Prevents locally muted or locally held microphone audio being added to the recording. |
| Recovery of mono tracks if merging fails | Avoids discarding recoverable call audio when finalization cannot complete. |

## 1.9 — simple output choices

| Change | Purpose |
| --- | --- |
| Recording-folder chooser | Gives the user control over where call data is stored. |
| OGG option: 24 kbit/s VBR Ogg Opus | Minimizes storage use where some voice-quality loss is acceptable. |
| MP3 option: 64 kbit/s independent stereo | Provides a widely compatible, space-efficient recording with good voice quality. |
| Source option: 16-bit PCM WAV | Avoids additional lossy compression and preserves the decoded audio PJSIP supplies. |
| Three plain format names only | Keeps codec and quality details out of the normal interface. |

All three formats retain strict channel separation. “Source” does not save compressed RTP codec packets; it saves lossless PCM after PJSIP has decoded the call audio.

## 2.0 — reliability and security hardening

| Change | Purpose |
| --- | --- |
| PJSIP 2.17, LibreSSL 4.3.2, and Opus 1.6.1 | Replaces older networking, TLS, and audio-codec dependencies. |
| Exclusive, collision-safe output creation | Prevents two calls with the same generated name from overwriting one another. |
| Output mode `0600` and private temporary directory mode `0700` | Restricts recordings and working tracks to the current user. |
| Background finalization on a serial utility queue | Prevents WAV merging and MP3/Ogg encoding from blocking the app's main interface. |
| Security-scoped folder access held through completion | Keeps user-selected destinations valid until asynchronous encoding actually finishes. |
| Recorder-destruction retry handling | Avoids invalidating PJSIP recorder identifiers before destruction has succeeded. |
| Validation of both mono tracks and every encoder setup result | Fails safely rather than silently producing corrupt or incomplete output. |
| Removal of participant/path logging | Reduces disclosure of call metadata and private filesystem locations in logs. |
| Removed disabled-library-validation entitlement | Restores hardened-runtime library validation because the app uses statically linked codecs. |
| Preferences, phone-scan, and media-log fixes | Removes a null dereference, guards absent phone values, and corrects a PJSIP media log format mismatch. |
| Focused recording harness and vendor-security script | Makes the collision, stereo, encoder, asynchronous, dependency, and entitlement behavior repeatably testable. |

## 2.0.1 — ad-hoc distribution repair

The normal project entitlements continue to enforce hardened-runtime library
validation. A Developer ID build signs the app and its embedded frameworks with
one Apple Team ID, which satisfies that validation.

An ad-hoc signature has no Apple Team ID. Version 2.0.0 therefore passed static
signature verification but macOS terminated it at launch when it tried to map
the embedded `Domain.framework`. Version 2.0.1 adds a dedicated distribution
script that applies the library-validation exception only to the ad-hoc app
bundle. The app sandbox and hardened runtime remain enabled. This exception is
not needed, and should not be used, for a future Developer ID release.

## 2.0.2 — recorded-call teardown repair

The 2.0.1 crash reports showed Objective-C aborting in `CallController` after a
recorded call ended. Call-window deallocation routed through `stopRecording`,
which attempted to create a weak reference to the controller after its
deallocation had already begun. Multiple end-of-call callbacks could also ask
to finalize the same recording and release a security-scoped destination while
the asynchronous stereo encoder was still using it.

Version 2.0.2 gives deallocation a weak-reference-free cleanup path and makes
recording finalization idempotent until its completion callback runs.
It also adds a regression test for the precise controller-deallocation path and
updates stale help-menu tests so the complete Telephone test bundle builds and
runs again.

## 2.0.3 — recording finalization timing repair

Real call logs showed AudioToolbox returning `kAudioFileInvalidFileError` at
the exact instant a SIP call disconnected, although the retained left/right
WAV tracks were valid immediately afterward. The converter treated that
transient close/flush state as permanent failure and removed the reserved MP3
or Ogg destination.

Version 2.0.3 retries transient invalid or incomplete WAV opens for up to two
seconds on the existing background encoder queue. A regression test recreates
the timing window by replacing an incomplete track with a finalized WAV while
conversion is waiting.

## Unreleased — recording ownership and reviewed cleanup

The source update after 2.0.3 moves destination-access ownership from a reusable
call controller to the individual recording call/session. Finalization takes its
own destination-access lifetime, so a new call in the same window can stop and
finalize independently while the old conversion is still pending. Normal Quit
waits asynchronously for both SIP shutdown and registered recording completions,
including the main-queue callbacks, without blocking the interface.

The update also removes reviewed dead code, repairs stale tests, completes
localized recording explanations, reuses the existing repository-link rename,
and adds staged build instructions for all six dependencies. Validation scripts
now pin/check the full archive inventory and reject missing tools or invalid
entitlement plists instead of treating those errors as successful checks.

The initial cleanup was source-only. The later [audio-recovery CI](docs/VALIDATION.md)
passed an unsigned native build and standalone harnesses. Version/build remain
2.0.3/154. During that initial cleanup, no native build,
XCTest, recording harness, signing, app launch or live call was run in the Linux
cleanup environment. See [the cleanup notes](docs/releases/unreleased.md) and
[validation instructions](docs/VALIDATION.md) before treating the update as ready
for binary distribution.

## Main implementation locations

- `Telephone/AKStereoRecording.h` and `.m`: secure output creation, stereo merge, MP3/Ogg encoding, and cleanup.
- `Telephone/AKSIPCall.h` and `.m`: per-call recorder lifecycle and PJSIP conference connections.
- `Telephone/CallController.m`: automatic start/stop orchestration and background finalization.
- `Telephone/GeneralPreferencesViewController.m` and `Telephone/Base.lproj/GeneralPreferencesView.xib`: recording preferences UI.
- `Telephone/ActiveCallViewController.m` and its XIB: visible recording indicator.
- `Tests/RecordingHardeningHarness.m`: focused recording and encoder regression harness.
- `Scripts/run-recording-tests.sh`: the ordinary, unsanitized recording harness build and run.
- `Scripts/verify-dependency-manifests.py`: portable source/binary hashes, inventories and linked-library checks.
- `Scripts/verify-vendor-security.sh`: native dependency versions, all archive architectures, metadata, and parsed entitlement checks.
- `Scripts/run-macos-validation.sh`: focused harness, all four XCTest bundles and unsigned Release build.
- `Scripts/sign-adhoc-release.sh`: nested-code signing and the ad-hoc-only library-validation exception.
- `Scripts/verify-adhoc-release.sh`: validates the finished app's signatures, version, architecture, and distribution entitlements.

For exact release notes, see [CHANGELOG.md](CHANGELOG.md). For user-facing recording behavior, see [RECORDING.md](RECORDING.md).
