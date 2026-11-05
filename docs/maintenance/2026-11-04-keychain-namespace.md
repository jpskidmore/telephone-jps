# Clean Keychain namespace — issue #77, Option B

The owner selected Option B on 4 November 2026. The final implementation follows the issue’s detailed owner decision to check the canonical namespace first, after published 3.8.1/build 168. No new release, installation or modification of the owner's Keychain was performed. [Issue #77](https://github.com/jpskidmore/telephone-jps/issues/77) remains open for installed acceptance.

## Identity and compatibility

SIP credentials now have the stable destination service `uk.jpsit.telephone.sip:<registrar>`, with label **jps Telephone — SIP account** and the exact existing account value. Registrar case, ports and spelling are preserved; no identity normalization merges accounts. Non-SIP callers retain their prior namespace. Neither namespace targets Apple's/App Store credentials or switches to the Data Protection/iCloud Keychain.

Reads check the **canonical new namespace first**. Only `errSecItemNotFound` permits fallback to the exact legacy identity. A denied, cancelled, malformed or otherwise failed canonical read never causes a second attempt against the backup. An existing canonical entry is used without reading or changing the legacy item, avoiding legacy prompts on normal subsequent lookups.

When the canonical item is absent and the legacy read succeeds, migration copies its exact bytes and access list into the **same file/login Keychain**, then independently reads the new item and compares its bytes before returning it as verified. It rechecks the canonical search list before creating the copy, in case an entry appeared while legacy permission was pending. The legacy item is never renamed, deleted or overwritten by a read. A matching creation race is verified; a differing value causes a typed failure with no password and leaves both values unchanged for explicit review. Canonical read/readback denial and cancellation likewise do not return a substitute legacy password. A source-context failure before a copy is admitted can leave the already-authorised legacy password usable with a migration warning.

The canonical entry stays authoritative on subsequent launches. An older build’s edit to a retained backup does not silently override it on upgrade; an explicit password save reconciles both copies. Known partial saves and creation conflicts retain reconciliation help until such a save.
This intentionally retains a rollback copy: **existing “blue icon v4” service fields are not deleted by this change**. New clean entries have the stable identifier and friendly label. Older builds continue to read the original service. Existing legacy labels remain untouched during a read; explicit saves give the compatibility entry its own friendly label. Label, service, access-list description and macOS prompt application identity are separate; actual prompt wording and counts must be observed on the installed candidate.

## Saves and lifecycle

An explicit password save keeps the compatibility password current first. Its update binds to the exact returned item reference rather than updating every match across the search list. The replacement is read back, the clean entry is added/updated within that item's Keychain, and its value is independently verified. Updates change password and label only, preserving each existing item's access controls. A new entry copies the source ACL; an unreadable ACL never falls back to a wider/default one.

Two Keychain items cannot be updated atomically by this wrapper. If the compatibility write succeeds but the new write/readback fails, the save reports that partial state explicitly and existing form handling prevents account settings being committed. Both items remain available for a deliberate retry; no uncertain result triggers deletion or a blind replay. Re-entering even the same password in Accounts counts as an explicit retry.

Operations are serialized. Saves use nonblocking admission so AppKit cannot wait behind a pending authorisation; utility reads may wait, then recheck request admission. The default credential broker carries its generation/invalidation check into migration, including before copy admission and readback. Already-admitted synchronous Security operations cannot be cancelled, but superseded requests cannot start subsequent migration operations. Failed/conflicting copy attempts are latched per process, bounded to 64 non-secret identities, until explicit password save or app relaunch. Ordinary cache expiry/reconnect does not repeat a failed copy attempt. Accounts exposes pending/conflict help through the password tooltip and accessibility help, without replacing owner-entered text.

The implementation uses deprecated file-Keychain reference/ACL APIs to preserve the existing store and its actual access lists. No entitlement, signing identity, Keychain search-list setting, permission grant or access group is changed. Their runtime behaviour still needs actual OS acceptance.

## Source validation — 4 November 2026

- Final successful Debug build-for-testing and newly prepared unique-identity, nib-free isolated host: **598 XCTest + 48 Swift Testing = 646 tests**, zero failures or skips.
- The additions comprise **24 namespace migration cases and three Accounts presentation/save cases**. They intercept the complete Security boundary using in-memory synthetic credentials: exact pair isolation, ACL/Keychain scoping, copy/readback, empty passwords, matching/conflicting existing entries, duplicate creation races, absence/new-only fallback, denial/cancel, corrupt data, partial saves/retry, bounded deferrals, main-thread save admission, superseded reads and actual broker invalidation.
- Existing credential broker, registration, preferences, account-save and full app regressions also pass. The canonical-first focused run passed 77 cases; this overlaps the final suite and is not added to its total.
- Unsigned arm64 Release compilation passed. The SDK reports the expected deprecations for the retained file-Keychain reference/ACL APIs. Other framework suites were not rerun or added to the 646 total.
- No real Keychain API, credential, registration, account store or permission prompt was exercised by the new migration fixtures. No package, installation or new release was produced. Source and log hashes are in the companion JSON; native results remain at `/private/tmp/jps-telephone-issue77/canonical-final.xcresult`.

## Follow-up save verification — 5 November 2026

Review of current main `bc5ec762` found that an explicit save could verify its
canonical copy in the source Keychain but still report success when a canonical
item earlier in the search list would supply a different password to normal
lookup. The minimal repair retains scoped verification and then independently
reads the effective canonical identity through the normal search list. A failed,
denied, cancelled, absent, malformed or different result follows the existing
partial-save/conflict path, preventing account settings from being committed.
It does not overwrite or delete the earlier Keychain's item.

