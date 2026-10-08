# Maintenance handover — 3.5 Guided routes

The owner authorised **3.5/build 162 Guided routes** on 8 October: one dialler, configurable country/area expansion, account routing and consolidated history. Implementation and local validation are in progress on main. Read [DIAL_PLANS.md](DIAL_PLANS.md) and [3.5 notes](releases/3.5.md) before continuing. The previous 3.0 publication proof below is historical and remains immutable; no completed 3.5 publication is claimed yet.

The owner's 7 October privacy/repair gate is complete. All 50 baseline findings
#2–51 are recorded **fixed_verified**, documented and closed on GitHub; current
verification found **zero open issues** and the repository is **private**. The
owner's **3.0/build 161** is built, ad-hoc signed, packaged and installed locally
at `/Applications/jps Telephone.app`, and published as
[GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.0).
The [publication/package record](releases/3.0-verification.md) and
[JSON proof](releases/3.0-verification.json) bind the exact release revision,
installed payloads and seven uploaded assets. This closes the finite baseline;
it does not establish that every possible future bug is eliminated.

## Current state and preserved baseline

- Source repair commit: [`01ae573`](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b),
  published on main. Documentation issue #39 was fixed earlier at
  `a7cd66478dd7079bfd9ca89d13ce8cbe7dcd73cd`. The progress record marks the repair
  gate passed on 8 October 2026 at 00:17 UTC. The release/source revision is
  `6363412d56e2bc142a54058321b7873a69068c62`, tree
  `1c87680f6751a0c4a513c8705ea2e3f8fb2232b6`.
- All four local suites passed **617 automated cases, zero failures**:
  Domain 28 XCTest; UseCases 195 XCTest plus 124 Swift Testing; Receipt 5 XCTest;
  isolated TelephoneTests 217 XCTest plus 48 Swift Testing. Component assertions
  and inert native probes are separate; see [VALIDATION.md](VALIDATION.md) and the
  [50-issue verification map](REPAIR_VERIFICATION.md).
