# Keychain read ownership — issue #73

The owner selected #73 ahead of #70/#71 on 27 October. This source repair replaces
the confirmed duplicate and synchronous read paths. The released 3.7/build 166
archive remains unchanged; no new release or installation is claimed.

## Result

Registration and Accounts use one `AKCredentialBroker`, keyed by the exact
existing service/account pair. A serial utility worker performs the Security
read; concurrent readers share its result and callbacks arrive asynchronously
on main. Success, legitimately empty success, missing items, cancellation,
denial, corrupt data and other failures remain distinct.

Cancellation or denial cannot become an empty SIP password. Registration retains
an explicit retry latch, so reachability events, timers and wake cannot retry a
failed read automatically. Choosing Online deliberately retries. Immutable results
are fenced by account, credential identity and generation; removal, replacement,
Offline, sleep, session suspension and quit close admission. A queued wake waits
for the other workspace observers and rechecks lifecycle state before resuming.

The authentication sheet receives the already-admitted credential and performs
no Keychain read while loading or presenting. An obsolete sheet cannot save a
password or reconnect. Old callbacks cannot unlock a newer retry or remove its
same-account registration. Secret fields are cleared when their presentation
ends; no secure zeroisation of ordinary strings is claimed.

Accounts layout construction performs no credential read while the pane is
hidden. Selection and edits have independent generation checks. An unchanged
save neither reads nor rewrites the password. Changing the credential destination
requires a deliberate replacement; the previous secret is not copied to another
key. Closing the window clears its secret and rejects late results. Failed lookup
retry leaves the account disabled until a successful result and another deliberate
enable action; the checkbox explains that next step.

The cache holds at most 64 admitted entries. Successful/missing results expire
after 300 seconds, with an idle purge interval of at most 30 seconds. Failed reads
stay latched until invalidation; a full set of blocked entries rejects additional
admission instead of forgetting a denial and prompting again. Existing storage
namespace, item permissions and signing policy are unchanged. Writes still use
the existing three synchronous UI action paths, invalidating cached reads before
and after the operation; this is not a general concurrent-write transaction API.
An admitted main-queue delivery retains its result until delivery or invalidation;
consumers own their admitted copies for their checked lifecycle.

## Verification

The current candidate has **964 passing suite cases**: Domain 28 XCTest;
UseCases 206 XCTest + 147 Swift Testing; ReceiptValidation 5 XCTest; isolated
Telephone 530 XCTest + 48 Swift Testing. A 67-case focused selection also passed
and overlaps that total. The final app run includes two additional wake-order
regressions. Earlier framework inputs were unchanged by that final bounded fix.
The final unsigned arm64 Release build passed.

Separate checks passed: 105 recording ownership assertions, 32 inert native SIP
lifecycle checks, 18 URI assertions, 11 callback checks, 11 audio wiring checks
and six recording lifecycle-model checks. They are not added to the suite total.
Real nib/NSWindow tests exercise hidden-pane admission, close/reopen, accessible
feedback and existing compact geometry with synthetic defaults and credentials.
The unique-identity nib-free test host prevents normal application startup.

The [JSON record](2026-10-28-keychain-reads.json) contains exact source and log
hashes, counts, environment and limits. Earlier diagnostic failures are retained:
the routing-only fixture lacked credential selectors; a focused preferences
fixture omitted its ringtone default; and a window fixture manually admitted a
read before native appearance admitted its current read. Those fixtures were
corrected. Product races found during review received separate regressions.

## Practical boundary

Tests use injected readers/writers and synthetic credentials. No real Keychain,
profile, Contacts, provider or permission grant was accessed. The source repair
does not prove the exact cause of the owner's original two OS prompts or promise
one prompt across different protected items or ad-hoc signed updates. Actual
prompt/grant behaviour, signed-upgrade continuity, provider calling and proficient
VoiceOver acceptance remain pending under #62 by owner choice.

Apple documents [the blocking Security query](https://developer.apple.com/documentation/security/secitemcopymatching(_:_:))
and [code identity requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
The shared broker is our implementation informed by those APIs; no signing or
Keychain trust change is part of this fix.
