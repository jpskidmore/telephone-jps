# Guided dialling-plan numbering core

`Telephone/DialPlan.swift` uses Foundation only. It has no provider, network,
Contacts, window or native SIP operations. `Scripts/run-dial-plan-tests.sh`
compiles that production file and a synthetic regression harness locally under
`/private/tmp`. Preferences use a unique disposable suite; no real accounts or
user data are loaded.

## Numbering sources and version

The bundled classification version is
`ofcom-2025-04-22+libphonenumber-d145763-v1`. It is offline and changes only with a
source update, so a future metadata change cannot silently alter a running plan.

UK designations are based on Ofcom's
[National Telephone Numbering Plan, effective 22 April 2025](https://www.ofcom.org.uk/siteassets/resources/documents/phones-telecoms-and-internet/information-for-industry/numbering/other/national-numbering-plan.pdf),
checked on 8 October 2026. Geographic 01/02 ranges are Landline. Mobile covers
071–075, 077–079 and the specific 07624 exception. Personal 070, paging 076,
corporate 055 and location-independent 056 are Other. The 03 and designated 08
ranges are Service; 090/091/098 are Premium. These labels describe number ranges,
not a connection's actual tariffs, allocation or reachability.

Country calling codes, trunk/international prefixes and bounded possible lengths
come from Google's
[libphonenumber metadata at d1457634c3d95e570dad433ee0ab400beb343a56](https://github.com/google/libphonenumber/blob/d1457634c3d95e570dad433ee0ab400beb343a56/resources/PhoneNumberMetadata.xml).
The original XML SHA-256 is
`9d3b07b53c7e8a437ddc316249620b51d4090987026f9e8ffb9743aab4e4d5a6`.
Domestic normalisation supports +44, +1, +33, +49 and +39 profiles. Italy's
significant leading zero is retained. NANP uses 011 for international dialling;
the other supported profiles use 00. Explicit international numbers for other
recognised calling codes retain their form and get structural length checks.
Foreign national numbers are Other unless outside the configured country, where
they are International. Mobile/Landline/Premium classification is UK-only.

## Normalisation and matching

The default country is +44 and default area is 01442. Both are configurable. The
core turns 07799414799 into +447799414799 and 242110 into +441442242110 before
matching any route. Ordinary presentation separators are removed; unknown
characters, multiple plus signs and unsupported telephone-link parameters are
rejected rather than discarded. A blank area permits national/international
numbers but fails a local number that needs its area.
Telephone's existing `sip://` and `tel://` URL aliases are normalised to their
`sip:`/`tel:` schemes before classification, including preview. This compatibility
conversion never removes query headers or otherwise unsupported parameters.

Exact 999 and 112 remain short emergency destinations and use only the explicit
emergency account. They precede ordinary normalisation and all category/exception
rules. No emergency connection is inferred during migration. A missing, removed,
disabled or offline selected connection fails explicitly; there is no fallback.
This is routing protection, not evidence of working provider emergency services.

Other short codes, recognised UK 116/118 and relay forms, and * / # service forms
stay literal. R/P syntax stays literal too; it is not a post-connect pause/recall
implementation, and native/provider rejection is surfaced by the call layer.
SIP destinations retain their identity, port and one supported transport parameter
and bypass telephone-number expansion. Only `transport=udp`, `tcp` or `tls` is
accepted; other/duplicate URI parameters and query headers are rejected because
the native/Swift bridge cannot preserve them. Ports must be numeric from 1 to
65535 and IPv6 hosts must use square brackets. Unsupported `sips:` schemes are rejected explicitly;
TLS remains a connection/transport setting. The production SIP parser is the
final authority for the supported SIP syntax.

Each explicit category target generates its documented prefix routes. Category
Default contributes no active prefix. The longest active prefix across generated
routes and exceptions wins; an explicit exception wins an equal-prefix tie.
International and unclassified Other use category fallbacks. No array/row order
changes precedence. Block has the same prefix precedence as a connection.
Exception prefixes can be canonical + forms, the configured country's national
forms or literal short/service forms; equivalent 07, +447 and 00447 are saved as
one +447 prefix and duplicates are rejected, even if disabled. Numeric prefixes
have at most 15 digits excluding +; literal service prefixes have at most 15
characters from 0–9, *, #, R and P. Comments have at most 20 characters.

## Integration and persistence contract

`DialPlanStore` is MainActor-bound and accepts injected `UserDefaults`.
`configuration` is a detached dictionary. `updateConfiguration` validates and
encodes the complete draft before committing it; rejected edits leave the saved
plan intact. Saved data is versioned JSON at `JPSDialPlanConfigurationV1`.
Only a committed update posts `JPSDialPlanDidChangeNotification` with that store
as its object. `previewDestination:configuration:accounts:error:` validates a
draft and resolves it without writes or notifications. A malformed/newer saved
plan is retained and blocks routing until explicitly repaired.

Account targets are stable UUIDs. `online` and outgoing-capable `unavailable`
permit calls; `registering`/`needsRegistration` permit a queued registration wait.
`offline` means intentional Offline and fails. Failed/unknown, disabled, missing
or duplicated account identities fail without choosing a different connection.
The coordinator must capture the immutable returned UUID and destination before
starting asynchronous registration and retain its existing cancellation guards.

History captures the canonical telephone destination at dial/receipt time,
separately from raw input/provider identity and the actual originating connection.
For incoming calls, Telephone's existing numeric caller-ID convention treats a
normalisable numeric SIP From user as a telephone CLI, regardless of From host;
the host does not reliably identify the originating provider. Such records route
callbacks by the normalised telephone number. Non-numeric incoming SIP identities
retain their SIP destination. Explicit outgoing numeric SIP identities bypass
telephone normalisation and retain their host. Numeric extensions/anonymous or
unresolvable caller identities must not be asserted to identify a reachable PSTN
subscriber; they remain a separately recorded provider/caller-ID boundary.
Callback always re-evaluates today's plan against that stored destination; an AA
incoming call may call back using Localphone. Changing country/area defaults must
not reinterpret an already stored international destination. Origin badges show
historical account identity and do not pin callbacks. SIP/service/short records
have no `canonicalNumber` and retain their literal dispatch destination.

## Verification limits

The local harness covers canonical equivalents, invalid input, metadata-specific
trunks, UK classification boundaries, prefix/Block precedence, protected exact
emergencies, selected-account failure, changed-plan callbacks, draft preview,
notifications, persistence, malformed/future schemas and migration. It does not
establish actual provider tariffs/routing/emergency access, SIP registrations,
physical media, account UI wiring, or imported provider/PBX caller-ID assumptions.
