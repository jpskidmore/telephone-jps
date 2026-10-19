# jps Telephone maintenance instructions

Start with [the current maintenance entry point](docs/MAINTENANCE.md). The owner
authorised the ranked roadmap on 19 October 2026, **one issue at a time in order**.
Read actual five-hour usage before/between issues and during long work; below
10% remaining, stop at a recoverable point and schedule this chat five minutes
after the reported reset. Keep the weekly allowance separate. See the entry
point for current baseline, execution controls and evidence boundaries.
Commit and verify each fix, but **install and publish only after the roadmap is
finished**, as the owner subsequently specified. Do not bump the app version or
replace the installed app for each individual source fix.

## Released application baseline — 8 October 2026

The owner's 3.5 crash in More → Guided routes… is fixed in **3.5.1/build 163**. Fresh local verification passed 665 cases; the app is built, installed and published as private Latest from immutable source `e111e5daee9e57f26c66c9a42d40b6f1f4f25edc`. The owner reported “tested - looks good”. Read [hotfix notes](docs/releases/3.5.1.md), [fresh tests](docs/releases/3.5.1-tests.json) and [publication proof](docs/releases/3.5.1-verification.md). Preserve all previous release tags/assets and all routing/data/layout behaviour. The 170 routing cases and unrelated component checks remain historical 3.5 unchanged-input evidence; no fresh rerun is claimed.

Read [the maintenance handover](docs/BUG_FIX_HANDOVER.md),
[verified repair map](docs/REPAIR_VERIFICATION.md) and
[tracked issue evidence](docs/audit-2.1.8/repair-progress.json) before implementation.
The repository remains private. The owner authorised 3.5/build 162 Guided routes after the published 3.0 repair baseline and requires main, local builds and no cloud workflows. Read [DIAL_PLANS.md](docs/DIAL_PLANS.md) and [offline numbering coverage](docs/DIAL_PLAN_NUMBERING.md) before changing routing. Historical 3.5 was built, installed and published as then-Latest from immutable source `cbfd3a0bbbca094f2f17e18b82e2904beb7e051a`; 664 complete-suite cases plus 170 separately counted dial-plan cases passed locally. Read [3.5 publication proof](docs/releases/3.5-verification.md) and its JSON record. Preserve v3.5, v3.0 and v2.1.8 tags/assets; later documentation commits do not replace a release archive.

## Retained verified 3.0 repair baseline

- Baseline issues **#2–51**, all 50 items, are recorded **fixed_verified**.
  The repair gate passed on 8 October 2026 with 617 local automated cases, zero
  failures. Source fixes are on main at `01ae5734bfd933c9048f00ef4c3ebe035fabeb0b`;
  documentation issue #39 was fixed at `a7cd66478dd7079bfd9ca89d13ce8cbe7dcd73cd`.
  Read each item's root cause, regression and practical limit in the progress file.
- **3.0/build 161** was built, ad-hoc signed, packaged and installed locally at
  `/Applications/jps Telephone.app`, then published as
  [then GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.0)
  on 8 October 2026. The immutable release/source revision is
  `6363412d56e2bc142a54058321b7873a69068c62`; all seven uploaded assets have
  verified sizes and SHA-256 matches. Read the
  [publication/package proof](docs/releases/3.0-verification.md) and its
  [machine-readable record](docs/releases/3.0-verification.json).
- After a new change, verify its affected paths and update actual evidence. Do not
  reuse old test results to certify changed code, or treat issue closure alone as
  a verified fix. Record new findings honestly; the original snapshot is history.
- Use **main**, with no new branch/worktree unless the owner later requests it.
  Do all compilation/testing locally on the Mac. Do not dispatch cloud workflows.
  Include **[skip ci]** in pushed commits. Existing workflow files do not override
  these instructions.
- Keep the repository private. Preserve **v2.1.8/build 160** and all its uploaded
  assets unchanged as the historical audit baseline at `9a32ae8`.
  Also preserve **v3.0/build 161**, its tag at `6363412` and all seven assets
  unchanged. The tag/source ZIP retain the preparation-time documentation
  snapshot; later main documentation records publication without rewriting it.
- Preserve the accepted compact design and functionality: UK English, Icon rail
  Settings with Titled sections and one Accounts-sized window, Dial bar with one
  recent call, Pocket call cards, native close controls, Light/Dark, green Online
  and red Offline. Avoid broad redesign or expanding the interface.
- Use synthetic data and isolated hosted tests. Do not run regressions against
  the user's real defaults, credentials, Contacts, SIP accounts, call history or
  recordings. Follow the nib-free unique-identity Debug-host guidance in the
  handover and preserve production metadata and the user's environment.
- Preserve main admission, serial native-worker ownership, lifecycle/selection
  generations and finalization/persistence drains when changing async code.
  Recording recovery must retain raw data after failure and remove it only after
  successful export. Read [audio](docs/AUDIO_RECOVERY.md) and
  [recording/history recovery](docs/RECORDING_RECOVERY.md).
- Keep test cases, component assertions and model/source-wiring checks separate.
  Live provider routing, physical devices, sandbox grants, visual acceptance and
  proficient VoiceOver remain separately recorded manual boundaries.

Follow [VALIDATION.md](docs/VALIDATION.md) for the local candidate/release sequence,
JPS_DEBUG_DERIVED_DATA/JPS_DEBUG_BUILD_LOG reproduction and dependency provenance.
A later explicit owner instruction can change this policy.
