# Event-driven call controls — 26 October 2026

Issue [#67](https://github.com/jpskidmore/telephone-jps/issues/67) is implemented and source-verified against main baseline `7e412da0ba5d7cf9fdb120b8d1de059becc277d6`. The owner authorised all remaining issues sequentially. The installed/released 3.6.1/build 165 and immutable releases are unchanged.

## Behaviour and ownership

The compact call card now derives its four controls from one immutable bitmask snapshot: confirmed/admitted call, actual cached mute/local/remote hold and independent native request-pending flags. Identical snapshots return immediately; changed snapshots write only changed native button properties and resolve symbols only when selection changes. Menu validation reads the same snapshot without manufacturing menu items. Geometry, native controls, labels, UK English and recording feedback remain intact.

A single one-second timer with 0.2-second tolerance publishes only `presentationDuration` changes. It does not validate controls, mutate general status, refresh the card/recording popover or query SIP. Elapsed time still comes from timestamps, including held/muted calls and delayed delivery. The consultation sheet retains its elapsed clock through a derived binding in its existing status slot, preserving hold/error messages. No new API requires a newer supported OS.

The timer uses a weak block and captures the current call's ownership. Inactive/disconnected calls, replacement, leaving the active view, removal and close invalidate it; stale timer objects cannot update a replacement. Loaded bindings are restored on explicit view reuse. Current-call KVO of the main-owned `localHold`/`remoteHold` cache is detached on inactivity, replacement, close and deallocation. This also covers native NONE/ERROR media updates that clear hold flags without a named hold notification. It introduces no new native media event or recording restart.

Hold/mute admission disables the matching control immediately (hold also disables Transfer). Completion reconciles actual cached state and failure feedback, guarded by call identity, lifecycle generation and closed state. The pending flag covers native request completion; provider hold acknowledgement still arrives through the native media path and is never inferred from acceptance. Existing main admission, serial worker/dialog checks and recording/history drains are preserved.

## Event inventory

| Boundary | Presentation update |
| --- | --- |
| Initial load, active view, connecting progress/hangup | Derive current snapshot |
| Calling, incoming, early, connecting, confirmed | Current-object delegate refresh; confirmation starts duration |
| Active media, local/remote hold, silent NONE/ERROR cache clears | Named callback or scoped cache observation |
| Hold/mute request admission and success/failure | Pending and actual cached selection reconciled immediately |
| Hangup admission and rejection/acceptance | Disable, restore on rejection, retire timer on acceptance |
| Audio-state and transfer-status callbacks | Current owner refresh; existing status/recovery behaviour retained |
| Call replacement, redial owner replacement, view departure/removal/close | Retire old timer/completions/observers; reset current snapshot |

All call delegate handlers reject another call or a closed owner. No later issue was implemented alongside this change.

## Actual bounded measurements

The same real-nib synthetic fixture ran on archived baseline and candidate, with actual native timers and AppKit run loop. After setup, four 2.2-second phases exercised one/four cards ordered front/out. Scoped instrumentation counted actual menu initialisers/validation and actual image/accessibility setters on fixture-owned buttons; it was restored after each test. These are operation counts, not source-derived estimates.

| Cards/windows | Timer firings before→after | Menu constructions before→after | Image writes before→after | AX label/value writes before→after | Process CPU sample before→after |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 visible | 11→2 | 44→0 | 22→0 | 44/22→0/0 | 3.906%→0.567% |
| 1 hidden | 11→2 | 44→0 | 22→0 | 44/22→0/0 | 3.375%→0.761% |
| 4 visible | 44→8 | 176→0 | 88→0 | 176/88→0/0 | 11.951%→1.368% |
| 4 hidden | 44→8 | 176→0 | 88→0 | 176/88→0/0 | 11.267%→0.987% |

Candidate steady phases also performed zero control refreshes, menu validations, status assignments or full presentation refreshes. Baseline status assignment caused two duration notifications per tick; candidate publishes one. CPU uses `getrusage` seconds/microseconds and monotonic wall time. These are short, fixed-order, single process samples including fixture/run-loop/AppKit work; they do not establish a population effect, battery savings, real-call CPU or App Nap behaviour.

Separate Time Profiler attachments to only the uniquely identified nib-free test host succeeded for both versions. Baseline 17.602s captured 894 samples (829 main-thread); candidate 18.138s captured 373 (310 main-thread). Sample stacks contained `callTimerTick` 88→4, `refreshVisibleCallControls` 59→1 and `refreshPresentation` 33→3. Capture includes delay/setup/teardown and all four phases; stacks overlap and are not call counts or a controlled equal-window CPU comparison. Setup/event refreshes in the candidate trace are expected. Raw traces/exports remain in local scratch; the JSON record includes paths, hashes and exact counters.

## Fresh validation

Local complete isolated Telephone suite: **377 XCTest + 48 Swift Testing, zero failures**. All 18 new cases passed, covering stable writes, tolerance/single timer, wall-clock delayed ticks, held/muted duration, pending/success/failure, actual selection before hold acknowledgement, stale completions/timers, incoming/outgoing confirmation, remote hold/audio failure, silent cache clears, hangup/close/removal/reuse and the compiled transfer nib. Production source was final in this run. A final extra reuse-binding assertion was then compiled and all 18 focused cases passed again; these overlap and are not added to the complete count.

Separate source/model checks: 11 audio integration checks and 6 recording lifecycle checks passed. An overly broad old wiring assertion rejected the newly added stale/closed-owner admission return; it now checks that admitted audio-failure handling still reaches off-hold signalling. The existing native failed-audio/off-hold regression also passed in the complete suite. Initial new fixture declarations were corrected before successful validation. No unchanged supporting framework suite is claimed as freshly rerun.

All hosted runs used a unique disposable bundle identity with `NSMainNibFile` removed, preserving production metadata. Calls/requests/defaults are synthetic and inert. No actual SIP account, audio recorder, Contacts, credentials or user history was loaded. Native Light/Dark geometry/control/accessibility-property regressions passed; no new screenshot or proficient VoiceOver acceptance is claimed.

## Reproduction and limits

Build locally with `xcodebuild ... build-for-testing` for TelephoneTests, then run `Scripts/prepare-isolated-test-host.py DERIVED_DATA`. Run `test-without-building` against `DERIVED_DATA/Build/Products/IsolatedTelephoneTests.xctestrun`, using `-only-testing:TelephoneTests/CallControlPresentationTests` for focused cases. To compare baseline, archive `7e412da` into disposable scratch, copy/register only the new test file and run only `testBoundedStableCallMeasurement`; new-regression selectors must not run against old code.

For profiling, copy the isolated xctestrun **inside its Products directory** (relative `__TESTROOT__` must resolve there), set TelephoneTests EnvironmentVariables `CC67_PROFILE_DELAY=10`, run only the measurement selector and attach `xcrun xctrace record --template 'Time Profiler' --attach PID --time-limit 18s --output PATH.trace --no-prompt` to the logged `CC67_PROFILE_READY` PID. Export `time-profile` with xctrace; never attach the normal installed application. The first scratch profiling setup used the wrong xctestrun directory and failed before launch; corrected captures both passed.

Physical sleep/wake, provider/audio devices, actual grants and proficient VoiceOver remain explicitly pending in [#62's practical matrix](../MACOS_27_ACCEPTANCE.md), as the owner requested. Source fixes do not imply installation/release. See the [machine-readable evidence](2026-10-26-call-controls.json).

Official Apple references rechecked 26 October 2026: [Timer](https://developer.apple.com/documentation/foundation/timer), [tolerance](https://developer.apple.com/documentation/foundation/timer/tolerance) (available since macOS 10.9), [responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), and [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes). Timer delivery may be late, so timestamps determine elapsed time; tolerance permits coalescing, without establishing this application's battery impact.
