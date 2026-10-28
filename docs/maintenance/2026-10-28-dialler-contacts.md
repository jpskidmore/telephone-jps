# Dialler Contacts snapshot — issue #70

Record date: 28 October 2026. Source base: `83d691eaa9d7f348b895720c79c2637ae080d2e6`.

Dialler completion and token enrichment now read an immutable `ContactCompletionSnapshot` rather than synchronously searching AddressBook from the token-field callbacks. The existing Contacts actor and matching-index enumeration build the snapshot; typing and token commit add no second directory-fetch pipeline. Main-actor publication uses admission tickets so store, activation, access and lifecycle changes reject late snapshots and stale enrichment. Failed or incomplete completion loads expose no snapshot. Permission requests remain in the existing explicit recovery/settings action.

The snapshot preserves supplied record and destination order, both completion forms, duplicate representations, first-result input capitalization, company/person matching, multiword name searches, raw phone prefixes and case-insensitive SIP prefixes. All phones and raw SIP-labelled emails remain available; ordinary email addresses do not become dial targets. Filtering remains O(n), with no result cap or deduplication. Token formatting and the per-token selected destination remain separate from directory lookup, and stale enrichment falls back to the entered literal URI.

## Synthetic parity and measurement

The final pure engine passed **88 normalized completion-input comparisons**: 57 across the 100/1,000/10,000 main corpus and 31 additional leading/trailing/repeated-whitespace and normalized-empty-name cases. A further **21 token contact and ordered-destination comparisons** passed. The complete ordered arrays were compared without truncation, including a 45,980-result broad query. These results cover the recorded corpus, not every possible raw system record.

| Synthetic contacts | Legacy completion p50 / p95 / max, ms | Snapshot completion p50 / p95 / max, ms | Cold snapshot construction, ms |
| ---: | --- | --- | ---: |
| 100 | 0.261 / 0.944 / 0.987 | 0.141 / 0.291 / 0.306 | 0.365 |
| 1,000 | 2.453 / 9.357 / 9.834 | 0.740 / 1.439 / 1.533 | 1.637 |
| 10,000 | 25.055 / 110.401 / 117.395 | 7.223 / 13.908 / 13.987 | 13.947 |

Each main size has 95 measured completion calls after two warm-ups per input, on the process main thread with equivalent autorelease-pool boundaries. Cold construction has one sample per process. These timings measure synthetic predicate/string CPU work; **they do not measure actual AddressBook index, store or disk latency or establish a real-world speedup**. Candidate token timing covers lookup only, excluding formatter/URI/menu construction, so it is not compared as a full callback speedup. Actual Contacts enumeration and actor-publication latency were not measured.

At 10,000 records, physical footprint increased by **17,596,440 bytes** across fixture-to-contact conversion and snapshot construction. The process already retained the raw fixture and complete expected-output JSON. This delta and the recorded absolute memory values are not measurements of the app's live cache or steady-state memory.

The [benchmark tools](../../Scripts/ContactsCompletionBenchmark/README.md) extract the legacy delegate, name and label methods from immutable baseline `83d691eaa9d7f348b895720c79c2637ae080d2e6`. They use genuine native `ABSearchElement.matchesRecord` over detached synthetic NSObject records; nine positive/negative predicate cases passed. Before fixtures, fail-fast guards cover `ABAddressBook.addressBook`, AddressBook/ABRecord/ABPerson allocation and CNContactStore allocation. All five guard probes returned the expected exit code 70; measured runs recorded zero forbidden store entries and balanced synthetic locks. Shared AddressBook and standard defaults resolve only to in-memory stubs. The candidate executable contains no AddressBook, Contacts or PJSIP framework dependency. The [JSON evidence](2026-10-28-dialler-contacts.json) records provenance, exact input/artifact hashes, timing and memory values.

## Compatibility boundaries

Modern Contacts exposes normalized nonoptional name strings. The old Objective-C loop could add accidental extra name forms when an absent AB property returned a zero-valued `NSRange` through messaging `nil`. Those extra forms are intentionally omitted; the actual phone/SIP destination remains available. Explicit empty-name and raw nil-name native probes document this distinction. Universal raw-AB-record parity is not claimed.

Completion display names use given/family or organisation and [the public Contacts name-order API](https://developer.apple.com/documentation/contacts/cncontactformatter/nameorder%28for%3A%29); history retains its existing full-name formatter. Modern per-contact name order can differ from the old global AddressBook name order. Built-in phone/SIP labels keep Telephone's existing label table; custom labels retain the adapter's localized fallback. Synthetic name-order and label checks do not establish actual user locale/profile acceptance.

The snapshot preserves the order supplied by Contacts enumeration. The synthetic comparison supplies identical input order to both engines; it does not establish that CNContactStore enumeration order equals the old AddressBook search order. First-record selection follows the current snapshot's order.

Incoming caller lookup in `AccountController` still uses AddressBook and is outside this dialler-completion change. This issue does not remove every AddressBook path from the application.

## Final validation

The final focused native run passed **60 cases, zero failures**: 19 dialler completion/token/keyboard cases, six transfer regressions, 12 publication/access/race cases, 18 Contacts recovery cases and five detached CNContact mapping cases. Actual completion-window keyboard dispatch selected row 1, committed destination `200` with per-token index 1, and delivered one Call action.

Earlier failures exposed fixture contracts: the keyboard harness had addressed arrow events to the inactive editor, and the existing transfer account fixture lacked the new optional provider getter. The corrected fixtures retain their original destination/transfer assertions. Diagnostics and failed logs remain part of the record.

Fresh local validation passed **1,014 suite cases, zero failures**: Domain 28 XCTest, UseCases 206 XCTest + 157 Swift Testing, ReceiptValidation five XCTest, and the isolated Telephone host 570 XCTest + 48 Swift Testing. The 60 focused cases overlap those suites. The separate synthetic recording ownership harness passed 105 assertions; repair and vendor/dependency gates passed. The unsigned Release build also passed. Runtime/test/project/benchmark input hashes remained unchanged throughout this final run.

The native host used a disposable unique identity with its startup nib removed. No app installation or release was performed. Final logs, exact source hashes and separate acceptance boundaries are recorded in the companion JSON. Prior failed builds/focus/full runs are retained as diagnostic history; they are not counted as current passes.

No actual Contacts store, owner profile, Keychain, permission grant or provider call was used by the synthetic measurements. Actual provider/hardware/grant/playback/sleep-wake/VoiceOver acceptance remains pending in [#62](https://github.com/jpskidmore/telephone-jps/issues/62). No installation or new release is included; 3.7/build 166 and all existing immutable releases/assets remain preserved.
