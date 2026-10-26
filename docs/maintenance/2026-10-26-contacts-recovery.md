# Contacts permission and lookup recovery — 26 October 2026

Issue [#63](https://github.com/jpskidmore/telephone-jps/issues/63) is implemented against source baseline `09ae94f5f3d6f16490bf718c6614ae9ea8cafb89` plus this commit. The owner resumed all remaining issues sequentially on 26 October. This record verifies source and synthetic native behaviour; it does not describe an installed update.

## Result

The modern Contacts/history path now returns explicit access and load outcomes. General Settings explains undetermined, denied, restricted and temporary failures, with Allow Contacts, Open Settings or Retry as appropriate. Only the explicit Allow action requests permission. Activation, store-change and Settings rechecks do not prompt automatically.

Only a complete successful snapshot becomes a matching index. Partial fetches are discarded. A transient fetch failure retains the previous complete index while access is valid; revoked, unknown or unsafe access clears cached names. Typed scope-narrowing failures also clear names. Stale asynchronous loads, matches and queued presentation updates cannot restore superseded contact information. Completed refreshes reload visible history even when two successful states are coalesced. Numbers and SIP use remain independent of modern Contacts availability.

The production macOS SDK supports authorised, undetermined, denied and restricted states; the iOS limited-access enum case is unavailable on this macOS target. Unknown future states conservatively block fetching and clear the cache. The generic load boundary includes a retryable failure that must not retain a previous access scope.

The row fits the existing General pane without resizing Settings. The action's accessibility name follows its actual Allow Contacts / Open Settings / Retry title. Status explicitly identifies call-history lookup; it does not certify the separate legacy ABAddressBook dialler autocomplete path tracked by #70. Raw system errors and contact data are not logged.

## Fresh local verification

Xcode 27.1 / Swift 6.4, arm64, macOS 27.0.1. Supported deployment remains macOS 15.6.

- UseCases: **203 XCTest + 144 Swift Testing cases**, zero failures.
- Telephone: **307 XCTest + 48 Swift Testing cases**, zero failures, including 18 new Contacts native tests.
- The native host has a unique isolated bundle identity and nib-free startup; the General test loads the real Settings nib with synthetic data and injected permission/settings actions.
- Regression coverage includes partial enumeration, all failure/cache outcomes, genuine empty/no-match results, retry, stale loads/matches, request failure, coalescing, revocation during fetch, explicit authorisation-denied errors and passive activation without prompts.
- Native Light/Dark assertions cover fixed window geometry, bounds, text wrapping, current accessibility labels and actual recovery-button routing. Inspected final native denied-state captures in Light and Dark: readable status/action, no clipping or overlap. The cached NSView PNGs initially appeared blank on transparency; compositing the same native pixels over the matching appearance background restored the captured controls. This is isolated native visual evidence, not full installed/provider/VoiceOver acceptance.
- Earlier runs exposed fixture timing assumptions and the static accessibility action label. Fixtures now await the initial settled refresh after displaying General, and production accessibility labels follow the current action. The final complete runs above pass.

## Evidence and reproduction

Follow `docs/VALIDATION.md`. Build TelephoneTests locally, then run `Scripts/prepare-isolated-test-host.py DERIVED_DATA` and use the generated `IsolatedTelephoneTests.xctestrun` for test-without-building. Never substitute normal application startup. Run the UseCasesTests scheme locally before the hosted suite; keep native test-manager runs serial.

Final evidence:

- `/private/tmp/jps-contacts-usecases-20261026.log`
- `/private/tmp/jps-contacts-verified-build-20261026.log`
- `/private/tmp/jps-contacts-app-verified-20261026.log`
- `/private/tmp/jps-contacts-usecases-20261026/Logs/Test/Test-UseCasesTests-2026.10.26_08-21-23-+0000.xcresult`
- `/private/tmp/jps-contacts-app-verified-20261026.xcresult`
- `/private/tmp/jps-contacts-verified-images/contacts-general-denied-light-opaque.png`
- `/private/tmp/jps-contacts-verified-images/contacts-general-denied-dark-opaque.png`
- `/private/tmp/jps-contacts-composite.swift` (background-only capture composition)

Source and log hashes are in the adjacent JSON record. All tests use synthetic Contacts boundaries; no actual Contacts grant was requested. Real OS denial/re-grant, provider calls, physical devices, full visual and proficient VoiceOver acceptance remain explicitly unverified in #62 by the owner's instruction. No real profile, Keychain, SIP account, history or recording data was used. No cloud workflow, package, installation or release was performed. The next source issue is #64.

Apple API references checked for this implementation: [authorisation status](https://developer.apple.com/documentation/contacts/cncontactstore/authorizationstatus(for:)), [request access](https://developer.apple.com/documentation/contacts/cncontactstore/requestaccess(for:completionhandler:)), [Contacts changes](https://developer.apple.com/documentation/contacts/cncontactstoredidchange), and the installed macOS Contacts SDK availability declarations. Established Contacts APIs retain the older supported-macOS path.