Four new in-memory regressions failed against unchanged production code, then
passed within **81 focused XCTest cases, zero failures or skips**, after the
seven-line production repair. The original 77 focused cases also passed before
the repair. These runs overlap; they are not additive. Debug build-for-testing
and the unique-identity, nib-free copied host ran locally on arm64 macOS 27.2
(26B123), Xcode 27.2 (27B52). All credential/SIP/defaults operations in the selected
fixtures use synthetic boundaries. See [the dated evidence record](2026-11-05-keychain-save-verification.json).

This is verification at save time, not an atomic transaction across Keychains
or protection against subsequent external changes. A conflicting earlier item
is left for deliberate review; automatic retry cannot promise to reconcile it.
The extra effective read may require permission, so prompt counts still need
actual acceptance. No full app/framework suite, Release build, installation,
release, live Keychain, provider registration or signing-identity access was
performed in this follow-up. Only the disposable test-host copy was ad-hoc signed
with `-`; production metadata and the existing signing configuration were not changed.

## Installed acceptance still required

**Status checked 5 November 2026: every step below is unverified.** These are
future procedures, requiring separate owner authorisation before any test
Keychain/account setup, candidate installation or real registration. The current
source review does not access the owner's Keychain, SIP credentials, production
accounts, signing identity or installed application.

[#62 was closed as not planned on 4 November](https://github.com/jpskidmore/telephone-jps/issues/62#issuecomment-6631639583)
when the owner stopped practical testing. Its reported successes used installed
3.8/build 167 and do not cover this later migration. Keep migration acceptance
in #77; do not reopen #62 or mark its 24-scenario matrix passed.

1. **Identify the exact candidate and rollback build.** Record source revision,
   local patch/commit, app version/build, bundle hash, macOS build, architecture,
   Xcode/SDK and signing configuration. Retain an identified earlier local build;
   do not replace an immutable release. A synthetic Debug host is not evidence
   for the eventual installed candidate.
2. **Prepare an isolated acceptance environment.** Use a disposable macOS user,
   test file Keychains and synthetic app profile with controlled SIP accounts and
   endpoints. Keep production credentials, defaults and Keychain search lists
   outside the session. Record authorisation, tester and test account aliases;
   keep passwords, real account details and credential values out of evidence.
3. **Establish upgrade baselines.** In separate variants, use 3.8/build 167 and
   3.8.1/build 168 to create legacy-only credentials. Include two usernames at
   the same registrar, plus a different registrar/port identity. Record exact
   service/account mappings privately, file-Keychain location, ACL authorised
   applications/access rules and unrelated namespace metadata before upgrade.
4. **Upgrade and observe first access.** Use the exact candidate. Record prompt
   application identity, item wording, timing, number and chosen action. Allow
   only deliberate test access. Confirm each controlled account registers
   without password re-entry, with no account mix-up.
5. **Inspect labels and access controls separately.** Expect canonical service
   `uk.jpsit.telephone.sip:<exact registrar>`, the unchanged account field and
   label `jps Telephone — SIP account`. Confirm distinct accounts, exact source
   file-Keychain location and equivalent source/copy ACL rules. Check actual
   enforcement as well as displayed ACLs. Automatic migration leaves legacy
   service fields and labels intact; old “blue” entries are intentional rollback
   copies. A friendly label alone does not establish prompt/signing identity.
6. **Repeat normal use.** Relaunch repeatedly, reconnect and visit Accounts.
   Verify canonical-first behaviour, normal registration, stable item counts
   and no unexpected repeated migration prompts. Record actual counts instead
   of assuming zero prompts for an ad-hoc signed app.
7. **Exercise failures in reset disposable variants.** Cover missing/new-only
   entries, empty passwords where supported, canonical and legacy denial/cancel,
   migration add/readback denial and interrupted migration. Verify truthful
   feedback, preserved originals, no substitute password after canonical failure
   and no automatic copy-retry loop. Record unavailable injections unverified.
8. **Save a changed test password explicitly.** Confirm both copies work through
   controlled authentication, existing ACLs are unchanged and the backup label
   becomes `jps Telephone — SIP account (compatibility copy)`. Recheck other
   accounts and unrelated namespaces. Include normal account edits and fresh
   credentials, rather than only migrated accounts.
9. **Distinguish conflicts and partial saves.** An already-existing canonical
   value remains authoritative even if its backup differs. A conflicting
   creation race must fail without a substitute password. Exercise failure after
   the compatibility write and deliberately retry; account settings must not be
   committed on an unverified save. Include a canonical item in an earlier test
   Keychain than the legacy item: a scoped copy alone must not produce success
   while effective lookup still selects a different/denied credential. Other
   Keychains must not be silently overwritten or cleaned up to reconcile it.
10. **Roll back, then upgrade again.** With the recorded older build, verify both
    controlled accounts can use the retained legacy copies and register. Change
    a test password in that older build, then upgrade: its backup edit must not
    silently override an existing canonical value. Explicit password save is
    needed to reconcile them. Verify both accounts again after reconciliation.
11. **Record only observed outcomes.** For each variant record date, tester,
    exact candidate/context, steps, prompt counts, result and redacted evidence.
    Leave unexercised variants unverified. Retain legacy copies throughout the
    rollback window; deletion needs separate verification and explicit review.
    Keep #77 open until the agreed migration acceptance is evidenced.

## Apple references

- [Generic-password identity](https://developer.apple.com/documentation/security/ksecclassgenericpassword): service and account form part of the composite primary key.
- [Updating and deleting items](https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items): updates affect matching items, so query scope matters.
- [Label metadata](https://developer.apple.com/documentation/security/ksecattrlabel) is separate from the service identifier.
