# Guided routes in jps Telephone 3.5

The computer has one compact dialler and one combined call history. All enabled SIP accounts continue registering for incoming calls; the outgoing connection is selected by the current dial plan. Existing call cards, audio, recording and session-bound transfers retain their account ownership.

## Set up the plan

Open Settings → Dial plan (or More → Guided routes…). The Numbers page sets your default country, local area, default connection and emergency connection. The initial UK example is +44 / 01442; change both to your own location. Emergency routing stays unset until you deliberately select a provider you know supports emergency calls.

The Routes page assigns connections or Block to Mobile, Landline, International, Premium, Other numbers and Service codes. Default uses the explicitly saved default connection. The initial default connection is migrated once from the old first-enabled account; reordering accounts never changes it. Show prefixes displays the offline classification table and its version. Number type is not a price: choose providers using their tariffs and add exceptions for special rates or territories.

The Exceptions page adds, edits, activates, deactivates and removes precise prefixes. Each canonical prefix is unique; comments have at most 20 characters. Prefixes are literal, with no regular expressions or wildcards. International prefixes allow up to 15 digits plus the displayed +. National prefixes such as 077 are saved as +4477 using the configured country. Explicit short/service prefixes accept digits, *, #, R and P. Save commits the validated plan together; leaving an edited page/window offers Save, Discard or Cancel.

The Test page shows the expanded destination, winning rule/category and selected connection without making a call. The main Call button also exposes the current expanded destination and selected route in its tooltip and accessibility help. Both previews share provider/rule wording and include nonfatal destination guidance, such as the literal pause/recall limitation. Account names and readiness refresh from current snapshots without discarding unsaved plan edits. Use the preview to check changes before calling.

## Expansion and matching

For +44 and 01442:

| Entered | Telephone destination |
| --- | --- |
| 07799414799 | +447799414799 |
| 242110 | +441442242110 |
| 01442242110 | +441442242110 |
| +447799414799 | +447799414799 |
| 00447799414799 | +447799414799 |

Expansion happens before matching. The longest active matching prefix wins across explicitly assigned category prefixes and exceptions. At the same prefix an exception wins; a category set to Default does not contribute a separate overriding rule. International means outside the configured home country code. The default connection applies when no explicit route matches.

Exact 999 and 112 are protected from area expansion and ordinary blocks and require the separately configured emergency connection. Short and service codes are not expanded. Explicit SIP addresses retain their host, port and supported transport. Unsupported or malformed input produces a clear error rather than removing characters. R/P are literal provider syntax; they are not implemented as pause, recall or post-connect DTMF. Unsupported secure URI forms are rejected rather than downgraded.

Domestic classification is supplied for UK ranges; other supported home-country profiles have explicit trunk/area conventions and conservatively use Other numbers for domestic classification. Read [numbering coverage and sources](DIAL_PLAN_NUMBERING.md) before using a different home country. This is not a live allocation, portability, tariff or reachability database.

## Calls, callbacks and unavailable accounts

The same coordinator handles typed numbers, Contacts, telephone/SIP links, Services, call-history callbacks and call-card redial. A callback resolves the current plan; its original incoming connection does not determine the outgoing connection. An incoming AA call can therefore be returned through Localphone when the current plan says so.

A disabled, deleted, deliberately Offline or failed selected connection produces a named error. No alternative provider is silently selected. Calls waiting for registration retain their selected account and destination; changes to the plan apply to later requests. Distinct pending requests are not overwritten. While any are queued, Waiting N appears beside the outgoing-route status. Open it to inspect each frozen provider and destination, and choose Cancel for one request. Cancelling one does not restart the others’ registration deadline. Offline, removal, disable, failed registration, Quit and More → Cancel pending calls discard pending requests. The first queued request starts one 30-second deadline per account; later requests share that deadline. Expired or cancelled requests cannot dial on a later retry.

## Combined history

Incoming, outgoing and missed calls from every configured account, including disabled accounts, are sorted together. The filled account badge derives automatically from the first letter of the configured account name; its tooltip and accessibility label give the full name. Account UUIDs identify rows and stores, so duplicate initials and account renames do not change callback routing or delete the wrong record.

The merged list reads existing per-account history files without rewriting them. New records add original-account metadata and the telephone destination captured when the call was made/received; explicit SIP destinations retain their address. This keeps later area-setting changes from reinterpreting new local-call records. Legacy records keep their existing stored bytes. Their telephone, short and service users enter the current plan without an old provider host; alphabetic SIP identities retain their address. New explicit numeric SIP destinations retain their recorded SIP intent. Incoming numeric caller identities follow Telephone’s existing telephony convention: long numeric SIP From users are treated as telephone caller ID even if their host differs from the account domain. A remote From host alone does not identify a trusted provider. Explicit outgoing SIP addresses and nonnumeric incoming SIP identities retain their address; a PBX using long numeric SIP usernames should verify that caller-ID convention before returning those calls. Clear history applies to all configured accounts; individual deletion selects the original UUID store. Existing unreadable-file preservation, durable clear, failed-write retry and Quit drain remain in use.

## Implementation and testing

`DialPlan.swift` contains the pure Foundation normaliser, resolver and versioned persisted model. `DialPlanCoordinator.swift` is the main-thread admission point; `SharedDialerController` owns the sole main window. Account controllers own registration and call sessions independently of a visible dialler. `GlobalCallHistory` projects existing UUID stores and delegates durable mutations.

All builds and tests run locally. Synthetic routing, persistence and native interface fixtures do not load the normal app profile, Contacts, credentials or real call history. Published validation must report actual results separately from live SIP/audio, VoiceOver and provider-specific acceptance. Do not place emergency calls as a test.

## Native macOS design references

The interface keeps AppKit controls, native titlebar close buttons and the accepted
compact geometry. Apple describes small/mini/medium macOS control sizes for dense
interfaces in [WWDC25: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
and explains semantic/native materials in the
[Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials).
The build uses the macOS27 SDK; synthetic native Light/Dark checks verify the
selected geometry and colours on this host, without claiming complete visual or
VoiceOver acceptance on every supported macOS release.
