# Pending and slow audio recovery — 26 October 2026

Issue [#64](https://github.com/jpskidmore/telephone-jps/issues/64), source baseline `810220849eaacae92ac69cc1834cf5eaf6ce354b` plus this change. Source work only; the installed release is unchanged.

## Result and ownership

The application menu shows Trying audio… with a native indeterminate spinner as soon as a current audio command is admitted. After five monotonic seconds it shows Audio is taking longer… and explains that the operation is still running. Five seconds is a presentation threshold, not a timeout, estimated completion time or driver-hang diagnosis. Run-loop scheduling is best effort and may deliver later; the callback rechecks elapsed monotonic time.

The watchdog follows the current agent object, endpoint generation and selection revision. Superseding an operation resets its presentation clock. A late timer or native completion cannot replace a newer command's status. Actual completion removes the spinner; a failed completion restores Audio unavailable: Retry Audio. Audio recovered is shown only for a matching observed command that began with failed audio and ends with the actual failure gate cleared. Ordinary pending selection, stopped endpoints and the null-sound clock are not reported as recovery.

The existing atomic selection revision is now exposed read-only. Lifecycle start/stop admission publishes invalidation before native scheduling, so pending feedback is removed promptly even while an old backend command is held. Native worker ownership, revisions and completion gates remain intact. Termination cancels the presentation timer; stale timer callbacks remain harmless.

The timer does not cancel or interrupt native work, release its pending flag, clear failure, enable duplicate Retry, reopen devices or restart services. Direct and menu Retry remain blocked while a command is pending. The transient 300×24-point menu view uses a native spinner and label; the underlying menu title, accessibility name and help stay current. Completed/failed states restore the ordinary native menu action. No call-card or Settings window geometry changes.

Recovery guidance does not add SIP addresses, credentials, device names, call contents or recording destinations to diagnostics. Actual provider calling, physical-device recovery, naturally occurring hang duration, microphone grants and proficient VoiceOver remain separately unverified in #62, as the owner requested.

## Verification

Fresh local Xcode 27.1 / Swift 6.4, arm64, macOS 27.0.1; deployment remains macOS 15.6.

- Complete isolated Telephone suite: **328 XCTest + 48 Swift Testing cases**, zero failures. This includes 19 new watchdog/presentation cases and two new lifecycle admission cases.
- Deterministic injected clocks and manually fired cancelled timer tokens verify Trying → slow at the five-second threshold, early/late delivery, duplicate updates, actual completion/failure, agent/revision/generation replacement, stopped endpoint, termination and pre-menu termination. Direct duplicate Retry stays blocked.
- Existing held audio-open regression verifies main responsiveness while a synthetic backend blocks; current lifecycle checks retain pending ownership until matching native completion. The separate fresh-source SIP harness exercises the real WaitingThread with inert native endpoint boundaries.
- Inspected four native Trying/slow captures in Light and Dark: readable labels and visible spinner with no clipping/overlap. Native assertions verify fixed 300×24 bounds, fitting text/spinner, current accessibility labels/help and ordinary native-action restoration.
- The first build found a test-class name collision with an existing call-card test. The new class was renamed; the final build and full execution pass. Review also found that pre-menu termination must not require audio collaborators; the setter now cancels presentation without querying a backend before menu installation, with a regression test.
- Separate production audio-gate harness: **309 component assertions passed**. Fresh-source real-worker SIP lifecycle harness: **32 checks passed**. Source-wiring checks: **11 passed**. None uses physical devices or a real SIP endpoint.
- Other framework suites were not rerun because their source is unchanged. Component assertions and source-wiring checks below are separate from the 376 native suite cases.

Final local build/run evidence:

- `/private/tmp/jps-audio64-verified-build-20261026.log`
- `/private/tmp/jps-audio64-verified-tests-20261026.log`
- `/private/tmp/jps-audio64-verified-20261026.xcresult`

Source, log and capture hashes and component results are in the adjacent JSON record.

## Reproduction and references

Follow `docs/VALIDATION.md`: build TelephoneTests locally, create the unique-identity nib-free host with `Scripts/prepare-isolated-test-host.py`, then run test-without-building using its generated xctestrun. Never start the production nib/profile to make tests pass. Run native test-manager sessions serially. The separate audio gate harness uses injected fake backend operations; the SIP lifecycle harness replaces native endpoint/transport/media boundaries.

Apple references checked on 26 October: [progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) and [Timer](https://developer.apple.com/documentation/foundation/timer). The retrieved Markdown guidance confirms indeterminate feedback for unknown duration, optional cancellation only where safe, and best-effort run-loop delivery. These are established APIs, not new macOS 27 requirements; supported deployment remains macOS 15.6.

No cloud workflow, packaging, installation, release or real profile access is part of this source fix. After verified publication the next ranked item is #65.
