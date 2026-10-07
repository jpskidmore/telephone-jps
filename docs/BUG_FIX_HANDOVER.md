# Repair handover — 50 findings before the next build

Owner instruction, **7 October 2026**: make `jpskidmore/telephone-jps` private
and fix the 50 audited findings before another application build. This document
and [AGENTS.md](../AGENTS.md) supersede earlier build/release instructions for the
current maintenance phase. No application fix, new binary or version change was
made as part of this documentation handover.

## Current baseline

- Repository: [jpskidmore/telephone-jps](https://github.com/jpskidmore/telephone-jps),
  now private; future sessions need authenticated access.
- Retained release: **2.1.8/build 160**, tag **v2.1.8**, commit
  `9a32ae825e4d3bb380cb52b8452ddf7526764a25`, tree
  `ee6fbedc72ca9ed380f112b3f95dd3ebd8c38975`.
- The existing locally built application/source ZIPs, checksums and verification
  documents remain attached to [2.1.8](https://github.com/jpskidmore/telephone-jps/releases/tag/v2.1.8).
  The tag and packages still describe that exact historical commit. This handover
  is a later documentation-only change on main; do not move the tag or replace
  those assets to include it.
- **50 open audit items: #2–51; 39 P2 and 11 P3.** These include application bugs,
  two cleanup items and one documentation item. All 50 remain in the repair gate.
  Updating documentation here does not automatically close #39.
- Read-only review ended with two fresh complete quiet passes in each assigned
  scope after its latest supported finding. This is scoped discovery closure,
  not proof of zero bugs or native/provider acceptance.

## Start a future session here

1. Read AGENTS.md, this handover, [audit context](audit-2.1.8/README.md),
   [full issue snapshot](audit-2.1.8/issues.json) and
   [repair progress](audit-2.1.8/repair-progress.json).
2. Confirm private visibility, current main/working-tree state, the retained
   v2.1.8 tag and all baseline issue states using authenticated GitHub access.
   Preserve unrelated user changes. Do not assume main still equals the release.
3. Read each live issue and its immutable baseline source links. The snapshot
   preserves the full descriptions, triggers, evidence limits, proposed remedies
   and regression expectations, so this chat and external scratch folders are not
   required. Live issues and recorded fix evidence determine current repair state.
4. Use small local changes on main, with **[skip ci]** on every pushed commit.
   Delegate independent GUI, SIP and backend groups when useful. Verify overlapping
   findings individually and review asynchronous ownership across group boundaries.
5. Update repair-progress.json and the relevant issue with the actual fix commit,
   root cause and regression outcome. Close an issue only after its fix is verified.
   Never convert an incomplete item to fixed simply to reach 50.
6. Keep the release/build gate closed until **all 50** have recorded verified fixes.
   Unresolved native acceptance or a blocked finding must be recorded honestly;
   it is not a pass. Seek the owner's direction only if work cannot progress or a
   later instruction is needed to change the gate.

## Build gate and local test safety

No new Release application or downloadable candidate, signing, packaging,
version/build-number bump, release tag, upload or publication is allowed before
all 50 baseline items are fixed and verified. Targeted local development
compilation and isolated Debug test products necessary to fix and verify them
are allowed throughout the repair phase. Ad-hoc re-signing of an isolated built
Debug test host solely to make its changed test metadata runnable is allowed;
this exception does not allow signing a Release or distributable candidate.

The following complete scripts also compile a **Release application** and must
wait for the gate: `Scripts/build-test-release.sh`,
`Scripts/run-macos-validation.sh` and
`Scripts/run-isolated-audio-validation.sh`. Inspect focused test entrypoints
before use rather than assuming a script named validation is tests-only.

`TelephoneTests` is application-hosted. Normal host startup may load the user's
real preferences and accounts. Prefer a disposable macOS test profile. For an
isolated local Debug host, build-for-testing first; give the **built Debug host**
a unique disposable CFBundleIdentifier **and remove its NSMainNibFile**; update
the corresponding host identity/path in generated .xctestrun metadata and re-sign
the modified host ad hoc if required. Then use test-without-building with the
exact intended test selectors, so rebuilding does not undo isolation. A unique
ID alone still starts AppController; removing only the nib leaves the real
defaults identity. Confirm the actual metadata and selected tests.

Do not change production Release metadata or repurpose HOME/CODEX_HOME. Do not
use real SIP credentials, Contacts or recordings to make a regression pass.
Native/provider/OS tests require an appropriate isolated test environment; report
what was actually exercised. Preserve logs/results and distinguish inert SDK
outcomes from a real native call, resource effect, crash or audible result.

Existing GitHub workflows remain historical automation:
`isolated-macos.yml` skips its job for private repositories, while
`test-release.yml` can still cloud-build on project/workflow/build-script changes
and manual dispatch. **[skip ci]** suppresses push-triggered runs; it does not
protect workflow_dispatch. Do not dispatch those workflows or publish through
them. All builds/tests in this maintenance task remain local.

## Suggested repair order

Work by root cause and dependencies, keeping each item independently verified:

1. Startup/readiness/resource safety: #35, #38, #50, #51, then startup intent and
   launch/configuration #25, #27, #32, #45, #48.
2. Call/controller ownership and SIP operations: #21, #22, #23, #40, #41, #43,
   #44, #46, #47; transfer/ended controls #31, #49.
3. SIP values and audio/device recovery: #10–13, #17, #26, #29, #34, #36.
4. Persistence, credentials, recordings and event ordering: #3, #4, #14–16,
   #24, #33, #37.
5. Remaining GUI input/accessibility/history/account validation: #5–9, #18,
   #19, #20, #28, #30, #42.
6. Finish cleanup/documentation #2 and #39, checking the real retained release
   and all active code references. These also count toward the gate.

This order is advisory; the complete table below is the authoritative finite
baseline. The JSON progress file tracks fix commits, checks and limits without
rewriting the historical issue snapshot.

## Complete baseline checklist

| Issue | Audit ID | Priority | Required repair | Initial state |
|---|---|---|---|---|
| [#2](https://github.com/jpskidmore/telephone-jps/issues/2) | CLEANUP-01 | P3 | Remove unused window-resizing and string-escaping Objective-C categories | Pending |
| [#3](https://github.com/jpskidmore/telephone-jps/issues/3) | BACKEND-01 | P2 | Preserve existing call history when loading its file fails | Pending |
| [#4](https://github.com/jpskidmore/telephone-jps/issues/4) | BACKEND-02 | P2 | Do not report Clear History as complete when deleting its file fails | Pending |
| [#5](https://github.com/jpskidmore/telephone-jps/issues/5) | GUI-01 | P2 | Active-call dead-key input raises an out-of-bounds exception | Pending |
| [#6](https://github.com/jpskidmore/telephone-jps/issues/6) | GUI-02 | P3 | Elapsed call duration stops updating during hold | Pending |
| [#7](https://github.com/jpskidmore/telephone-jps/issues/7) | GUI-03 | P2 | Settings and account-entry fields omit their accessible purpose labels | Pending |
| [#8](https://github.com/jpskidmore/telephone-jps/issues/8) | GUI-04 | P2 | Clear outbound-proxy icon is exposed as Stop Progress | Pending |
| [#9](https://github.com/jpskidmore/telephone-jps/issues/9) | GUI-05 | P3 | DTMF echo replaces the row still labelled Caller, including after the call ends | Pending |
| [#10](https://github.com/jpskidmore/telephone-jps/issues/10) | SIP-01 | P2 | Use UTF-8 byte length when parsing SIP display names | Pending |
| [#11](https://github.com/jpskidmore/telephone-jps/issues/11) | SIP-02 | P2 | Preserve non-default SIP ports through redial and history conversions | Pending |
| [#12](https://github.com/jpskidmore/telephone-jps/issues/12) | SIP-03 | P2 | Preserve IPv6 brackets when parsing a SIP address with a port | Pending |
| [#13](https://github.com/jpskidmore/telephone-jps/issues/13) | BACKEND-03 | P2 | Use unique audio-device identities instead of collapsing identical device names | Pending |
| [#14](https://github.com/jpskidmore/telephone-jps/issues/14) | BACKEND-04 | P2 | Surface recording export failure and retain a durable recovery job | Pending |
| [#15](https://github.com/jpskidmore/telephone-jps/issues/15) | BACKEND-05 | P2 | Drain pending call-history writes before confirming app termination | Pending |
| [#16](https://github.com/jpskidmore/telephone-jps/issues/16) | BACKEND-06 | P2 | Handle failed Keychain credential saves before reporting account changes as saved | Pending |
| [#17](https://github.com/jpskidmore/telephone-jps/issues/17) | BACKEND-07 | P2 | Keep potentially blocking audio opens and SDK-lock waits off the UI thread | Pending |
| [#18](https://github.com/jpskidmore/telephone-jps/issues/18) | GUI-07 | P2 | Keep first-launch setup unchanged after rejecting whitespace-only account fields | Pending |
| [#19](https://github.com/jpskidmore/telephone-jps/issues/19) | GUI-08 | P2 | Validate the authentication username before dismissing the retry sheet | Pending |
| [#20](https://github.com/jpskidmore/telephone-jps/issues/20) | GUI-06 | P3 | Keep compact call-card growth inside the screen’s visible work area | Pending |
| [#21](https://github.com/jpskidmore/telephone-jps/issues/21) | SIP-04 | P2 | Preserve successful transfer results after the source call is removed | Pending |
| [#22](https://github.com/jpskidmore/telephone-jps/issues/22) | SIP-05 | P2 | Attach replacement calls to a call controller | Pending |
| [#23](https://github.com/jpskidmore/telephone-jps/issues/23) | SIP-06 | P2 | Guard late incoming-call delivery after an account is removed | Pending |
| [#24](https://github.com/jpskidmore/telephone-jps/issues/24) | BACKEND-08 | P3 | Reject stale history reloads after Clear History or newer updates | Pending |
| [#25](https://github.com/jpskidmore/telephone-jps/issues/25) | BACKEND-09 | P3 | End background activity when SIP startup fails | Pending |
| [#26](https://github.com/jpskidmore/telephone-jps/issues/26) | BACKEND-10 | P2 | Enable explicit audio recovery when hotplug remapping fails after null sound | Pending |
| [#27](https://github.com/jpskidmore/telephone-jps/issues/27) | SIP-07 | P2 | Cancel pending account registration when Offline is selected during startup | Pending |
| [#28](https://github.com/jpskidmore/telephone-jps/issues/28) | GUI-09 | P2 | Preserve the selected call when a full history shifts to include a new record | Pending |
| [#29](https://github.com/jpskidmore/telephone-jps/issues/29) | BACKEND-11 | P3 | Apply a changed ringtone output while an incoming call is ringing | Pending |
| [#30](https://github.com/jpskidmore/telephone-jps/issues/30) | GUI-10 | P2 | Keep the selected contact destination attached to its own token | Pending |
| [#31](https://github.com/jpskidmore/telephone-jps/issues/31) | GUI-11 | P2 | Preserve a manually held call when closing transfer setup | Pending |
| [#32](https://github.com/jpskidmore/telephone-jps/issues/32) | SIP-08 | P2 | Preserve manual Unavailable across automatic wake and session registration | Pending |
| [#33](https://github.com/jpskidmore/telephone-jps/issues/33) | BACKEND-12 | P2 | Invalidate pending history additions when deleting an account | Pending |
| [#34](https://github.com/jpskidmore/telephone-jps/issues/34) | BACKEND-13 | P2 | Recognise documented CoreAudio errors from implicit SDK sound opens | Pending |
| [#35](https://github.com/jpskidmore/telephone-jps/issues/35) | BACKEND-14 | P2 | Release failed reachability initialisers exactly once | Pending |
| [#36](https://github.com/jpskidmore/telephone-jps/issues/36) | BACKEND-15 | P2 | Recover empty Sound settings after a transient device query failure | Pending |
| [#37](https://github.com/jpskidmore/telephone-jps/issues/37) | CLEANUP-02 | P3 | Prune expired history subscribers from shared event lists | Pending |
| [#38](https://github.com/jpskidmore/telephone-jps/issues/38) | BACKEND-16 | P2 | Handle nullable DNS watcher creation before using Core Foundation handles | Pending |
| [#39](https://github.com/jpskidmore/telephone-jps/issues/39) | DOC-01 | P3 | Update the README local-test download entry for the published release | Pending |
| [#40](https://github.com/jpskidmore/telephone-jps/issues/40) | SIP-09 | P2 | Keep calls controllable when a local hang-up request is rejected | Pending |
| [#41](https://github.com/jpskidmore/telephone-jps/issues/41) | SIP-10 | P2 | Restore Transfer after the preliminary local hold request is rejected | Pending |
| [#42](https://github.com/jpskidmore/telephone-jps/issues/42) | GUI-12 | P2 | Validate existing account edits before re-enabling and overwriting saved values | Pending |
| [#43](https://github.com/jpskidmore/telephone-jps/issues/43) | SIP-11 | P2 | Cancel pending outgoing calls when their account is removed | Pending |
| [#44](https://github.com/jpskidmore/telephone-jps/issues/44) | SIP-12 | P2 | Preserve active-call callback ownership when an account goes Offline | Pending |
| [#45](https://github.com/jpskidmore/telephone-jps/issues/45) | BACKEND-17 | P2 | Apply saved Network configuration changes made during user-agent startup | Pending |
| [#46](https://github.com/jpskidmore/telephone-jps/issues/46) | SIP-13 | P2 | Reset ringback bookkeeping when the SIP user agent restarts | Pending |
| [#47](https://github.com/jpskidmore/telephone-jps/issues/47) | GUI-13 | P2 | Rebind the cached transfer observer when its source card redials | Pending |
| [#48](https://github.com/jpskidmore/telephone-jps/issues/48) | BACKEND-18 | P2 | Complete first-run launch state after the first account is added | Pending |
| [#49](https://github.com/jpskidmore/telephone-jps/issues/49) | GUI-14 | P3 | Connect the ended-transfer Call Back button to its redial delay | Pending |
| [#50](https://github.com/jpskidmore/telephone-jps/issues/50) | BACKEND-19 | P2 | Defer Sound codec changes until the media endpoint is ready | Pending |
| [#51](https://github.com/jpskidmore/telephone-jps/issues/51) | BACKEND-20 | P3 | Release the wrapper's PJLIB reference after failed startup | Pending |

## Before the next packaged build

After all 50 fixes and their regressions are verified, run the required complete
native suites locally on the Mac and inspect the compact GUI in Light/Dark,
keyboard and accessibility behavior, startup/quit, storage failure/recovery,
SIP intent/callback/transfer handling, audio recovery and recording. Keep real
provider/audio acceptance separate from synthetic component results and state
any untested limits. A quiet source review does not replace those checks.

Only then select the next version/build number, make one local Release candidate
from the exact repaired main commit, sign/package/verify it, and inspect those
exact packaged bytes before upload. Record the toolchain, executed results,
source/binary hashes and remaining limits in the next BUILD-VERIFICATION and
release notes. Do not reuse the 2.1.8 verification report as proof for changed
code, replace its assets or claim passes from planned tests.

## Ready-to-use future-session request

> Read AGENTS.md and docs/BUG_FIX_HANDOVER.md in the private
> jpskidmore/telephone-jps repository. Repair and verify all 50 baseline issues
> #2–51 on main, preserving the accepted compact UK-English interface and calling,
> recording and saved-data behavior. Use local development compilation and
> isolated tests only; prevent cloud workflows with [skip ci] and no dispatch.
> Update the tracked progress and issue evidence after each verified fix. Do not
> make a new Release/distributable build, bump the version, sign/package/tag,
> upload or publish until every baseline item is fixed and verified.
