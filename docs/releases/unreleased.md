# Unreleased source cleanup after 2.0.3

Application metadata stays at **2.0.3 (build 154)**. This is a source-only update;
no new application release, signature or deployment is implied.

## Audio failure containment

The later audio-recovery update adds a shared failure gate, explicit Retry Audio,
checked conference connections, privacy-safe diagnostics, stale-media protection
and a headless native policy harness. See [audio recovery](../AUDIO_RECOVERY.md).
It prevents repeated failed attempts; it does not claim to remove the first
CoreAudio timeout or establish live-device acceptance. No application was installed.

## Recording ownership and shutdown

- Recording destination access belongs to the recording's call/session and is
  transferred to that session's asynchronous finalization completion. A prior
  conversion can no longer use a controller-wide flag or folder field to suppress
  another call's stop request or clear its access bookkeeping
- Normal Quit waits asynchronously for SIP shutdown and registered recording
  finalizations, including their main-queue completion callbacks. The main thread
  remains available to complete that work. Delayed SIP start/account-registration
  requests are blocked during termination, and the final callback rechecks that
  SIP is stopped before permitting exit
- Regression sources cover deferred redial/finalization, directory ownership,
  teardown, queued success/failure conversion and an empty completion barrier

These fixes address source-reviewed failure paths. Their native runtime behavior
has not been validated by this Linux cleanup. The WAV-readiness retry, private
output/recovery files and microphone-left/remote-right channel layout remain.

## Focused maintenance

- Remove reviewed unused store helpers, stale SIP-response code and ringback
  fields, and unused stored dependencies; preserve active feature paths
- Repair misleading device fixtures and remove obsolete orphaned tests/doubles
- Preserve the README repository-link corrections merged in PR #1
- Make microphone purpose text describe optional recording in English, German
  and Russian; complete the German recording labels and localize branded menu verbs
- Document staged builds for all six dependencies using the bundled sources
- Verify all source hashes, pin all 24 bundled archive hashes, check every linked
  archive, and fail explicitly when native tools or valid plist data are missing
- Add a complete macOS validation entry point and recording-library credit notices

## Preserved behavior and data

The saved-credential Keychain namespace, existing trust bundle, SIP/account and
recording preferences, recording consent default, private file modes, collision
handling, source-track recovery, WAV-readiness retry and left/right channel layout
are unchanged. Existing localization keys and nib object IDs, source archives,
PJSIP patches, inherited licences and original notices are retained. No security
permissions were changed, and no real calls or recordings were used.

## Validation and rollback

Six portable recording-lifecycle model tests passed on Linux, alongside dependency
manifest/inventory, localization structure, shell syntax and patch dry-run checks.
See [validation commands and limits](../VALIDATION.md). Portable checks and the
lifecycle model do not replace XCTest, a macOS build, native codec execution,
launch/signing checks, or a separately approved manual SIP/audio test plan.

The review baseline was `ea2769e430c8db3f90e88cc71a8fa7509420bb4b`. While this
cleanup was being prepared, README link-only PR #1 was merged as
`d68c372c5465d78f843bc807690c9edb09807c7b`; that concurrent change is preserved as
the publication parent. If rollback is needed after publication,
revert the published cleanup commit(s), newest first, on a clean working branch;
inspect the resulting diff and rerun the appropriate validation. Use the exact
published commit IDs from the publication summary, rather than resetting or
force-pushing `main`. Existing binary releases were not replaced by this cleanup.
