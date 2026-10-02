# Audio-recovery native validation — 2 October 2026

## First successful native candidate

- Commit: `fcd45a2f0fc12b5b9c0352091a4859ac6d3bd6fd`
- Run: [Isolated macOS validation 37037958671](https://github.com/jpskidmore/telephone-jps/actions/runs/37037958671)
- Job: [validate 110940728200](https://github.com/jpskidmore/telephone-jps/actions/runs/37037958671/job/110940728200)
- Runner: standard `macos-15`, arm64; macOS 15.7.9
- Toolchain: Xcode 26.3, Apple Swift 6.2.4, macOS SDK 26.2
- Result: completed successfully; `BUILD SUCCEEDED` at 17:03:39 UTC

## Executed results

- Dependency manifests: seven source-manifest files, 24 static archives and 21 linked libraries passed
- Audio integration wiring: 11 portable source checks passed
- Recording lifecycle: six portable model tests passed
- `AKAudioDeviceController`: **232 checks passed**, compiled and executed against fake backend operations
- Synthetic recording hardening harness: passed, using generated PCM/temp files and the real encoder implementation
- Telephone application: unsigned arm64 Release build passed

The policy harness links Foundation only. It does not initialize PJSUA or touch
audio hardware. The recording harness uses generated test data and file codecs,
not live microphone input. Both are standalone executables; neither launches the
Telephone application or its hosted test bundle.

## Not established

- No hosted XCTest execution, GUI launch or interactive UI verification
- No physical device, microphone, live SIP/call, or macOS 27 CoreAudio test
- No signing, installation, distribution release or deployment
- No proof that the first blocking hardware-open timeout is gone

The local Mac executor disconnected before source transfer/build. The successful
results above are from GitHub's clean hosted runner, not that Mac. Full device
acceptance must use the scenarios in [Audio Recovery](../AUDIO_RECOVERY.md).

## Warnings and follow-up

The build was successful, not warning-free. Its logs include inherited StoreKit
and notification-API deprecations, optional AppIntents metadata notices, and
`dsymutil` messages about remapped precompiled-module debug paths. Those messages
do not constitute live validation or a reason to weaken signing/security.

The run also identified nullability annotations on the new failure/completion
paths. These are corrected in the following candidate commit and rechecked by
the same branch CI before main is advanced. Build and harness results for later
commits are available in the workflow's normal run history; each publication
must use a successful run for the exact final candidate.
