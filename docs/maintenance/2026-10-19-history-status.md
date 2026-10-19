# Call history status — issue #56

The existing history row now exposes Missed, Incoming or Outgoing independently
of contact colour. The presentation model derives status from the stored flags,
giving the explicit missed flag precedence. Status participates in equality and
hashing, so a status-only change refreshes a row with the same stable identity.

A non-drawing native static-text child occupies the existing direction arrow's
12 × 12-point position. It exposes the short purpose “Call status” and the
current value. The arrow is decorative; the account badge remains a separate
native element. Contact, date and duration keep their existing semantics.
No persistence, routing, history actions, symbols or visible geometry changed.

## Verification — 19 October 2026

The final isolated **TelephoneTests** run passed **307 cases, zero failures**:
259 XCTest and 48 Swift Testing. Five new XCTest cases cover flag mapping,
status-only equality, the actual native accessibility tree, reuse/reset, and
selected-call identity across status changes, prepend and collapse/expansion.
The native checks run in Light and Dark, require exactly one status and one
account per visible row, retain contact/date/duration, and reject a second image
announcement. Existing compact geometry, badge drawing and action tests passed.

The [JSON record](issue-56-verification.json) binds changed-source and final
build/test log hashes to these results. The fresh host had a unique disposable
Debug identity and no main nib; all history records were synthetic. Domain,
UseCases and ReceiptValidation were unchanged and were not rerun: their #55
results remain dated historical evidence, not fresh #56 passes.

Earlier native fixtures mixed test-module records with app-module cells, skipped
legacy AppKit accessibility wrappers, and encountered an incompatible Swift
typed selected-row array. Corrected fixtures use the actual Telephone app types
and modern/legacy public accessibility attributes. Reuse follows Objective-C
KVO; the adversarial foreign-value reset alone detaches the arrow binding.
Earlier failed and restarted runs are diagnostic evidence only. No broader
accessibility-child override or native-control rewrite was needed.

## Delivery and practical limits

This is source-only completion under the owner's instruction to commit each fix
and release after the roadmap. Version metadata, the installed 3.5.1/build 163
application, release tags and assets remain unchanged. No installation or
publication is claimed.

Automated native metadata/tree, colour and layout checks do not establish
proficient VoiceOver speech, actual keyboard/pointer use, live provider/audio or
permission acceptance. Keep those practical checks separate, including the
[macOS 27 acceptance matrix](https://github.com/jpskidmore/telephone-jps/issues/62).

- [Issue #56](https://github.com/jpskidmore/telephone-jps/issues/56) and
  [ranked roadmap](https://github.com/jpskidmore/telephone-jps/issues/52).
- [OpenAI Codex best practices](https://learn.chatgpt.com/docs/learn/best-practices)
  — scoped implementation and explicit completion checks; no AI API addition.
- [Apple macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
  — compatibility review; established APIs retain older-OS support.
- [Apple accessibility children](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilitychildren())
  and [accessibility value](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/setaccessibilityvalue(_:))
  — actual native child reachability and semantic values.
