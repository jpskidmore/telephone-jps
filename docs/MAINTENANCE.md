# Current maintenance entry point

Start here for current work on jps Telephone. Release archives and dated test
records describe their original builds; later documentation commits do not
replace those archives or certify a changed app.

## Released and installed baseline

Checked on **21 October 2026**:

- GitHub Latest and the installed application are **3.6/build 164**.
- The immutable application release source is
  `7abcede59ff282f9c0dd042e66cb8283ffb66085`. Read the
  [3.6 publication proof](releases/3.6-verification.md) and
  [release test record](releases/3.6-tests.json) for the fresh 694-case validation
  and verified packaging/installation/publication. Previous 3.5.1 and earlier
  release tags/assets remain unchanged.
- The owner chose **public visibility on 21 October 2026** and explicitly said
  to leave repository visibility alone. Do not change that setting. The
  [19 October visibility record](maintenance/2026-10-19-visibility.md) retains
  the earlier private-policy snapshot; it is superseded as current policy.
- The original 50-issue repair gate (#2–51) completed on **8 October 2026**.
  The [repair map](REPAIR_VERIFICATION.md) is completed historical evidence,
  not a list of 50 outstanding tasks.
- The supported baseline remains **Apple silicon and macOS 15.6 or later**.
  macOS 27 behaviour must be checked against current Apple documentation;
  newer API use must retain SDK/runtime guards and the older-OS fallback.

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

## Owner's execution controls

On **21 October 2026**, the owner authorised **Fix A for #72**: remove the
permanent route line and restore the centred 3.5 dialler row, then install and
release **3.6.1/build 165** after verification. The other eleven roadmap issues
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
long-running work. If its remaining allowance falls **below 10%**, stop at a
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
