# Current maintenance entry point

Start here for current work on jps Telephone. Release archives and dated test
records describe their original builds; later documentation commits do not
replace those archives or certify a changed app.

## Current published release — 27 October 2026

- **3.7/build 166** is public [GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.7), release ID 425883772, from immutable source/tag `58956a9906cbe1221640a926446341e6a71fdcb9`.
- Fresh local validation passed **920 suite cases**, zero failures. All seven uploaded/downloaded assets, 57 app file payloads, six symlinks and 1,510 source Git blobs were verified. Read [3.7 delivery proof](releases/3.7-verification.md) and [the JSON record](releases/3.7-verification.json).
- **No local installation was performed.** The 21 October [3.6.1 installation record](releases/3.6.1-verification.md) is historical; no `/Applications/jps Telephone.app` was present on the machine used for this release.
- The owner chose public visibility on 21 October 2026; no visibility setting changed. All seven previous releases, 44 assets and 12 distinct tags remain unchanged.
- Apple silicon and macOS 15.6 or later remain supported. The package is ad-hoc signed and unnotarised. Actual provider/hardware/grant/playback/installed quit-reopen/VoiceOver acceptance remains pending in #62.
- Review current Apple documentation for macOS 27 behaviour. Newer API use must retain SDK/runtime guards and the older-OS fallback.
- The original 50-issue repair gate (#2–51) completed on 8 October 2026. Its [repair map](REPAIR_VERIFICATION.md) remains historical evidence.

The [ranked roadmap #52](https://github.com/jpskidmore/telephone-jps/issues/52)
is the live source for new issue order and completion. Main may contain later
documentation or implementation commits; do not describe them as installed or
released without separate evidence. The documentation corrections in issue #54
do not change or rebuild the installed application.

The [issue #55 route-status record](maintenance/2026-10-19-route-status.md)
documents the verified source improvement and its separate delivery boundary.

The [issue #58 waiting-call record](maintenance/2026-10-20-waiting-calls.md)
documents individual cancellation, compact feedback and fresh local checks.

The [issue #59 route-preview record](maintenance/2026-10-20-route-presentation.md)
documents shared explanations and consistent account snapshots.

The [issue #60 numbering record](maintenance/2026-10-20-numbering-transparency.md)
documents visible coverage/version information and saved-versus-draft behaviour.

## Source work delivered in 3.7 — 27 October 2026

Issues #61 and #63–69 are now included in the published 3.7 release. The dated source-validation counts below retain their original scope; fresh release validation is recorded above. #62 remains pending by owner choice. **Owner priority update — 28 October:** the owner-prioritised #73 credential source repair is implemented and verified. It is not part of the immutable 3.7 release. **Owner priority update — later 28 October:** #74 now also has verified source changes matching the standard compact dialler footprint. **Next: #70**, then #71. The original roadmap remains 16/19 complete; #73 and #74 are additional reported issues.

The owner resumed open-issue repairs. Expanded history search/filter issue #61
now has fresh native validation: 289 XCTest plus 48 Swift Testing cases, and
68 separately counted AppKit component assertions. Startup, duplicate account
menu and native Search clear defects found during acceptance are repaired.
Read [the history filter record](maintenance/2026-10-23-history-filters.md).
These #61 source changes are now included in 3.7. No installation was performed for this release.
Issue #62 has a published [24-scenario practical matrix](MACOS_27_ACCEPTANCE.md)
with all real-world checks explicitly pending, as the owner requested.

Contacts recovery #63 is now implemented and verified with fresh local suites:
203 XCTest + 144 Swift Testing cases in UseCases, and 307 XCTest + 48 Swift
Testing cases in the isolated Telephone host, all passing. Read
[the Contacts record](maintenance/2026-10-26-contacts-recovery.md) for the source
scope, synthetic permission checks and separate actual-OS acceptance boundary.
Legacy dialler autocomplete remains #70.

Audio recovery feedback #64 now shows current pending/slow attempts with a
native indeterminate indicator and a presentation-only watchdog. Fresh isolated
Telephone validation passed 328 XCTest + 48 Swift Testing cases; separate audio
gate, real-worker lifecycle and source-wiring checks passed. Read
[the audio progress record](maintenance/2026-10-26-audio-progress.md) for identity
guards, actual counts and physical-device limits. Recording feedback follows below. Recording feedback #65 is also source-verified: typed start/fallback
outcomes, current-call retry and actual-folder details in the compact REC slot.
Fresh isolated Telephone validation passed 359 XCTest + 48 Swift Testing cases,
plus synthetic encoding/recovery and separate checks. Read
[the recording feedback record](maintenance/2026-10-26-recording-feedback.md).
These source changes are now included in 3.7; no local installation was performed.

Activity-policy investigation #66 retains the current SIP-session activity after
an isolated 16-sample comparison and a fresh token-balance fixture. It permits
idle system sleep; no app energy/battery improvement or real readiness is claimed.
Read [the measurement and retention decision](maintenance/2026-10-26-activity-policy.md).
The owner-prioritised #73 source repair is verified; the next ranked source item is #70.

Call controls #67 now use current state events and diffed snapshots, with a
one-second tolerant duration-only timer. Fresh isolated Telephone validation
passed 377 XCTest + 48 Swift Testing cases; final 18 focused cases and bounded
baseline/candidate counters plus Time Profiler captures passed. Read
[the call-control record](maintenance/2026-10-26-call-controls.md) for event
coverage, lifecycle checks and measurement limits. No battery or live-call gain
is claimed. The owner-prioritised #73 source repair is verified; the next ranked source item is #70.

Recording recovery #68 now has a selectable native manager and a generation-checked
asynchronous index; menu validation reads cached state. Owned retry/report/discard
and cleanup participate in quit drains, with exclusive output creation and per-job
confirmation before discard. Fresh isolated Telephone validation passed 428 XCTest
+ 48 Swift Testing cases, plus separate 105 recording ownership assertions, 32 native
lifecycle checks, 11 audio wiring and 6 model/wiring checks. Light/Dark captures
were inspected. Read [the recovery manager record](maintenance/2026-10-26-recording-recovery-browser.md).
The owner-prioritised #73 source repair is verified; the next ranked source item is #70. These changes are now included in 3.7; no local installation was performed.

History recording attachments #69 are implemented, locally source-verified and
published in main at bdb60c2be44c3bad301422e42e21f0623e639fad. New calls/segments have exact optional identities,
a versioned catalogue and journalled export-link repair. Native history/More menus
provide scoped, verified Play/Reveal actions; history deletion preserves audio.
Final validation passed 486 XCTest + 48 Swift Testing in the isolated app and
206 XCTest + 147 Swift Testing in UseCases, plus separate component gates and
cooperating-process catalogue tests. Read [the verification record](maintenance/2026-10-27-history-recordings.md)
for source hashes, corrected fixtures and the conservative parent-directory-sync
grant boundary. Actual grants/player/provider/VoiceOver remains pending in #62.
These changes are included in published 3.7/build 166. No local installation was performed. The owner-prioritised #73 source repair is verified; the next ranked source item is #70.

## Keychain read repair — issue #73, 28 October 2026

Registration and Accounts now share typed, asynchronous, coalesced credential reads. Authentication presentation no longer rereads Keychain; cancellation/denial does not become an empty password or an automatic retry. Account, UI and lifecycle generations fence stale work. Hidden Accounts construction performs no lookup, unchanged saves perform no reread, and closing the window clears its credential fields. The storage namespace, Keychain permissions and signing policy are unchanged.

Current validation passed **964 suite cases**, including the final isolated app run of 530 XCTest + 48 Swift Testing. Separate recording/SIP/source gates and unsigned Release compilation passed. Read [the source verification and limits](maintenance/2026-10-28-keychain-reads.md) and [hash record](maintenance/2026-10-28-keychain-reads.json). No real credential/profile/grant test or new release/installation is claimed. Distinct items and ad-hoc signing changes can still require legitimate separate OS prompts; #62 practical acceptance remains pending.

## Compact call-window footprint — issue #74, 28 October 2026

Ordinary call windows now share the standard compact dialler content size of **368 × 104 points**, with native window-frame conversion for matching outer dimensions (368 × 136 on the validation Mac). Opening, ringing/connecting, active and ended panes keep that footprint; caller details, duration, REC feedback and 44-point controls fit inside it. Long status text uses one native truncated line with its complete value retained in help and accessibility. Existing window placement is retained subject to visible-screen clamping. Manually widened or history-expanded diallers are outside this standard-footprint scope; transfer sheets retain their own layout.

Fresh local validation passed **968 suite cases**, 50 overlapping focused cases, the separate 105 recording assertions and unsigned Release compilation. Ten native Light/Dark side-by-side captures and geometry records were inspected. Read [the verification and practical limits](maintenance/2026-10-28-call-window-footprint.md) and [hash record](maintenance/2026-10-28-call-window-footprint.json). This is a source repair after 3.7, with no release or installation; actual different physical displays/provider/VoiceOver acceptance remains pending in #62.

On 26 October the owner authorised **all remaining issues, one at a time**, with
findings and outcomes logged in GitHub for other contributors. This resumes the
previously deferred source work and supersedes the historical 25% release stop.
After each issue and during long work, check actual five-hour allowance. At
**10% remaining or below**, checkpoint and schedule continuation five minutes
after the usage tool's reported reset. Recheck usage on resumption. Source fixes
do not imply installation or release; preserve the released baseline above.

## Owner's execution controls

On **21 October 2026**, the owner authorised **Fix A for #72**: remove the
permanent route line and restore the centred 3.5 dialler row, then install and
release **3.6.1/build 165** after verification. Delivery completed on21 October;
read the hotfix proof above. The other eleven roadmap issues
remain deferred. Repository visibility is owner-controlled and must be left alone.

The owner authorised roadmap implementation on **19 October 2026**, strictly
**one issue at a time, in ranked order**. Finish and verify the current item,
record its evidence and update GitHub before starting the next. An independent
review of the same item is allowed; do not work on later items in parallel.

The owner initially chose one verified source commit per fix with release after
the roadmap. On **20 October 2026**, they changed that instruction: at **25%
remaining in the actual five-hour allowance**, stop roadmap work, build and
release the completed verified batch, and leave remaining issues for another
day. This interim delivery contains #53–60 (eight of nineteen); #61–71 remain
open. Version 3.6/build 164 completed installation and private publication on
21 October after the independent delivery checks passed. The remaining roadmap
is deferred until the owner asks; the release-only wakeup is stopped.

Read the actual five-hour usage window before work, between issues and during
long-running work. If its remaining allowance falls **to 10% or below**, stop at a
recoverable point and record the exact in-progress state. Schedule this chat to
resume **five minutes after the reset reported by the usage tool**. Recheck the
allowance on resumption; do not guess the reset from wall-clock time or substitute
the weekly window. If live usage data is unavailable, report that limitation.

Work locally on main under [AGENTS.md](../AGENTS.md), with `[skip ci]` in pushed
commits and no cloud workflow dispatch. Preserve the compact UK-English design,
credentials, user data and all immutable release tags/assets. Read the current
working tree before editing and preserve unrelated changes.

## Feature and verification guides

- [Recording use](../RECORDING.md),
  [recording/history recovery](RECORDING_RECOVERY.md) and
  [audio recovery](AUDIO_RECOVERY.md) describe current controls and known limits.
- [Guided routes](DIAL_PLANS.md) and
  [offline numbering coverage](DIAL_PLAN_NUMBERING.md) explain routing boundaries.
- [Validation](VALIDATION.md) describes local, isolated checks and the release
  sequence. Use synthetic data; never load the owner's real accounts, Contacts,
  call history or recordings into regression fixtures.
- [Compact interface](LIQUID_GLASS.md) records the accepted window sizes,
  appearance and accessibility behaviour.
- [Maintenance handover](BUG_FIX_HANDOVER.md) retains the detailed repair and
  publication history. [Old unreleased notes](releases/unreleased.md) are
  explicitly historical, not an active release gate.

Keep source review, automated checks, packaged/installed evidence and actual
provider/audio/device/permission/VoiceOver acceptance separate. A previous test
pass or issue closure does not verify changed code. Do not place emergency calls
as tests. Dated historical results remain dated; this documentation update claims
no new runtime or live-call validation.

## Official references

- [OpenAI Codex best practices](https://learn.chatgpt.com/guides/best-practices)
  — scoped implementation and explicit completion checks; no OpenAI API runtime
  dependency is implied for this SIP application.
- [Apple macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
  — current SDK/OS compatibility reference. Established APIs are not automatically
  macOS 27 additions.

Recheck the applicable official documentation for each implementation issue.

## Owner release request — 27 October 2026

The owner explicitly authorised releasing the latest verified build on GitHub now,
overriding the usage pause for this release. 3.7/build 166 was packaged locally, published and verified; all earlier releases and uploaded assets were preserved.
Do not install locally without a separate request. The remaining practical #62
checks stay pending; no real profile/provider/grant testing is authorised.
