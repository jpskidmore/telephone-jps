# Synthetic legacy dialler completion CPU baseline

This is a local measurement tool for issue #70. It never opens a real AddressBook
or Contacts store, restores an account/profile, starts SIP, or creates an app UI.
It measures the production synchronous delegate bodies against a deterministic,
in-memory directory. Results are **not system AddressBook store, index or disk
latency** and cannot establish a real-world performance gain.

Run after a local native Debug validation has produced `UseCases.framework` and
`Domain.framework`:

```sh
Scripts/ContactsCompletionBenchmark/run.py \
  --products /absolute/path/to/DerivedData/Build/Products/Debug \
  --output work/contacts70-benchmark
```

The runner extracts immutable baseline source from commit
`83d691eaa9d7f348b895720c79c2637ae080d2e6` with `git show`. The completion,
token-commit, name and label method bodies are included verbatim; class declarations
and fixture dependencies are synthetic. `AKSIPURI`, URI and telephone formatters
use production implementations and the local pure UseCases framework. Only three
unused PJSIP imports in the standalone AKSIPURI copy are omitted, so PJSIP is not
linked or started. The manifest records original/extracted/generated source,
framework, executable and result hashes plus the compiler command.

Before fixture creation, `ABAddressBook.addressBook`, AddressBook/ABRecord/ABPerson
allocation, and CNContactStore allocation are replaced with fail-fast guards.
`sharedAddressBook` resolves only to the synthetic NSObject directory. Standard
NSUserDefaults resolves to an in-memory formatting-flags object. Guard probes
must each exit 70; native predicate qualification must pass all nine positive and
negative cases, including second SIP-labelled multivalue matching. Native
`ABSearchElement.matchesRecord` then evaluates detached NSObject records; no
`ABRecord` or `ABPerson` is initialised or allocated. The small shim supplies SDK
property types, dictionary values, name order and counted no-op API locks. An
unexpected directory selector or property type aborts. These private selector
aliases are a benchmark seam only and must never enter app code.

The benchmark runs sequential processes for 100/1,000/10,000 synthetic contacts on
the process main thread. It records one cold synthetic-directory construction,
first callback wall/CPU work, then two warm-up calls and five measured trials per
input. Nineteen completion queries include broad, selective, no-match, empty,
phone and SIP prefixes, multiword names in both orders, literal Unicode punctuation,
case changes and missing names. Seven token inputs cover name/phone forms, named
SIP, companies, raw SIP and no match. All completion results remain unbounded.

`baseline-N.json` records per-input and aggregate wall/CPU latency, predicate scan
wall time, result counts, process resident/physical memory and guard/lock counters.
`baseline-N-fixtures.json` preserves every ordered raw fixture value and label;
`baseline-N-outputs.json` preserves complete output arrays, every token destination
and the selected index for later candidate parity comparison. Memory after queries
includes all retained output snapshots, so it is not steady-state app memory.
The wrapper records warm token aggregate latency separately from per-input token
statistics that also include first calls.

Do not compare a candidate that truncates or deduplicates output with this
unbounded baseline. Require complete semantic parity and separately verify actual
native keyboard/Return, selected-token ownership, account/lifecycle invalidation
and permission recovery. Real provider/hardware/grant/VoiceOver acceptance remains
pending in issue #62.

## Current snapshot candidate

After the pure candidate files exist, compare them against the frozen baseline
outputs without rebuilding or changing the baseline:

```sh
Scripts/ContactsCompletionBenchmark/compare.py \
  --baseline work/contacts70-benchmark \
  --output work/contacts70-candidate
```

This compiles the actual `UseCases/Contact.swift` and
`UseCases/ContactCompletionSnapshot.swift` with a fixture adapter and Foundation.
It rejects direct Contacts/AddressBook store dependencies in the candidate value
sources and hashes them before and after compilation. Every completion array is
compared in full, including order, duplicate forms, capitalization and unbounded
large results. Token checks compare the returned contact and all ordered raw
phone/SIP destinations, display names and fixture labels against the legacy
output. The fixture's simple token forms are parsed by a small benchmark adapter;
production URI formatting, label bridging and selected-token ownership require
the separate native app tests.

Candidate timing covers `completionStrings` and `firstContact` separately, using
the same main-thread warm-ups, sample counts and autorelease-pool boundaries.
Token timing is **lookup only**; it excludes production formatter/URI construction
and must not be presented as a full token-callback speedup. Cold fixture conversion
and snapshot construction are separate measurements, not Contacts enumeration or
actor-publication latency. The candidate remains an O(n) scan, performs no result
truncation or cache eviction, and contains one immutable snapshot. It retains the
raw fixture and complete expected legacy output JSON while measuring, so absolute
process memory is not comparable with the baseline process or app steady state.
Use the reported before/after construction delta and describe that limit.

A passing parity run establishes only this synthetic corpus. The candidate still
needs native callback, keyboard/Return, per-token selected destination, lifecycle,
authorization and invalidation tests, a fresh full suite and local Release build.

The additional guarded rare-name probe retains an explicit boundary: old
ABRecord properties that are absent (`nil`) can add accidental name forms to
phone/SIP completions because an Objective-C nil message supplies an NSRange with
location zero. Modern Contacts exposes normalized empty strings. The candidate
intentionally uses normalized empty-name behaviour, preserving the actual
destination without those extra forms. Exact parity claims apply to the recorded
normalized synthetic corpus, including leading/trailing/repeated name whitespace,
not every raw ABRecord nil/empty combination. Native app regression tests should verify
the normalized empty-name behaviour separately.
