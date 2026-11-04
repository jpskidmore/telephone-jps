# Clean Keychain namespace — issue #77, Option B

The owner selected Option B on 4 November 2026. The source implementation is based on main `0d8b196`, after published 3.8.1/build 168. No new release, installation or modification of the owner's Keychain was performed. [Issue #77](https://github.com/jpskidmore/telephone-jps/issues/77) remains open for installed acceptance.

## Identity and compatibility

SIP credentials now have the stable destination service `uk.jpsit.telephone.sip:<registrar>`, with label **jps Telephone — SIP account** and the exact existing account value. Registrar case, ports and spelling are preserved; no identity normalization merges accounts. Non-SIP callers retain their prior namespace. Neither namespace targets Apple's/App Store credentials or switches to the Data Protection/iCloud Keychain.

Reads remain **legacy first**, with clean-namespace fallback only when the legacy item is absent. A denied, cancelled, malformed or otherwise failed legacy read never causes a second attempt against another copy of the secret. The legacy password stays authoritative for older-build compatibility. Once that read succeeds, migration copies its exact bytes and access list into the **same file/login Keychain**, then independently reads the new item and compares its bytes before returning it as verified. The legacy item is never renamed, deleted or overwritten by a read. Existing matching copies need no writes; conflicting copies remain unchanged and return a separate migration warning alongside the already-authorised legacy password.

This intentionally retains a rollback copy: **existing “blue icon v4” service fields are not deleted by this change**. New clean entries have the stable identifier and friendly label. Older builds continue to read the original service. Existing legacy labels remain untouched during a read; explicit saves give the compatibility entry its own friendly label. Label, service, access-list description and macOS prompt application identity are separate; actual prompt wording and counts must be observed on the installed candidate.

## Saves and lifecycle

An explicit password save keeps the compatibility password current first. Its update binds to the exact returned item reference rather than updating every match across the search list. The replacement is read back, the clean entry is added/updated within that item's Keychain, and its value is independently verified. Updates change password and label only, preserving each existing item's access controls. A new entry copies the source ACL; an unreadable ACL never falls back to a wider/default one.

Two Keychain items cannot be updated atomically by this wrapper. If the compatibility write succeeds but the new write/readback fails, the save reports that partial state explicitly and existing form handling prevents account settings being committed. Both items remain available for a deliberate retry; no uncertain result triggers deletion or a blind replay. Re-entering even the same password in Accounts counts as an explicit retry.

Operations are serialized. Saves use nonblocking admission so AppKit cannot wait behind a pending authorisation; utility reads may wait, then recheck request admission. The default credential broker carries its generation/invalidation check into migration, including before copy admission and readback. Already-admitted synchronous Security operations cannot be cancelled, but superseded requests cannot start subsequent migration operations. Failed/conflicting copy attempts are latched per process, bounded to 64 non-secret identities, until explicit password save or app relaunch. Ordinary cache expiry/reconnect does not repeat a failed copy attempt. Accounts exposes pending/conflict help through the password tooltip and accessibility help, without replacing owner-entered text.

The implementation uses deprecated file-Keychain reference/ACL APIs to preserve the existing store and its actual access lists. No entitlement, signing identity, Keychain search-list setting, permission grant or access group is changed. Their runtime behaviour still needs actual OS acceptance.

## Fresh source validation

- Final successful Debug build-for-testing and newly prepared unique-identity, nib-free isolated host: **598 XCTest + 48 Swift Testing = 646 tests**, zero failures or skips.
- The additions comprise **24 namespace migration cases and three Accounts presentation/save cases**. They intercept the complete Security boundary using in-memory synthetic credentials: exact pair isolation, ACL/Keychain scoping, copy/readback, empty passwords, matching/conflicting existing entries, duplicate creation races, absence/new-only fallback, denial/cancel, corrupt data, partial saves/retry, bounded deferrals, main-thread save admission, superseded reads and actual broker invalidation.
- Existing credential broker, registration, preferences, account-save and full app regressions also pass. Earlier focused runs passed 73 and 76 cases respectively; those overlap the final suite and are not added to its total.
- Unsigned arm64 Release compilation passed. The SDK reports the expected deprecations for the retained file-Keychain reference/ACL APIs. Other framework suites were not rerun or added to the 646 total.
- No real Keychain API, credential, registration, account store or permission prompt was exercised by the new migration fixtures. No package, installation or new release was produced. Source and log hashes are in the companion JSON; native results remain at `/private/tmp/jps-telephone-issue77/final.xcresult`.

## Installed acceptance still required

Use controlled accounts to check upgrade from 3.8/3.8.1, existing and newly created entries, two accounts sharing a registrar, different registrar/port identities, explicit password changes, empty/missing items, denial/cancel, conflicting entries, repeated relaunch and rollback to the previous local build. Independently check actual registration, both item values, exact ACLs and file-Keychain location, Keychain Access labels/service fields, and macOS prompt wording/count. Do not log password values. Do not remove legacy entries before this reversible behaviour is confirmed. Parent #62 retains real provider, permission and proficient VoiceOver acceptance.

## Apple references

- [Generic-password identity](https://developer.apple.com/documentation/security/ksecclassgenericpassword): service and account form part of the composite primary key.
- [Updating and deleting items](https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items): updates affect matching items, so query scope matters.
- [Label metadata](https://developer.apple.com/documentation/security/ksecattrlabel) is separate from the service identifier.
