# Contacts first-use permission — issue #78, 8 November 2026

**Resolved and published:** the owner accepted local build174 as good and requested release/merge. The repair is public in [3.9.2/build175](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.9.2); #78 is closed on that scoped acceptance. Earlier pending/candidate statements below retain their original checkpoints.


The owner reported missing names in both dialler completion and caller/history lookup, then identified that access required the Settings **Allow Contacts** button. The owner explicitly requested an automatic request. This is a first-use permission/discoverability defect, not evidence of a failed Contacts enumeration or broken matching algorithm. No actual contact values or system permission settings were inspected or changed.

## Source change

Source `92d2616d11b5fae22f14cabd61f919ff66fd39bb` starts the Contacts access flow during normal application startup, after default registration/settings migration. The recovery controller admits that automatic request once per process and coalesces it with any already-running passive refresh. The existing adapter requests OS permission **only when not determined**: an existing authorised/denied/restricted choice does not prompt again. Enumeration, activation and later passive refresh do not independently request access. After a request finishes, the existing matching index and dialler snapshot refresh. Settings retains explicit retry/recovery; a failed request is not automatically retried repeatedly. No persistent defaults, identity, entitlement scope or matching algorithm is broadened.

## Synthetic regression and process gates

Three new native tests exercise actual adapter/index/dialler publication and recovery code with injected permission/fetch operations and detached synthetic contacts:

- Undetermined first use requests once, then supplies both phone/history matching and dialler completion; repeated startup and activation do not request again.
- Existing authorised, denied and restricted choices preserve their behavior; denied/restricted choices never enumerate or prompt.
- Failed first-use requests do not repeat on activation; explicit Settings retry can request again and failed requests never enumerate.

The first two regressions failed against unchanged production: **20 focused Contacts cases, 18 passed/two failed**. An intermediate full run had **598 cases, 597 passed/one failed** because the test waited for a restricted action to become enabled; the assertion was corrected to respect its deliberately disabled state. Final isolated application validation passed **599 cases, zero failures/skips** (551 XCTest + 48 Swift Testing). Domain/UseCases were not rerun for this app-only change; no new full-release 942-case result is claimed.

Both `build-test-release.sh` and `run-macos-validation.sh` now invoke `verify-contacts-regressions.py` against the actual isolated result bundle. Six named first-use/lookup/denial/revocation regressions must have executed and passed; missing, skipped or failed cases stop validation. The old release result was rejected, while the final result passed. A separate source-wiring assertion checks the normal startup hook because executing the real AppController startup in the isolated host would access an owner profile. That assertion is not a real startup integration test.

Release bundle verification also requires the normal and signed Contacts/address-book entitlement and a non-empty `NSContactsUsageDescription`. The strengthened check passed on the existing signed 173 package (metadata/entitlement fixture only, not certification of its old Contacts behavior). The new candidate's actual signature/entitlements and usage description were independently checked. Shell syntax/Python compilation checks passed.

## Candidate and limits

Unsigned arm64 Release compilation passed using version overrides **3.9.2/build 174**. Project release metadata remains 3.9.1/173. The working files tested/compiled match the subsequently committed source; no application source bytes changed after that validation. Info.plist records the candidate source before ad-hoc signing. Strict/deep signatures, arm64, sandbox/Contacts entitlements, usage description, absence of local user paths and ZIP extraction parity passed: **52 regular app files/six symlinks**.

Local candidate `jps-Telephone-3.9.2-contacts-candidate-174-arm64.zip`: **3,021,533 bytes**, SHA-256 `80547324465acbfe012e6959016ea09574b97e4800ab7d47a189f1bf3dcbc7da`. It and the verification JSON are under this chat's `outputs/contacts-first-use`; detailed logs are in `work/contacts-first-use`, result bundle `/private/tmp/jps-contacts-first-use-final.xcresult`. This is ad-hoc signed, unnotarised and not a public release/tag. Public Latest remains immutable 3.9.1/build 173.

No real CNContactStore, Contacts prompt, owner data or normal production profile was used by these tests. No installation, permission grant, actual contact lookup, call, cloud CI dispatch or Cloudflare change was performed. Real first-use prompting and permitted names still require owner confirmation; #78 stays open. A prior denial requires System Settings recovery; a prior grant is reused and should not prompt again. Do not reset real privacy grants merely to demonstrate a prompt. #77 and #71 remain completed; #62 remains closed not planned.

## Owner acceptance and publication

The owner said **“release, merge etc - it's good”** after receiving local build174. This accepts the reported Contacts behavior and authorises publication; the fix was already on main. It is not a per-scenario record proving an actual undecided-to-granted OS prompt, denied/restricted choice, every real address-book lookup or live-call/rollback behavior. No agent Contacts access or installation is inferred.

Published **3.9.2/build175**, exact source/tag `c4454fc8f3315b09f706d13662f8762d02dcbbc6`, passed a fresh full **942-case** release run (zero failures/skips), mandatory Contacts gates, separate components, Release/signing/package/source checks and all seven published-download hash checks. No diagnostic-only markers remain. [Publication proof](../releases/3.9.2-verification.json) records unchanged prior releases/tags/assets. #78 is closed completed; #77/#71 completed and #62 closed not planned. No production-profile launch, user-data operation, privacy grant, cloud workflow dispatch or Cloudflare change was made.