- Retained audit baseline: **v2.1.8/build 160**, commit
  `9a32ae825e4d3bb380cb52b8452ddf7526764a25`, tree
  `ee6fbedc72ca9ed380f112b3f95dd3ebd8c38975`. Its original app/source ZIPs,
  checksums and verification files remain
  [unchanged](https://github.com/jpskidmore/telephone-jps/releases/tag/v2.1.8).
  Do not move that tag or replace its assets with 3.0 content.
- Published Latest: [v3.0](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.0),
  release ID `406277128`, published 8 October 2026 at 00:33 UTC. All seven asset
  sizes/SHA-256 digests match the verified local files. The installed app matches
  all 59 extracted app payloads; the source ZIP matches all 1,400 release-commit
  file payloads. Preserve this tag and its assets unchanged too. Its immutable
  source ZIP/tag retain the preparation-time documentation snapshot; current main
  documentation records completed publication without rewriting that snapshot.
- Preserve the accepted compact UK-English design: Icon rail/Titled sections
  Settings at one Accounts-sized window, Dial bar with one recent call, Pocket
  call cards, native close controls, Light/Dark, green Online and red Offline.
  The fixes retain calling, recording, account and saved-data functions.

## Start a future session here

1. Read [AGENTS.md](../AGENTS.md), this handover, [repair evidence](REPAIR_VERIFICATION.md),
   [validation](VALIDATION.md) and [tracked progress](audit-2.1.8/repair-progress.json).
   The [immutable issue snapshot](audit-2.1.8/issues.json) and
   [original audit context](audit-2.1.8/README.md) preserve the baseline, not 50
   outstanding repairs to repeat.
2. Confirm private GitHub visibility, current main/working-tree state, live issue
   states, installed app and published/downloadable release against the recorded
   3.0 proof. Preserve unrelated user changes. The publication/install steps are
   complete; verify current state before later work rather than rebuilding or
   replacing immutable release assets to repeat those steps.
3. Work on main locally, with `[skip ci]` pushed commits and no workflow dispatch.
   Delegate independent GUI/SIP/backend work when useful. Review async ownership
   across groups, especially main admission, worker generation guards and final
   recording/history drains.
4. For a new defect, record its concrete trigger, root cause, affected production
   boundary, regression and remaining limits. Update issue evidence after a
   verified fix. Do not treat closure, compilation alone or historical tests as
   proof that new code is correct; do not rewrite the original issue snapshot.
5. For a later authorised release, rerun affected and required complete checks,
   build/sign/package locally, install and inspect the exact packaged app, upload
   those same bytes plus source/docs/checksums, then verify publication and
   uploaded asset hashes/sizes. Preserve v2.1.8 and v3.0 unchanged. Their historical
   passes do not certify changed code.

## Local tests and user-data safeguards

`TelephoneTests` is application-hosted. Normal startup may load the user's real
preferences/accounts. Build-for-testing first, then give the **built Debug host**
a unique disposable CFBundleIdentifier **and remove NSMainNibFile**. Update host
identity/path in generated `.xctestrun` metadata, re-sign only that modified test
host ad hoc, then test-without-building so rebuild does not undo isolation. A
unique ID alone still starts AppController; removing only the nib retains the
real defaults identity. Preserve production app metadata and the user's data.

Run hosted tests serially from a local `/private/tmp` host/framework copy if
FileProvider under Documents stalls dyld/signing. The final 617-case validation
used isolated local hosts. Preserve `.xcresult`, logs and compiler/platform info.
Set `JPS_DEBUG_DERIVED_DATA` and `JPS_DEBUG_BUILD_LOG` to current local products and
their captured successful build link log when reproducing native probes; detailed
commands are in [VALIDATION.md](VALIDATION.md). A launch timeout before test entry
is not a case pass. Do not repurpose HOME or CODEX_HOME or use real credentials,
Contacts, calls/history or recordings to make a regression pass.

Native SIP fixtures redirect endpoint/transport/media effects and use synthetic
identity. UID/resource fixtures use inert CoreAudio/CoreFoundation boundaries.
Recording tests perform real encoding using synthetic audio and scratch paths.
These establish their controlled regressions; they do not establish live SIP
provider routing, actual audio/hotplug, sandbox grants, a real recording capture,
visual acceptance or proficient VoiceOver. Record manual scenarios separately on
the exact installed app. New SDK/audio operations must remain on the serial
control worker and validate ownership/generation before applying completions.

Existing GitHub workflows are historical automation. `[skip ci]` suppresses push
runs but not workflow_dispatch. Do not dispatch or publish through cloud runners;
all builds/tests for this project remain local. The ad-hoc local package is
unnotarised; preserve its documented signing policy and verify nested signatures.

## Complete verified baseline

The table reports controlled repair verification, not a proof of zero future
bugs or all provider/hardware behaviour. Per-item causes/checks/limits and full
fix hashes remain in [repair-progress.json](audit-2.1.8/repair-progress.json).

| Issue | Audit ID | Priority | Repair | Verified fix |
|---|---|---|---|---|
| [#2](https://github.com/jpskidmore/telephone-jps/issues/2) | CLEANUP-01 | P3 | Remove unused window-resizing and string-escaping Objective-C categories | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#3](https://github.com/jpskidmore/telephone-jps/issues/3) | BACKEND-01 | P2 | Preserve existing call history when loading its file fails | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#4](https://github.com/jpskidmore/telephone-jps/issues/4) | BACKEND-02 | P2 | Do not report Clear History as complete when deleting its file fails | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#5](https://github.com/jpskidmore/telephone-jps/issues/5) | GUI-01 | P2 | Active-call dead-key input raises an out-of-bounds exception | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#6](https://github.com/jpskidmore/telephone-jps/issues/6) | GUI-02 | P3 | Elapsed call duration stops updating during hold | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#7](https://github.com/jpskidmore/telephone-jps/issues/7) | GUI-03 | P2 | Settings and account-entry fields omit their accessible purpose labels | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#8](https://github.com/jpskidmore/telephone-jps/issues/8) | GUI-04 | P2 | Clear outbound-proxy icon is exposed as Stop Progress | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#9](https://github.com/jpskidmore/telephone-jps/issues/9) | GUI-05 | P3 | DTMF echo replaces the row still labelled Caller, including after the call ends | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#10](https://github.com/jpskidmore/telephone-jps/issues/10) | SIP-01 | P2 | Use UTF-8 byte length when parsing SIP display names | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#11](https://github.com/jpskidmore/telephone-jps/issues/11) | SIP-02 | P2 | Preserve non-default SIP ports through redial and history conversions | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#12](https://github.com/jpskidmore/telephone-jps/issues/12) | SIP-03 | P2 | Preserve IPv6 brackets when parsing a SIP address with a port | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#13](https://github.com/jpskidmore/telephone-jps/issues/13) | BACKEND-03 | P2 | Use unique audio-device identities instead of collapsing identical device names | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#14](https://github.com/jpskidmore/telephone-jps/issues/14) | BACKEND-04 | P2 | Surface recording export failure and retain a durable recovery job | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#15](https://github.com/jpskidmore/telephone-jps/issues/15) | BACKEND-05 | P2 | Drain pending call-history writes before confirming app termination | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#16](https://github.com/jpskidmore/telephone-jps/issues/16) | BACKEND-06 | P2 | Handle failed Keychain credential saves before reporting account changes as saved | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#17](https://github.com/jpskidmore/telephone-jps/issues/17) | BACKEND-07 | P2 | Keep potentially blocking audio opens and SDK-lock waits off the UI thread | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#18](https://github.com/jpskidmore/telephone-jps/issues/18) | GUI-07 | P2 | Keep first-launch setup unchanged after rejecting whitespace-only account fields | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#19](https://github.com/jpskidmore/telephone-jps/issues/19) | GUI-08 | P2 | Validate the authentication username before dismissing the retry sheet | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#20](https://github.com/jpskidmore/telephone-jps/issues/20) | GUI-06 | P3 | Keep compact call-card growth inside the screen’s visible work area | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#21](https://github.com/jpskidmore/telephone-jps/issues/21) | SIP-04 | P2 | Preserve successful transfer results after the source call is removed | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#22](https://github.com/jpskidmore/telephone-jps/issues/22) | SIP-05 | P2 | Attach replacement calls to a call controller | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#23](https://github.com/jpskidmore/telephone-jps/issues/23) | SIP-06 | P2 | Guard late incoming-call delivery after an account is removed | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#24](https://github.com/jpskidmore/telephone-jps/issues/24) | BACKEND-08 | P3 | Reject stale history reloads after Clear History or newer updates | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#25](https://github.com/jpskidmore/telephone-jps/issues/25) | BACKEND-09 | P3 | End background activity when SIP startup fails | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#26](https://github.com/jpskidmore/telephone-jps/issues/26) | BACKEND-10 | P2 | Enable explicit audio recovery when hotplug remapping fails after null sound | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#27](https://github.com/jpskidmore/telephone-jps/issues/27) | SIP-07 | P2 | Cancel pending account registration when Offline is selected during startup | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#28](https://github.com/jpskidmore/telephone-jps/issues/28) | GUI-09 | P2 | Preserve the selected call when a full history shifts to include a new record | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#29](https://github.com/jpskidmore/telephone-jps/issues/29) | BACKEND-11 | P3 | Apply a changed ringtone output while an incoming call is ringing | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#30](https://github.com/jpskidmore/telephone-jps/issues/30) | GUI-10 | P2 | Keep the selected contact destination attached to its own token | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#31](https://github.com/jpskidmore/telephone-jps/issues/31) | GUI-11 | P2 | Preserve a manually held call when closing transfer setup | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#32](https://github.com/jpskidmore/telephone-jps/issues/32) | SIP-08 | P2 | Preserve manual Unavailable across automatic wake and session registration | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#33](https://github.com/jpskidmore/telephone-jps/issues/33) | BACKEND-12 | P2 | Invalidate pending history additions when deleting an account | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#34](https://github.com/jpskidmore/telephone-jps/issues/34) | BACKEND-13 | P2 | Recognise documented CoreAudio errors from implicit SDK sound opens | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#35](https://github.com/jpskidmore/telephone-jps/issues/35) | BACKEND-14 | P2 | Release failed reachability initialisers exactly once | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#36](https://github.com/jpskidmore/telephone-jps/issues/36) | BACKEND-15 | P2 | Recover empty Sound settings after a transient device query failure | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#37](https://github.com/jpskidmore/telephone-jps/issues/37) | CLEANUP-02 | P3 | Prune expired history subscribers from shared event lists | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#38](https://github.com/jpskidmore/telephone-jps/issues/38) | BACKEND-16 | P2 | Handle nullable DNS watcher creation before using Core Foundation handles | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#39](https://github.com/jpskidmore/telephone-jps/issues/39) | DOC-01 | P3 | Update the README local-test download entry for the published release | Verified ([a7cd664](https://github.com/jpskidmore/telephone-jps/commit/a7cd66478dd7079bfd9ca89d13ce8cbe7dcd73cd)) |
| [#40](https://github.com/jpskidmore/telephone-jps/issues/40) | SIP-09 | P2 | Keep calls controllable when a local hang-up request is rejected | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#41](https://github.com/jpskidmore/telephone-jps/issues/41) | SIP-10 | P2 | Restore Transfer after the preliminary local hold request is rejected | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#42](https://github.com/jpskidmore/telephone-jps/issues/42) | GUI-12 | P2 | Validate existing account edits before re-enabling and overwriting saved values | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#43](https://github.com/jpskidmore/telephone-jps/issues/43) | SIP-11 | P2 | Cancel pending outgoing calls when their account is removed | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#44](https://github.com/jpskidmore/telephone-jps/issues/44) | SIP-12 | P2 | Preserve active-call callback ownership when an account goes Offline | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#45](https://github.com/jpskidmore/telephone-jps/issues/45) | BACKEND-17 | P2 | Apply saved Network configuration changes made during user-agent startup | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#46](https://github.com/jpskidmore/telephone-jps/issues/46) | SIP-13 | P2 | Reset ringback bookkeeping when the SIP user agent restarts | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#47](https://github.com/jpskidmore/telephone-jps/issues/47) | GUI-13 | P2 | Rebind the cached transfer observer when its source card redials | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#48](https://github.com/jpskidmore/telephone-jps/issues/48) | BACKEND-18 | P2 | Complete first-run launch state after the first account is added | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#49](https://github.com/jpskidmore/telephone-jps/issues/49) | GUI-14 | P3 | Connect the ended-transfer Call Back button to its redial delay | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#50](https://github.com/jpskidmore/telephone-jps/issues/50) | BACKEND-19 | P2 | Defer Sound codec changes until the media endpoint is ready | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |
| [#51](https://github.com/jpskidmore/telephone-jps/issues/51) | BACKEND-20 | P3 | Release the wrapper's PJLIB reference after failed startup | Verified ([01ae573](https://github.com/jpskidmore/telephone-jps/commit/01ae5734bfd933c9048f00ef4c3ebe035fabeb0b)) |

## Ready-to-use future-session request

> Read AGENTS.md, docs/BUG_FIX_HANDOVER.md, docs/REPAIR_VERIFICATION.md and the
> tracked progress in the private jpskidmore/telephone-jps repository. The 50
> baseline findings #2–51 are already fixed and verified. Confirm current main,
> issue and installed/published 3.0 state before continuing maintenance. Preserve
> the accepted compact UK-English interface and saved data. Work on main locally,
> use isolated tests and [skip ci], and do not dispatch cloud workflows. Record
> each new change's actual regressions and practical limits; preserve v2.1.8.
