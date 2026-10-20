# Waiting calls and individual cancellation — issue #58

The compact dialler now shows **Waiting N** while calls await their selected
connection's registration. Open the native popover to inspect each frozen
provider and destination, then cancel an individual request. The existing More
→ Cancel pending calls action still cancels all waiting requests.

Each summary contains copied strings and stable request/account UUIDs, without
exposing mutable SIP URIs or account controllers. Queue changes notify the GUI
on the main thread without sensitive payloads. Cancellation resolves the current
account and request UUID; stale rows cannot cancel a different request or revive
an expired one. The native SIP worker and registration lifecycle are retained.

The first waiting request starts one 30-second timer per account. Later requests
share that original deadline. Cancelling one preserves the exact timer and
expiry while others remain; removing the last invalidates it. Offline, account
disable/removal, failure, Quit and late-registration safeguards remain covered.

The count uses the existing route-status area. The default 368 × 104 window,
368 × 268 expanded history, destination minimum 160 points and existing 44-point
controls remain intact. Native buttons expose count, destination and provider
labels; keyboard focus follows the remaining row after cancellation and returns
to the destination when the queue empties. Focus scrolls into view in long lists.

## Verification

Local tests ran on **19 October 2026**, with final evidence and documentation
checked on **20 October**. A fresh unique nib-free Debug host used inert
synthetic accounts, isolated data and an offscreen native popover.

- **317 app cases passed, zero failures:** 269 XCTest plus 48 Swift Testing.
  Seven new cases cover immutable snapshots, exact deadline preservation,
  cancellation/late callbacks, two-provider content, stale rows, compact
  Light/Dark geometry, accessibility metadata and actual popover focus.
- The focused routing/dialler run passed **23 cases**. Its first attempt caught
  AppKit replacing the popover's Tab sequence on presentation. Explicit native
  key-loop setup fixed this; the repeated focused and complete suites passed.
- A separate review subagent found no remaining actionable findings. The
  historical 50-issue repair gate and whitespace checks pass. Unchanged
  framework and standalone routing results remain historical evidence.

The [JSON record](issue-58-verification.json) binds source and test logs. Compact
captures support layout inspection. Native popover view-cache images omit
composited button titles/backgrounds, so they are not final visual proof.
Actual provider calls, physical audio, permission behaviour, full visual and
proficient VoiceOver acceptance remain separate work under
[#62](https://github.com/jpskidmore/telephone-jps/issues/62) and the final release.

This is a verified source change. The owner chose one commit per fix, with a
combined installation/publication after the roadmap. Version/build and installed
baseline remain **3.5.1/build 163**. No cloud workflows were dispatched; user
data, credentials and historical release tags/assets were preserved.

Official documentation checked on 19 and 20 October:
[OpenAI best practices](https://learn.chatgpt.com/docs/learn/best-practices),
[Apple macOS 27 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes),
[NSPopover](https://developer.apple.com/documentation/appkit/nspopover),
[contentViewController](https://developer.apple.com/documentation/appkit/nspopover/contentviewcontroller)
and [MainActor](https://developer.apple.com/documentation/swift/mainactor).
Established AppKit APIs retain the macOS 15.6 baseline; no OpenAI runtime
dependency is introduced.
