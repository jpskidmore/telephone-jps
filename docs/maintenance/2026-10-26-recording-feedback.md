# Recording start and destination feedback — 26 October 2026

Issue [#65](https://github.com/jpskidmore/telephone-jps/issues/65), baseline `e493bbbc8af754bd2e9de5fe2bd1098941951b10` plus this change. Verified source work only; no installed update.

Typed native results distinguish busy, stale call, invalid destination, unavailable audio, private storage, recorder creation and connection failure. Typed destination reasons retain the original fallback cause even if reservation later fails. The existing 52-point recording slot now shows Starting, Failed or confirmed REC; REC* identifies fallback. Its native details show the actual folder, reason and explicit Retry / Choose Folder / Reveal actions. Failed attempts never claim a recording exists or earlier uncaptured audio can be recovered. Retry reads current settings and cannot create duplicate pending sessions. Existing capture remains visible if preferences change.

Current-call and per-attempt ownership reject stale callbacks. Stop invalidates queued recording admission and schedules serial cleanup behind any already-running setup; late UI completion cannot stop a newer session. Private raw-job ownership and export recovery remain intact. Granted folder access is consumed once and retained through conversion; only unused empty regular-file reservations are removed, with active/pending destinations protected. Invalid saved bookmarks fall back without requesting a custom grant on the default folder. Stale bookmark refresh remains available. No raw error text or recording paths are added to diagnostics.

## Fresh verification

Local Xcode 27.1 / Swift 6.4, arm64, macOS 27.0.1; deployment macOS 15.6.

- Complete isolated Telephone suite: **359 XCTest + 48 Swift Testing cases**, zero failures, including **16 new backend outcome tests and 15 new controller/UI tests**.
- Actual synthetic WAV/MP3/Ogg export and durable recovery harness passed, including **102 ownership assertions**. Separate lifecycle model/source checks: six passed; audio integration wiring: 11 passed. These are separate from 407 hosted suite cases.
- New tests cover denied/invalid/missing folders, reservation errors, exact fallback/Reveal, recorder/connection failures, busy admission, scope transfer, stop before/after held work, old dialog/call/generation callbacks, fresh retry settings, no false REC and stale folder panels.
- Native card and live details are asserted in Light/Dark: 300-point card, 52×14 recording slot, fitting labels, wrapped long folders, action routing and current accessibility descriptions. Twelve captures exported; four representative Light/Dark card/detail captures inspected without clipping or overlap.
- The first full run found the Starting… label was 54.12 points wide in a 52-point slot. Shortening the visible label to Starting preserves the full accessible explanation. The final complete build/run passes.
- Unchanged framework suites were not rerun. No actual recording capture, hardware/provider call, sandbox grant, proficient VoiceOver, cloud workflow, package, installation or release is claimed. Actual practical checks remain pending in #62 by owner choice.

Final evidence: `/private/tmp/jps-recording65-final-build-20261026.log`, `/private/tmp/jps-recording65-final-tests-20261026.log`, `/private/tmp/jps-recording65-final-20261026.xcresult`, `/private/tmp/jps-recording65-components-20261026.log`, and `/private/tmp/jps-recording65-final-images/`. Source/log/capture hashes are in the adjacent JSON record. Reproduce using docs/VALIDATION.md and the unique-identity nib-free host script; keep test-manager runs serial and synthetic. Next ranked source item: #66.

Apple references checked: [contextual feedback and alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), and [security-scoped resource access](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()). Established APIs retain the older supported OS path.
