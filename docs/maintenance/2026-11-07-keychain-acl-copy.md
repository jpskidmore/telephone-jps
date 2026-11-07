# Issue #77 — observed creation rejection and ACL-copy candidate

## Direct observation

On 7 November 2026 the agent read only the installed app's visible alert and bundle metadata. The owner-installed **3.9.1/build 171**, diagnostic source `e7b865008fab2e473a6b6e8132b1c4c21af08a4f`, showed:

> Saving the new Keychain entry (Keychain error -25293).

This identifies `canonical-write`, specifically `SecItemAdd`, returning `errSecAuthFailed`. The compatibility write, compatibility readback and source access/file-Keychain context had already succeeded. This is not a canonical update/readback failure and does not establish why creation was denied. No password field, credential item, account settings or other live data was read or changed by the agent. The owner's earlier report was 3.9 with the prompt allowed.

## Narrow source correction; installed root cause still unproven

Source [`80c5493`](https://github.com/jpskidmore/telephone-jps/commit/80c5493c00432251bd99f13c17087ff0484140fa) prepares only the detached access snapshot used to create a new canonical item. Apple's [item-copy implementation](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/Item.cpp) removes per-item integrity and partition ACLs before copying its own access object. Our previous code supplied the whole snapshot explicitly, bypassing that internal copy preparation. Reusing those bindings is an unsupported assumption and a plausible contributor to this incident, **not a demonstrated explanation of the owner's -25293**.

The correction retains the opaque owner, ordinary rights, trusted applications and prompt selectors. It removes only managed-only integrity/partition ACLs from the copied policy; an unfamiliar ACL mixing those tags with user rights is rejected before editing. No default/wider access policy is substituted. The original persisted ACL is never set or edited. The destination remains in the same source file Keychain; canonical-first reads, denial/cancellation behavior, legacy rollback preservation and independent scoped/effective verification are unchanged. Existing canonical updates retain their own ACL.

Apple's [ACL implementation](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/ACL.cpp) keeps removed entries as deleted tombstones in the snapshot. Managed tags are cleared before removal so new-item integrity setup cannot select a deleted integrity entry. Deleted entries are skipped when applying a new access object. This is done exclusively on the detached snapshot, never on persisted source access. No Security.framework private API or lossy owner/ACL reconstruction is used.

## Fresh local evidence and limits

- Final uniquely identified, nib-free Telephone Debug host: **596 tests passed, zero failures/skips**: 548 XCTest and 48 Swift Testing. Includes three new native in-memory Security ACL cases for managed-tag removal with ordinary contents preserved, unchanged ordinary policy, and mixed-policy rejection before editing; existing namespace/rollback, diagnostics and Accounts rejection cases also passed. Domain/UseCases were not rerun for this correction.
- Initial experimentation: a no-op helper run had 38 cases, 36 passed/two failed. An intermediate full run had 596 cases, 595 passed/one failed because the first test incorrectly expected removed ACL objects to disappear from `SecAccessCopyACLList`. Apple retains tombstones; the implementation and assertion were corrected to clear/check tags before deletion. These runs do not reproduce the owner's failure and are not final-pass evidence.
- Opt-in [private native fixture](../../Scripts/test-keychain-acl-copy.m), linked to the actual `AKKeychain.m`, passed creation and scoped byte-for-byte readback of a synthetic original and prepared destination in a freshly created `/private/tmp/jps-acl-fixture-*/fixture.keychain`. UI interaction was disabled. Every item operation names that private Keychain explicitly. The fixture deleted its own Keychain and verified the search list was unchanged. Apple's [StorageManager](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/StorageManager.cpp) excludes private non-login/non-System creation from search-list updates. No default/search-list setter or real credential query is used. **The unchanged whole-ACL control also succeeded**, so this clean fixture validates the correction's native compatibility but does not reproduce the owner's environment or prove the incident fixed.
- Fresh arm64 unsigned Release compilation passed; candidate ad-hoc deep/strict signing, sandbox entitlements, arm64 metadata, absence of `/Users/` payload paths and extracted ZIP parity passed: **52 regular files/six symlinks**. No launch, installation or owner account operation was performed by the agent. Existing simulator-version and test-host QoS warnings are not native macOS compilation/test failures.

Local logs are in this chat's `work/keychain-save-2026-11-07`: `acl-final-build.log`, `acl-final-tests.log`, `acl-release-build.log`, `acl-fixture-final.log`, `acl-signature.log`; final result bundle `/private/tmp/jps-keychain-acl-final.xcresult`. The output verification JSON records their SHA-256 values.

## Owner candidate, not a public release

**3.9.1/build 172**, source `80c5493c00432251bd99f13c17087ff0484140fa`, uses command-line version overrides and diagnostic Info.plist markers. Project metadata remains 3.9/170. Candidate `jps-Telephone-3.9.1-candidate-172-arm64.zip`: **3,053,033 bytes**, SHA-256 `1e5eb4f1c7529b45ade65198a0a87327673da116f58f844c76ede04ca650787b`. The candidate and verification JSON are in `outputs/keychain-candidate-172` in this chat. It is ad-hoc signed, unnotarised, without a public tag/release.

The owner can quit the old app and try the same save once in build 172. Keep #77 open until the result is known; record only success or its fixed operation/error-code line. A successful owner save would be separate installed evidence, not full multi-account/upgrade/rollback acceptance. Do not delete credentials, reset Keychain, relax permissions, bypass verification or retry automatically. Published 3.9 and all prior tags/assets remain unchanged. #71 stays completed; #62 stays closed not planned. No cloud workflow was dispatched and no Cloudflare resource was altered.
