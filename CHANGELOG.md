# Changelog

## jps Telephone 3.0 (build 161) — verified repairs, publication pending

The 50-issue repair gate passed. The next release is being built, signed,
installed and packaged locally; no published 3.0 binary is claimed yet.

- Preserve unreadable history, commit Clear History durably, reject stale reloads and deleted-account additions, and drain history before Quit
- Retain captured recordings in durable recovery jobs and offer Retry, Save Elsewhere, Reveal and Later after failed export
- Move audited SIP/audio operations to the serial backend worker, retain explicit audio recovery and identify devices by physical UID
- Correct startup/Offline/restart intent, transfer/callback ownership, delayed account/call completions, ringback reset and codec readiness
- Correct compact-window placement, keyboard/DTMF/timers, native accessibility purposes, credential failure handling and first-run readiness
- Prune expired subscribers, balance native resources/PJLIB/background activity and remove unused legacy categories
- Keep the accepted UK-English compact interface, native close controls, Light/Dark support and availability colours

All four local suites passed 617 automated test cases with zero failures. Native
component assertions and manual SIP/audio/sandbox/VoiceOver limits are separate.
The package is intended to be ad-hoc signed and unnotarised.

See [3.0 notes](docs/releases/3.0.md), [50-issue evidence](docs/REPAIR_VERIFICATION.md)
and [validation](docs/VALIDATION.md). The existing v2.1.8 tag/assets are unchanged.

## jps Telephone 2.1.8 (build 160) — titled Settings sections

- Align General, Sound and app-wide Network settings at the top of their panes
- Group related options under compact native headings and separators
- Keep the same Accounts-sized window across every pane and retain all existing controls and actions

See [release notes](docs/releases/2.1.8.md).

## jps Telephone 2.1.7 (build 159) — availability colours

- Show online availability in system green and offline availability in system red
- Preserve the compact main window, status symbols and availability actions
- Retain the existing Settings window size and controls

See [release notes](docs/releases/2.1.7.md).

## jps Telephone 2.1.6 (build 158) — interface refinements

- Align and space the compact main window controls and recent-call row consistently
- Rename Delete All to Clear Call History… and remove the duplicate history visibility command from More
- Keep all Settings panes at the Accounts pane's window size
- Distinguish app-wide Network settings from an account's Connection tab
- Preserve the visible history button, call/history actions, account options and network save prompts

See [release notes](docs/releases/2.1.6.md).

## jps Telephone 2.1.5 (build 157) — compact desktop interface

- Replace the wide Settings sidebar with an edge-to-edge icon rail and size each pane to its contents
- Use a compact dial bar with one recent call underneath and expandable full history
- Restore original-width call cards with one row of icon controls and an on-demand keypad
- Preserve calling, recording, account, history and settings actions, including Network save prompts
- Retain native close controls, readable titlebars, light/dark colors and accessibility material fallbacks
- Add native layout and lifecycle regressions for the compact interface
- Use UK English only; remove German and Russian resources and language-specific defaults
- Use UK date order, 24-hour time and English duration units without changing saved number-formatting choices
- Keep all four Settings rail icons within the narrow visible strip
- Keep the call backdrop beneath the caller and controls after switching call views
- Give call titlebars semantic backing for readable dark appearance while retaining the body material

See [release notes](docs/releases/2.1.5.md).

## jps Telephone 2.1.4 (build 156) — Settings and material repair

- Prevent initial sidebar selection from navigating before the detail hierarchy exists
- Replace the flat white window underlay with a native desktop-blending backdrop in Settings and call windows
- Preserve an opaque accessibility fallback and keyboard focus when materials change
- Keep the window title consistently named Settings
- Restore the standard macOS title bar and visible native close control in Settings
- Give the Settings title bar an opaque system backing while preserving the existing form and sidebar materials
- Add a complete Settings window initialization regression
- Preserve a downloadable candidate for local GUI acceptance before release publication
- Verify the app ZIP after extraction without Finder/resource metadata

See [release notes](docs/releases/2.1.4.md).

## jps Telephone 2.1.3 (build 155) — local test release

- Add system Liquid Glass to call controls and Settings navigation on macOS 26+, with native macOS 15 fallback
- Reorganize call presentation with a clearer caller/status hierarchy and larger labeled controls
- Replace Settings toolbar navigation with a native sidebar for the same four settings sections
- Fix bounded Foundation/receipt lifetime and malformed-data failures; see the bug review
- Include the previously unreleased audio recovery and recording-lifetime cleanup below
- Add a native test-release pipeline that checks four XCTest bundles, signs/verifies the arm64 app, and uploads exact source and checksums

See [release notes](docs/releases/2.1.3.md), [interface guidance](docs/LIQUID_GLASS.md),
[bug review](docs/BUG_REVIEW_2.1.3.md) and the downloadable build verification report.

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

Version/build remain 2.0.3/154. The initial cleanup was source-only; the later
audio-recovery CI passed an unsigned native build and two standalone harnesses.
Hosted tests and real-device acceptance remain separate; see
[cleanup notes](docs/releases/unreleased.md) and [validation limits](docs/VALIDATION.md).
No binary release or deployment was made.

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
