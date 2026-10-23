# macOS 27 practical acceptance matrix

Issue [#62](https://github.com/jpskidmore/telephone-jps/issues/62). Prepared 23 October 2026 after source repair [a69ed93](https://github.com/jpskidmore/telephone-jps/commit/a69ed93c00ce20768883473a7f48e278fe719bf7).

**Practical acceptance is incomplete; #62 remains open.** Every practical scenario below is **unverified**. This document is a repeatable worksheet, not evidence that its procedures were executed.

## Run record and result rules

Create a new record for each exercised scenario/variant, identifying the exact local candidate, source and bundle hash. Do not overwrite dated earlier results. Record:

- run id
- scenario id
- variant
- tested at ISO8601 with timezone
- tester
- result
- app version
- app build
- source commit
- app bundle SHA256
- configuration and signing identity
- installed or isolated host
- macOS version and build
- SDK and Xcode version
- hardware model and architecture
- display scale
- appearance and accessibility settings
- input output device models and connections
- provider and controlled endpoint aliases
- permission and folder grant state
- authorisation reference
- steps actually performed
- observed result
- redacted evidence reference
- failure issue
- reason if not exercised or not applicable

Use passed, failed, blocked, unverified or not applicable. Passed requires the stated observations and evidence for that exact run. A mismatch is failed and links to a GitHub issue; an unavailable prerequisite is blocked. Absence of execution/evidence remains unverified; not applicable requires an explicit reason.

Use controlled destination/provider aliases and redacted evidence. Keep credentials, real account/telephone details, participant speech and call content out of GitHub. Store any private evidence separately and reference its identifier. Obtain participant consent for capture. Specify a controlled destination/provider before calls; never use an emergency number. Use isolated profiles and scratch files for failures/recovery and grant variants; preserve production data and system preferences.

## Practical scenarios — all unverified

| ID | Scenario | Controlled procedure | Pass observations |
| --- | --- | --- | --- |
| CALL-01 | Outgoing | Call an agreed controlled endpoint; answer remotely; confirm both directions of audio; end locally, then repeat with remote hangup. | Correct destination/provider and one call; truthful connecting/active/ended state; both participants confirm media; end removes active media and restores ended actions. |
| CALL-02 | Incoming / decline | Call from the controlled endpoint; answer once, then repeat and decline. | Correct identity/account and configured ringtone; Answer/Decline work; answered audio works both ways; decline leaves no call or continuing ringtone. |
| CALL-03 | Mute / hold | Mute/unmute and hold/resume a controlled call; separately end while held. | Remote observations agree with controls; resume restores media; end while held finishes normally. |
| CALL-04 | Transfer | Exercise each transfer mode actually offered, using agreed endpoints; separately cancel the sheet. | Intended recipient receives transfer; no duplicate media; expected final state; cancellation leaves original call usable. Record provider rejection separately. |
| CALL-05 | DTMF | Send 0–9, *, # and each supported A–D/R input through keypad and keyboard to a controlled receiver. | Receiver confirms the exact sequence once per input; ordinary text entry elsewhere emits no tones. Record provider support per variant. |
| ROUTE-01 | Selected route | Compare accepted current route/help with a controlled outgoing call. | Actual provider/destination matches the admitted plan; accurate provider help; no unexpected fallback. |
| ROUTE-02 | Waiting cancellation | Make the selected test provider unavailable; enqueue one request, cancel it, then restore availability. | Waiting accurately identifies the request; cancellation removes it; restoration produces no delayed call. |
| ROUTE-03 | Pending request ownership | Queue a controlled request, change its route or remove/disable its account, then restore availability. | No unexpected reroute or stale-account call; compare immutable admitted request/account validation with the recorded expected policy before execution. |
| REC-01 | Actual capture / export | With participant consent, record known short local/remote phrases; stop/end and export each offered format under acceptance. | Both expected channels and interval captured; output plays with correct filename/format; successful export cleans only its own completed raw job. |
| REC-02 | Failed export / retry | In an isolated profile, export synthetic capture to deliberately unwritable scratch storage; defer, reopen, then Retry/Save Elsewhere. | Visible failure; original tracks retained; recoverable job rediscovered; retry produces usable audio; no silent overwrite or premature deletion. |
| REC-03 | Recovery / termination | With an isolated failed job, exercise Stay Open and Keep Files and Quit separately; reopen. | Stay Open cancels quit; keeping files preserves the job; reopen discovers it; retry succeeds. |
| REC-04 | Audio-loss segments | Use the agreed hardware-loss setup during a consented recorded call; explicitly retry audio. | Original segment finalises; no recording claimed during loss; successful retry may start a separately named segment; hangup remains possible. |
| DEVICE-01 | Physical device selection | Select each agreed input/output/ringtone device and perform controlled call/ringtone checks, including duplicate names if equipment exists. | Actual sound uses the intended physical devices and stable identity; labels and selection remain accurate. |
| DEVICE-02 | Hotplug / defaults | During idle and an agreed active call, disconnect/reconnect a removable test device and change the agreed default. | Responsive GUI; accurate device/state; visible failure or actual recovery; no hidden retry loop; explicit Retry Audio uses current selection. |
| DEVICE-03 | Failure / explicit retry | Reproduce an agreed test audio failure without changing production privacy grants; dismiss warning and use Retry Audio. | Persistent failure remains visible until actual recovery; generic notifications do not clear it; retry restores media or reports continued failure. |
| POWER-01 | Idle sleep / wake | Sleep/wake the test Mac while idle; then make controlled incoming/outgoing calls. | Registration settles truthfully; no stale cancelled request dials; subsequent calls/audio work. Record recovery time without inventing an SLA. |
| POWER-02 | Active sleep / wake | Sleep/wake during an agreed controlled call. | State reflects actual provider outcome; no phantom active timer/media; surviving call has confirmed audio or visible recovery; ending works. |
| GUI-01 | Whole-app appearance / geometry | Inspect all Settings panes/account tabs, compact/expanded history and incoming/connecting/active/ended cards in Light and Dark. | Readable, unclipped, usable controls; native Close and UK English. Record dimensions against version-specific design: dialler minimum content 368×104/368×268 expanded, Settings 592×337 outer; current card baseline 300-point width. Track requested change #74 separately. |
| GUI-02 | Accessibility materials / motion | Repeat key tasks with Reduce Transparency, Increase Contrast, both combined and Reduce Motion; record each variant. | Readable opaque semantic fallback/contrast outline as applicable; state understandable without colour alone; material changes retain focus/selection; appropriate motion. |
| GUI-03 | Keyboard / focus | Navigate dialler, Search → Status → Account → Table, Settings, call controls, menus and sheets without a mouse; collapse/reopen. | All actions reachable forward/reverse with visible focus; Return uses the selected original record; hidden filters do not retain focus after collapse. |
| GUI-04 | VoiceOver tasks | A proficient tester completes representative dial, history, Settings, call-control, menu and sheet tasks. | Correct spoken purpose/role/state, logical order and modal focus; tasks completed without sight. AX metadata alone cannot pass this row. |
| GUI-05 | Native Open/Save panels | From isolated flows, keyboard-navigate panels, cancel/reopen and complete a scratch operation; test actual sandbox grant separately. | Focus enters modal context and returns to invoker; cancel makes no unintended write; correct path, filename/accessories and overwrite handling. Check current macOS panel shortcuts/layout. |
| GUI-06 | Menus / symbols | Inspect actual app, context and popup menus in both appearances, with keyboard and VoiceOver. | Titles/states sufficient with or without images; appropriate native symbol visibility and disabled/selection/focus states; same-title account UUIDs remain selectable. |
| COMPAT-01 | Earlier supported OS | On separately available supported older hardware/OS, repeat the relevant task/appearance subset. | Fallback materials and availability guards work with no unavailable-API crash; macOS 27 evidence cannot pass this row. |

Each row above has an explicit unverified result in the adjacent [machine-readable matrix](MACOS_27_ACCEPTANCE.json). Fill the record before changing a result. Repeat relevant rows after lifecycle/presentation changes; record unsupported provider variants and unavailable equipment rather than assuming a pass.

## Existing controlled evidence — separate from practical outcomes

The exact source tree published as a69ed93 was locally built on arm64 macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), Swift 6.4, retaining the macOS 15.6 deployment target.

