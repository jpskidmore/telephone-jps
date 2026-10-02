# Changelog

## Unreleased audio-failure recovery after 2.0.3

- Contain repeated audio-device open failures across media, ringback, unmute and recording paths
- Keep audio failure visible and add an explicit Retry Audio action with current-device remapping
- Preserve signaling, finalize interrupted recording segments and guard delayed media/outgoing work
- Add privacy-safe error/timing diagnostics and fix enumeration-buffer cleanup on failure
- Add a standalone fake-backend native harness and an isolated unsigned-build runner

The first blocking hardware operation is not eliminated. See [audio recovery](docs/AUDIO_RECOVERY.md)
for behavior, validation limits and remaining device acceptance. This is not an
installation or a new downloadable release; version/build remain 2.0.3/154.

## Unreleased source cleanup after 2.0.3

- Give each recording its own destination-access and completion lifetime across redial and controller teardown
- Wait asynchronously for SIP shutdown and recording completion before normal Quit
- Add recording ownership/shutdown regression sources and a portable lifecycle model
- Remove reviewed unused code and repair stale or misleading tests
- Correct repository links and English/German/Russian recording and menu explanations
- Document all six dependency builds; verify source hashes, all 24 archive hashes/architectures and parsed entitlements
- Add a four-bundle macOS validation runner and recording-library notices

Version/build remain 2.0.3/154. This is an unbuilt source update, with native macOS
validation still required; see [cleanup notes](docs/releases/unreleased.md) and
[validation limits](docs/VALIDATION.md). No binary release or deployment was made.

## jps Telephone 2.0.3 (build 154)

- Remapped release compiler paths so downloadable binaries do not expose the
  local macOS account name or source checkout location.
- Added a release check that rejects application bundles containing absolute
  `/Users/...` paths.
- Fixed a SIP-recorder close/flush race that could make AudioToolbox briefly
  reject valid call tracks and remove the reserved final recording file.
- Finalization now retries transient incomplete-WAV errors for up to two
  seconds on its background encoder queue.
- Added a regression test that makes an initially incomplete WAV become valid
  shortly after finalization starts.

## jps Telephone 2.0.2 (build 153)

- Fixed the Objective-C abort that could close the application when a recorded
  call ended and its call window was released.
- Made recording finalization idempotent across hang-up, disconnect, window
  close, and controller teardown callbacks.
- Kept security-scoped recording-folder access alive until asynchronous stereo
  encoding has actually finished.

## jps Telephone 2.0.1 (build 152)

- Fixed an immediate launch crash in the downloadable ad-hoc build.
- Added a dedicated ad-hoc signing script that keeps the hardened runtime but
  permits the app to load its bundled ad-hoc-signed Domain and UseCases
  frameworks.
- Kept library validation enabled in the normal project entitlements so a
  future Developer ID build continues to enforce same-team framework loading.

## jps Telephone 2.0.0 (build 151)

- Upgraded PJSIP to 2.17, LibreSSL to 4.3.2, and Opus to 1.6.1.
- Prevented recording-name collisions from overwriting an existing call.
- Moved raw tracks to a private temporary folder and removed path details from logs.
- Moved stereo merge and MP3/Ogg compression off the main thread.
- Added recorder-finalization retries and kept folder access open until encoding finishes.
- Validated both source tracks and every encoder setup call before writing output.
- Removed the unnecessary disabled-library-validation entitlement.

## jps Telephone 1.9.0 (build 150)

- Added OGG, MP3, and lossless Source recording choices without exposing codec settings.
- Added a folder chooser for the call-recording destination.
- Made OGG the default for the smallest files (24 kbps Ogg Opus).
- Added 64 kbps independent-stereo MP3 for broad compatibility and good voice quality.
- Kept local audio strictly left and remote audio strictly right in every format.

## jps Telephone 1.8.1 (build 149)

- Changed call recordings to stereo WAV files.
- Put the local microphone on the left channel and the remote party on the right channel.
- Preserve the two mono source tracks if stereo finalization fails, so recoverable audio is not discarded.

## jps Telephone 1.8.0 (build 148)

- Added an opt-in General preference to record every connected call automatically.
- Added automatic two-way WAV recording through the PJSIP conference bridge.
- Added a visible red recording indicator during active recordings.
- Save finalized recordings to `Downloads/jps Telephone Recordings` with descriptive names.
- Keep automatic recording disabled by default and mirror mute/local-hold state in the recorder.

## 1.7
- Minimum deployment target 15.6.
- Swift 6.

## 1.6 - 2022-06-29
- macOS Big Sur.
- Apple silicon.
- Minimum deployment target 10.13.
- Fixed an issue where matching contact for an incoming call could not
  be found when the incoming phone number was exactly the same length
  as the significant phone number setting and the contact's phone
  number was longer than that.
- Remove user notification when incoming call is answered or declined.
- Allow the app settings to be copied to clipboard as text.
- LibreSSL 3.1.5.
