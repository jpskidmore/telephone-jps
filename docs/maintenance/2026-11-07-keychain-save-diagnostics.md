# Issue #77 reopened — save failure diagnostics, 7 November 2026

**Superseded diagnostic checkpoint:** build 171 identified canonical creation returning -25293. #77 is now closed on owner save/restart confirmation, and the correction is published in 3.9.1/build 173. See [direct observation, correction, owner acceptance and publication](2026-11-07-keychain-acl-copy.md). Unknown-status, open-issue and requested-next-evidence statements below describe the earlier checkpoint.

The owner reports the compatibility-saved/new-entry-not-verified alert in **3.9/build 170**, after **allowing** the Keychain prompt. The actual failing Security operation/status is **not yet known**. #77 is reopened; #71 remains completed and #62 remains closed not planned. Published 3.9 and its immutable assets are unchanged.

## Substantiated diagnostic defect and narrow source repair

The alert replaces the existing NSError OSStatus with one generic visible message. It conflates compatibility readback, access-context copying, canonical creation/update, scoped readback and effective search-list readback. Thus allowing the prompt does not establish which operation failed or why. A previously covered shadowing/readback failure is one possibility, not a diagnosed cause.

Source [`e7b8650`](https://github.com/jpskidmore/telephone-jps/commit/e7b865008fab2e473a6b6e8132b1c4c21af08a4f) appends a fixed human-readable operation name and numeric Keychain error to the visible save error. NSError also includes `AKCredentialSaveStage` with one fixed string. The error contains no password, SIP service/account, Keychain path or query dictionary; there is no new logging. Existing compatibility-first explicit writes, canonical-first normal reads, ACL/keychain scoping, independent scoped/effective verification, broker invalidation, return status and account-settings rejection are unchanged. This repairs diagnostic observability, **not the owner's unresolved save failure**.

The Keychain implementation blob is identical in the 3.8.2 and 3.9 release sources; that does not rule out signature, access-control or environmental effects during an upgrade.

## Native verification

Six new failure-stage/code/redaction cases first failed against unchanged production: **34 cases, 28 passed and six failed** (12 assertion failures). A test-helper Objective-C macro syntax error was corrected before this counted run; an initial zero-case execution after that compile failure is not validation evidence.

Final diagnostic source passed **66 focused XCTest cases, zero failures/skips**, in the uniquely identified nib-free Debug host: `KeychainNamespaceMigrationTests`, `CredentialBrokerTests`, `CredentialPreferencesTests`. Seven new diagnostic cases cover compatibility write/readback, access context, canonical add/update/readback and effective lookup. Existing conflict, denial/cancellation, rollback preservation, credential broker and Accounts rejection cases passed within this selection. This is not a repeated full 929-case release run.

Unsigned arm64 Release compilation passed. A **local diagnostic candidate only**, version **3.9.1/build 171**, was built with command-line version overrides; project release metadata remains 3.9/170. Its Info.plist records `JPSDiagnosticBuild` and source commit before ad-hoc signing. Deep/strict signatures, arm64, sandbox/ad-hoc entitlements, absence of local user paths and extracted ZIP parity passed: **52 regular payloads and six symlinks**. It is unnotarised and has no public tag/release. No normal application launch or installation was performed by the agent.

Candidate: `jps-Telephone-3.9.1-diagnostic-arm64.zip`, 3,020,136 bytes, SHA-256 `d691fcfe9a8f8affb5564858b39cfcecceecf3a5f53d2d827b0cf49695aaef08`. Full local logs and hash record are under this chat's `work/keychain-save-2026-11-07`; the user-facing candidate and verification JSON are under `outputs/keychain-diagnostic`.

## Required next evidence

The owner can run the candidate after quitting the existing app, repeat the already-failing save once, and report only the new final operation/error-code line (or say if the save succeeds). It may prompt again because the diagnostic app has a new ad-hoc signature. Do not send credentials or Keychain screenshots. The agent does not inspect, mutate or delete the owner's credentials, search list, defaults, SIP account or live data. No bypass of canonical verification, broad permission change, credential cleanup or root-cause fix is justified before this evidence. The earlier installed #77 acceptance remains distinct from these synthetic tests.
