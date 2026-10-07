# 2.1.8 audit snapshot

This portable repository snapshot preserves the complete **50 findings, #2–51**,
captured on 7 October 2026 against 2.1.8/build 160 at
`9a32ae825e4d3bb380cb52b8452ddf7526764a25`.

Read [the handover](../BUG_FIX_HANDOVER.md) before repair. The
[issue snapshot](issues.json) contains every original issue body, title, ID,
priority, source link and bounded evidence statement. Keep it as historical
evidence; record implementation progress in [repair-progress.json](repair-progress.json)
and each live authenticated GitHub issue. A snapshot field such as
`verified: true` means the historical finding/publication was validated; it never
means the bug was fixed. Only recorded `fixed_verified` repair progress backed
by actual fix and regression evidence can pass the repair gate.

## Evidence and closure

- Priority totals: **39 P2 / 11 P3**.
- Strongest evidence boundaries: **44 isolated production-component findings**,
  **one shown native-window geometry finding**, **two source-only/known-limitation
  findings**, **two cleanup findings**, **one documentation finding**.
  Component counters/recorders are not end-to-end native/provider/UI outcomes.
- Complete GUI review: eight passes (five earlier plus three follow-ups), final
  quiet supplemental passes 2/3 after GUI-14; 37 source/header files and 22 resources.
- Backend storage/device/recovery review: five passes, final quiet 4/5.
- Supplementary maintenance/reference/release-parity review: five passes, final
  quiet 4/5 after DOC-01.
- SIP/account/startup review: 12 passes, final fresh quiet 11/12 after BACKEND-20;
  45 implementations / 8,955 lines, plus final supporting headers/resources.
- A new supported finding reset its scope's quiet count. Both final complete
  passes found no additional distinct supported or unresolved candidate. Existing
  findings are still open; there is no global zero-bug claim.

The audit did not make fixes, rebuild the application or rerun the full test
suite. Existing release documentation distinguishes earlier 540-test baseline
verification from the 16 focused 2.1.8 tests and separate Settings fixtures.
Recorded probe results retain their original boundaries in each issue body.

Native SIP/provider/media behavior, real audio/device failure and hotplug,
full VoiceOver/keyboard/IME/multiple-display acceptance, credentials/Contacts and
user-profile startup were not comprehensively exercised by this review.
The window geometry check measured work-area overflow, not actual Dock occlusion.
Native crash/resource/audible consequences labelled source-supported were not
reproduced by inert fixtures.

Original local scratch probes/objects/results live outside the checkout in the
owner's prior workspace. They are optional supporting material, not a dependency
of this handover. Future sessions should use the preserved source-linked triggers
and regression expectations to create current tests and record their actual
results. Do not treat absent scratch files or a closed issue as verified repair.

The retained 2.1.8 source/archive and five uploaded assets remain historical.
The new main documentation does not change their source revision, version or
binary bytes. Repository privacy and the repair-before-build instruction are
recorded in the handover and root AGENTS.md.
