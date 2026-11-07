# Current maintenance entry point

Start here for current work on jps Telephone. Release archives and dated test
records describe their original builds; later documentation commits do not
replace those archives or certify a changed app.

## Active work order — 7 November 2026

**Current outstanding issues: exactly one, [#71](https://github.com/jpskidmore/telephone-jps/issues/71). No open PRs were found.** The [ranked roadmap #52](https://github.com/jpskidmore/telephone-jps/issues/52) has been refreshed; its original 19-item baseline is **17 implemented / one closed not planned (#62) / one open (#71)**. The only remaining code issue is **historically P3 and rank 19/19, now the first actionable item because all others are closed**. No currently reported P0/P1 issue is open.

1. **Next — #71, owner-selected Option B.** Retire unused StoreKit purchase, restore, subscription, receipt-refresh and payment-gating infrastructure from the maintained local app and its active build/test graph. [Owner decision of 29 October](https://github.com/jpskidmore/telephone-jps/issues/71#issuecomment-6508472369) replaces the former Option A plan. All local features are included without purchasing/entitlement; retain the existing 30-call engine capacity, full history, lifecycle/recording guards, compact interface and truthful version/build/source/GPL/Credits.
2. **Then — verification gate for #71.** Inventory active references before deletion; freshly run isolated local feature/startup/capacity/history and native information-view cases, appropriate complete native suites, dependency/recording checks and unsigned arm64 Release build. Check absence of active payment observers or purchasing operations. Record actual results and unresolved limits in #71. The 29 October Option A candidate (1,034/1,035 passes) is not a validated implementation B and the obsolete StoreKit purchase-test error must not be described as its blocker.
3. **After passing gates — close #71 and separately decide whether to build/release.** Do not infer signing, installation, real provider/hardware/permission tests or a new release from a source fix. Keep releases/tags/assets immutable and never touch real owner credentials or profiles during synthetic tests.

**Already resolved:** #76 Mute/Hold icon regression and #77 Keychain namespace/save verification were closed. #77 was shipped in **[3.8.2/build 169](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.8.2)** and the owner subsequently reported it worked; the published release passed 1,046 suite tests and seven published downloads were hash-verified. No installation of 3.8.2 was recorded in the release process, and the general owner's confirmation does not constitute per-scenario Keychain/VoiceOver testing. #62's 24-scenario matrix is intentionally incomplete and **closed not planned**, not passed; do not reopen it without a new owner decision.

**Execution boundaries:** one issue at a time on main, local Mac/Xcode checks, synthetic data, `[skip ci]` in code/documentation commits, no manually dispatched cloud workflow, no change to public visibility, licences, release archives or user data. This native macOS repository has no identified Cloudflare deployment dependency; leave Cloudflare resources unchanged. The dated release and other issue history below is retained as original evidence, not a live backlog.

## Current published release — 3.8.2/build 169, 5 November 2026

**3.8.2/build 169** is [public GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.8.2),
from immutable source/tag `361f7fe3d639c11cb4fdf40fc5e72c92e77cfb58`
(tree `00f8214294ff5de22c5ee2c51b46b4b37e20d80e`). It includes #77's
canonical-first namespace migration and the effective-save verification repair.

Fresh local validation passed **1,046 suite tests**, zero failures/skips: Domain
28 XCTest; UseCases 206 XCTest + 157 Swift Testing; ReceiptValidation 5 XCTest;
isolated Telephone 602 XCTest + 48 Swift Testing. Separate component checks,
Release compilation, ad-hoc signatures, metadata and extracted ZIP checks passed.
Independent parity covered 57 regular app files, six symlinks and 1,549 source
blobs. All seven published assets were downloaded and matched local sizes and
SHA-256. Ten prior releases, 65 assets and 16 existing tag refs were preserved.
Read [publication and package proof](releases/3.8.2-verification.json).

No local installation or production-profile/live-Keychain test was performed.
Real labels, ACL enforcement, prompts, multiple-account upgrade/registration and
rollback remain unverified in open #77. #62 stays closed by owner decision.
All release builds were local; no cloud build/release workflow was dispatched.
GitHub's existing automatic CodeQL scan ran despite `[skip ci]` and completed
before cancellation was available; it was not used as release validation.
Later documentation commits do not change this release's tag or archives.

## Acceptance tracking correction — 5 November 2026

The owner [closed #62 as not planned on 4 November](https://github.com/jpskidmore/telephone-jps/issues/62#issuecomment-6631639583)
after stopping practical testing. Its reported observations used installed
3.8/build 167; they do not validate the later #77 migration. The committed
24-scenario matrix remains unverified without completed run records. Historical
references below to pending checks under #62 do not reopen it or authorise more
manual testing. #77 independently retains its Keychain acceptance; read the
[step-by-step checklist](maintenance/2026-11-04-keychain-namespace.md#installed-acceptance-still-required).

The 5 November source review also repairs explicit-save verification when an
earlier Keychain shadows the scoped canonical copy. Fresh local Debug validation
passed 81 focused synthetic credential/account tests; four new regressions first
failed on unchanged production code. This does not repeat the historical full
suite or Release build, or pass installed acceptance. Read the
[repair and evidence](maintenance/2026-11-04-keychain-namespace.md#follow-up-save-verification--5-november-2026).

## Source implementation — issue #77 Option B, 4 November 2026

The owner-selected clean Keychain namespace is implemented and source-verified.
Lookups use `uk.jpsit.telephone.sip:<exact registrar>` first; only absence permits
fallback. Authorised legacy reads can copy into that namespace
with a friendly label, the source ACL and the same file Keychain, followed by
readback verification. Legacy items remain for rollback; explicit saves keep
both copies current and report partial failures. Fresh isolated Telephone
validation passed **646 tests** and unsigned Release compilation passed. Read
[the implementation, evidence and acceptance limits](maintenance/2026-11-04-keychain-namespace.md).
No actual owner Keychain item was modified and no new release or installation
was performed. #77 remains open for installed acceptance; 3.8.1 below remains
GitHub Latest and does not contain this migration.

## Previous published release — 3.8.1/build 168, 4 November 2026

**3.8.1/build 168** is [GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.8.1), from immutable source/tag `ae19260441156318211a984f61dd33de9f1679c8` (tree `fae2145f9f6dc544fa37306d3bcda6191d1cb7ea`). It includes the issue #76 icon repair on the 3.8 baseline.

Fresh local release validation passed **1,015 tests**, zero failures or skips: Domain 28 XCTest; UseCases 206 XCTest + 157 Swift Testing; ReceiptValidation 5 XCTest; isolated Telephone 571 XCTest + 48 Swift Testing. Separate dependency, audio, recording and Foundation checks passed. Release compilation, ad-hoc signing, arm64/entitlements and ZIP extraction passed. All 57 regular app payloads, six symlinks and 1,544 source Git blobs match their packaged counterparts. All seven published downloads match local sizes/SHA-256. Nine previous releases, 58 assets and all 14 previous tag references were preserved. See [publication proof](releases/3.8.1-verification.json).

No local installation or production-profile launch was performed. Apple silicon, macOS 15.6+, ad-hoc signed and unnotarised. Issue #76 remains open for installed Light/Dark call-control acceptance; #62 retains actual provider/audio/hardware/grant/VoiceOver checks. No cloud workflow was dispatched.

## Source repair — call-control icons, 4 November 2026

Issue #76 now has a verified source repair: Mute/Unmute and Hold/Resume restore
icon-only layout after AppKit title updates. Fresh isolated Telephone validation
passed 571 XCTest + 48 Swift Testing (619 tests), unsigned Release compilation
passed, and six native Light/Dark renders were inspected. Read [the evidence and
remaining acceptance](maintenance/2026-11-04-call-control-icons.md). The repair is now
in published 3.8.1 above; #76 remains open for installed acceptance under #62.

## Previous published release — 3.8, 4 November 2026

**3.8/build 167** was published as [GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.8), from immutable source/tag `6d78e04d4d086b3b42bd25499b667645b82846d1` (tree `e8ddbf6d738cec581ff0691638227e3d91989289`). It includes all pushed source changes through `04c75fe`, plus release metadata: #73 Keychain reads, #74 compact call windows and #70 Contacts snapshots.

Fresh local validation passed **1,014 suite cases, zero failures**: Domain 28 XCTest; UseCases 206 XCTest + 157 Swift Testing; ReceiptValidation 5 XCTest; isolated Telephone 570 XCTest + 48 Swift Testing. Separate dependency, audio, recording, Foundation, dial-plan, history-filter and SIP component checks passed. Release compilation, ad-hoc signatures, arm64/entitlements, ZIP extraction and parity checks passed: 57 regular app payloads, six symlinks and 1,534 source Git blobs. All seven published assets were downloaded and matched local sizes/SHA-256. Eight prior releases, their assets and all previous tag references remain unchanged; public visibility was preserved. See [publication proof](releases/3.8-verification.json).

No local installation or production profile launch was performed. This ad-hoc signed, unnotarised release supports Apple silicon and macOS 15.6+. Actual provider, hardware, OS grants, playback and proficient VoiceOver acceptance remain pending in #62. No cloud workflow was dispatched. Historical release and source-only delivery statements below retain their original dates.

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

Issues #61 and #63–69 are now included in the published 3.7 release. The dated source-validation counts below retain their original scope; fresh release validation is recorded above. #62 remains pending by owner choice. **Owner priority update — 28 October:** the owner-prioritised #73 credential source repair is implemented and verified. It is not part of the immutable 3.7 release. **Owner priority update — later 28 October:** #74 now also has verified source changes matching the standard compact dialler footprint. **#70 is now also source-verified** after shared Contacts completion, native keyboard/access/race checks and 1,014 passing suite cases. **Next: #71.** The original roadmap is 17/19 complete; #62 actual acceptance and #71 remain. #73 and #74 are additional reported issues.

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
The later #73/#74/#70 source work is verified; the next ranked item is #71.

Call controls #67 now use current state events and diffed snapshots, with a
one-second tolerant duration-only timer. Fresh isolated Telephone validation
passed 377 XCTest + 48 Swift Testing cases; final 18 focused cases and bounded
baseline/candidate counters plus Time Profiler captures passed. Read
[the call-control record](maintenance/2026-10-26-call-controls.md) for event
coverage, lifecycle checks and measurement limits. No battery or live-call gain
is claimed. The later #73/#74/#70 source work is verified; the next ranked item is #71.

Recording recovery #68 now has a selectable native manager and a generation-checked
asynchronous index; menu validation reads cached state. Owned retry/report/discard
and cleanup participate in quit drains, with exclusive output creation and per-job
confirmation before discard. Fresh isolated Telephone validation passed 428 XCTest
+ 48 Swift Testing cases, plus separate 105 recording ownership assertions, 32 native
lifecycle checks, 11 audio wiring and 6 model/wiring checks. Light/Dark captures
were inspected. Read [the recovery manager record](maintenance/2026-10-26-recording-recovery-browser.md).
The later #73/#74/#70 source work is verified; the next ranked item is #71. These changes are now included in 3.7; no local installation was performed.

History recording attachments #69 are implemented, locally source-verified and
published in main at bdb60c2be44c3bad301422e42e21f0623e639fad. New calls/segments have exact optional identities,
a versioned catalogue and journalled export-link repair. Native history/More menus
provide scoped, verified Play/Reveal actions; history deletion preserves audio.
Final validation passed 486 XCTest + 48 Swift Testing in the isolated app and
206 XCTest + 147 Swift Testing in UseCases, plus separate component gates and
cooperating-process catalogue tests. Read [the verification record](maintenance/2026-10-27-history-recordings.md)
for source hashes, corrected fixtures and the conservative parent-directory-sync
grant boundary. Actual grants/player/provider/VoiceOver remains pending in #62.
These changes are included in published 3.7/build 166. No local installation was performed. The later #73/#74/#70 source work is verified; the next ranked item is #71.

## Keychain read repair — issue #73, 28 October 2026

Registration and Accounts now share typed, asynchronous, coalesced credential reads. Authentication presentation no longer rereads Keychain; cancellation/denial does not become an empty password or an automatic retry. Account, UI and lifecycle generations fence stale work. Hidden Accounts construction performs no lookup, unchanged saves perform no reread, and closing the window clears its credential fields. The storage namespace, Keychain permissions and signing policy are unchanged.

Current validation passed **964 suite cases**, including the final isolated app run of 530 XCTest + 48 Swift Testing. Separate recording/SIP/source gates and unsigned Release compilation passed. Read [the source verification and limits](maintenance/2026-10-28-keychain-reads.md) and [hash record](maintenance/2026-10-28-keychain-reads.json). No real credential/profile/grant test or new release/installation is claimed. Distinct items and ad-hoc signing changes can still require legitimate separate OS prompts; #62 practical acceptance remains pending.

## Compact call-window footprint — issue #74, 28 October 2026

Ordinary call windows now share the standard compact dialler content size of **368 × 104 points**, with native window-frame conversion for matching outer dimensions (368 × 136 on the validation Mac). Opening, ringing/connecting, active and ended panes keep that footprint; caller details, duration, REC feedback and 44-point controls fit inside it. Long status text uses one native truncated line with its complete value retained in help and accessibility. Existing window placement is retained subject to visible-screen clamping. Manually widened or history-expanded diallers are outside this standard-footprint scope; transfer sheets retain their own layout.

Fresh local validation passed **968 suite cases**, 50 overlapping focused cases, the separate 105 recording assertions and unsigned Release compilation. Ten native Light/Dark side-by-side captures and geometry records were inspected. Read [the verification and practical limits](maintenance/2026-10-28-call-window-footprint.md) and [hash record](maintenance/2026-10-28-call-window-footprint.json). This is a source repair after 3.7, with no release or installation; actual different physical displays/provider/VoiceOver acceptance remains pending in #62.

## Dialler Contacts snapshot — issue #70, 28 October 2026

Dialler and transfer completion/token callbacks now use an immutable snapshot built by the existing Contacts actor enumeration. Producer-side admission tickets and current access checks reject revoked or stale suggestions/enrichment; formatting, per-token selection and routing stay in the native controller. History name formatting and the existing fetch order are retained. Synthetic comparison passed 88 normalized ordered completion inputs and 21 token cases; 10,000-contact completion p95 was 13.908 ms versus 110.401 ms for the guarded legacy synthetic scan. This measures synthetic CPU work, not actual system-store/index/disk latency or real-world speedup.

Fresh complete validation passed **1,014 suite cases**, 60 overlapping focused cases, separate 105 recording assertions, repair/vendor gates and unsigned Release. Actual popup keyboard selection, selected URI/index, one delivery, transfer regressions, access/publication races and detached CN mapping were exercised. Read [the full source evidence and compatibility limits](maintenance/2026-10-28-dialler-contacts.md) and [hash record](maintenance/2026-10-28-dialler-contacts.json). CN normalized-empty names, modern display-name order and system enumeration differences are explicit boundaries; incoming-call AddressBook lookup remains outside this change. No installation or new release; #62 actual acceptance stays pending.

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