- Isolated Telephone suite: 289 XCTest + 48 Swift Testing cases, zero failures.
- Standalone AppKit production-controller harness: 68 separate component assertions.
- Native history captures at 368 and 520 points were inspected in Light/Dark; history filters, record identity, compact mode and focus-chain regressions passed.
- The host had a unique identity and no production startup nib; individual controllers loaded actual nib resources. Physical Mac model/display scale/provider/audio context were not recorded as a practical run.

Read [the #61 verification record](maintenance/2026-10-23-history-filters.md) and its [source/log hashes](maintenance/2026-10-23-history-filters.json). These results do not pass practical CALL, REC, DEVICE, POWER, whole-app GUI, proficient VoiceOver, actual-grant or earlier-OS rows. No installed candidate, package or release was produced for that repair.

## Current Apple documentation check

Reviewed Apple's [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes), including the actual AppKit section in its [published documentation data](https://developer.apple.com/tutorials/data/documentation/macos-release-notes/macos-27-release-notes.json), on 23 October 2026.

The AppKit notes describe reduced symbol-image visibility in menus for apps linked against newer SDKs; non-symbol images and XIB settings have distinct rules. Review actual menu usability against that policy before treating a missing symbol as a defect. They also describe Command-Shift-F access to panel Recents and window movement/resizing support for standalone file panels. GUI-05/06 must exercise the exact candidate/OS and relevant presentation mode; source review and older screenshots cannot establish their outcomes.

Also consult [Apple accessibility testing](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app), [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel), [NSSavePanel](https://developer.apple.com/documentation/appkit/nssavepanel), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus), the project's [design baseline](LIQUID_GLASS.md) and [validation guidance](VALIDATION.md). No new API adoption or change to availability guards is part of this worksheet.

## Remaining gate

A test operator must supply the exact candidate/build/hash, hardware/display/device context, controlled provider/endpoints and authorisation for applicable practical variants. A proficient VoiceOver tester and supported older OS are separate prerequisites. Record dated actual observations, log failures in GitHub and retain every unexercised row as unverified. Do not close #62 merely because this worksheet or an automated suite exists.
