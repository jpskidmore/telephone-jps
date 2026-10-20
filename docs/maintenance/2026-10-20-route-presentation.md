# Consistent route previews — issue #59

The compact dialler and Dial plan Test page now use one immutable presentation
value derived from their resolved route and the same account snapshot. Provider
names, matching-rule descriptions and explanations share a policy while the
compact status and full editor layout keep their existing purposes.

Both surfaces include nonfatal destination guidance. For example, `123R45P67`
retains its selected connection and explicitly explains that pause/recall syntax
is literal provider syntax rather than post-connect DTMF. Duplicate route/error
messages appear once. Full explanations remain available in tooltips and native
accessibility values; clearing input or entering an invalid draft removes stale
guidance. Duplicate account UUIDs display ambiguity instead of an arbitrary name.

Each coherent editor refresh reads the account provider once. Selectors, preview
and deferred exception rows reuse that snapshot. Equal account fields skip
unnecessary menu/table rebuilding during number edits. Later state changes and
the post-admission account-refresh notification replace the rendered snapshot.
Unsaved plans, open exception fields and selected target UUIDs survive those
updates. A committed save suppresses its own synchronous refresh before applying
one final render. No persistent route cache or new state framework was added.

The compact Objective-C resolver receives the exact account snapshot later used
by presentation. A detached preview callback exits safely after its window
controller is released. Normalisation, route resolution, default/exception
precedence, immutable request selection, native-worker ownership and no-fallback
admission remain unchanged.

## Fresh local verification — 20 October 2026

- **325 app cases passed, zero failures:** 277 XCTest plus 48 Swift Testing.
  Eight new native cases verify snapshot consistency, fresh names/states,
  preserved drafts/sheets, save notifications, complete/stale explanatory text
  and callback lifetime. The focused editor/dialler run passed **30 cases**.
- The production Foundation routing/presentation harness passed **213 checks**,
  including 43 new presentation assertions. Ready, waiting, disabled, failed,
  Offline, missing/ambiguous identity, blocked, emergency, SIP and literal service
  cases retain routing outcomes and no fallback. These checks are counted
  separately from native app cases.
- The normaliser/resolver sections and call-admission coordinator are unchanged
  from the source parent. Independent review found no remaining blockers;
  whitespace checks and the historical 50-issue repair gate passed.

The [JSON record](issue-59-verification.json) binds source sections, logs and
counts. Tests used a fresh unique nib-free Debug host, actual Telephone app-module
editor types, synthetic accounts and isolated defaults. The off-main notification
hop and defaults-backed fallback observer have static review only. Real provider,
physical device/audio, permission, full visual and proficient VoiceOver
acceptance remain separate under [#62](https://github.com/jpskidmore/telephone-jps/issues/62)
and the final combined release. Framework results remain historical.

This change verifies shared wording and bounded provider reads. It claims no
measured latency, CPU, memory or energy improvement. The accepted compact sizes
and fixed editor geometry remain intact. Installation/publication and version
bumping remain deferred until the roadmap is complete; installed baseline stays
**3.5.1/build 163**. No cloud workflows, user-data migration or release asset/tag
changes occurred.

Official references checked on 20 October:
[OpenAI best practices](https://learn.chatgpt.com/docs/learn/best-practices),
[Apple macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
and [MainActor](https://developer.apple.com/documentation/swift/mainactor).
These support scoped verification and UI snapshot ownership; no OpenAI runtime
dependency or new macOS-only API requirement is introduced.
