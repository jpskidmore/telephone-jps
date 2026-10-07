# jps Telephone maintenance instructions

Read [the repair handover](docs/BUG_FIX_HANDOVER.md) and the tracked
[50-issue snapshot](docs/audit-2.1.8/issues.json) before implementation.
The owner's 7 October 2026 instruction is to keep this repository private and
fix all 50 audited findings before making a new application build.

## Required repair and build gate

- The finite baseline is GitHub issues **#2–51**, all 50 items, audited against
  **2.1.8/build 160, `9a32ae825e4d3bb380cb52b8452ddf7526764a25`**.
  No item is fixed merely because it is closed, labelled, duplicated or documented.
- Fix and verify every baseline finding. Record each fix commit, root cause,
  regression result and remaining limits in
  [repair-progress.json](docs/audit-2.1.8/repair-progress.json) and its GitHub issue.
  A shared fix may cover several findings, but verify each one.
- Until all 50 are fixed and verified, **do not make a new Release application,
  test-release/distributable candidate, sign or package one, bump its version,
  create/move a release tag, upload a build or publish another release**.
  Incomplete or blocked items keep the gate closed.
- Targeted **local development compilation and isolated Debug/unit tests**
  needed to implement and verify fixes are allowed. They are development products,
  not a new application candidate. Ad-hoc re-signing of an isolated modified
  Debug test host solely for test isolation is allowed; Release/candidate signing
  remains forbidden. Do not run complete release/validation scripts
  that also compile Release while the gate is closed.
- Use **main**, with no new branch or worktree unless the owner later requests it.
  Do all compilation and testing locally on the Mac; no cloud builds or workflow
  dispatch. Include **[skip ci]** in every pushed commit while repairing. Existing
  workflow/build instructions do not override this policy.
- Keep the repository private. Preserve the existing **v2.1.8** tag and all its
  uploaded assets; they are a historical baseline and must not be replaced by
  unverified fixes or regenerated packages.
- Preserve the accepted compact design and existing functionality: UK English,
  Icon rail Settings with Titled sections and one Accounts-sized window, Dial bar
  with one recent call, Pocket call cards, native close controls, Light/Dark
  appearance, green Online and red Offline. Avoid broad redesign.
- Use synthetic data and isolated test environments. Do not exercise hosted tests
  against the user's real defaults, credentials, Contacts, SIP accounts, call
  history or recordings. Follow the concrete Debug-host isolation guidance in the
  handover; preserve production metadata and the user's environment.
- Historical validation notes are evidence of earlier runs, not permission to build
  now or a claim that the audited defects are fixed. Report only checks actually run.

After the gate passes, follow the handover's local validation/release sequence.
A later explicit owner instruction can change this policy.
