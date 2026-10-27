# Validation and release checks

## Current 3.7 release — 27 October 2026

Public [GitHub Latest v3.7](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.7), build 166, is verified from exact source/tag `58956a9906cbe1221640a926446341e6a71fdcb9`. Fresh local suites passed **920 cases**, zero failures: Domain 28 XCTest; UseCases 206 XCTest + 147 Swift Testing; ReceiptValidation 5 XCTest; isolated Telephone 486 XCTest + 48 Swift Testing. Separate component assertions are not added to this total.

All seven downloaded assets match local sizes/SHA-256; app/source parity covers 57 regular app files, six symlinks and 1,510 Git blobs. Ad-hoc signatures, arm64, entitlements and ZIP extraction checks passed. An actual Release recovery controller received narrow idle Light/Dark inspection in a unique-identity nib-free copy with synthetic data/inert actions; no real AppController/profile was started. No local installation was performed. Previous releases/assets/tags and public visibility were preserved.

Read [3.7 publication proof](releases/3.7-verification.md) and [full asset/hash proof](releases/3.7-verification.json). #62 actual provider/hardware/grants/playback/installed quit-reopen/VoiceOver checks remain pending. Historical validation below describes its original release, not this candidate.

## 3.6.1 centred dialler hotfix — 21 October 2026

Fresh 694-case local validation, separate components, independent Light/Dark
visual review and installed/downloaded package/source parity passed. Issue #72 Fix A
removes the permanent route line while retaining Call help and conditional
Waiting control. Read [delivery proof](releases/3.6.1-verification.md) and
[fresh results](releases/3.6.1-tests.json). The repository remains public by owner
choice; visibility settings are left alone. Actual provider/audio/grant and
proficient VoiceOver acceptance remain separate.

## 3.6 interim roadmap release — 21 October 2026

Fresh serial local validation passed **694 cases, zero failures or skips**:
Domain 28 XCTest; UseCases 201 XCTest plus 131 Swift Testing; ReceiptValidation
5 XCTest; isolated Telephone 281 XCTest plus 48 Swift Testing. Fresh vendor,
audio, recording ownership/recovery, Foundation and additional routing/SIP/
history/CoreAudio checks are separate from that suite total.

The exact signed candidate is installed and privately published from immutable
source `7abcede59ff282f9c0dd042e66cb8283ffb66085`. Every app file/symlink,
source Git blob and all seven uploaded/downloaded asset hashes match. Previous
releases/tags/assets remain unchanged. Read [delivery proof](releases/3.6-verification.md)
and [fresh results](releases/3.6-tests.json). Actual provider/audio/device/grant,
full visual and proficient VoiceOver acceptance remain separate. Issues #61–71
are deferred; no further roadmap implementation is part of this release.

## 3.5.1 Guided routes crash repair — 8 October 2026

Fresh serial local validation passed **665 test cases, zero failures**: Domain
28 XCTest; UseCases 201 XCTest + 131 Swift Testing; ReceiptValidation 5 XCTest;
isolated Telephone 252 XCTest + 48 Swift Testing. The generated More-menu
regression preserves real AppKit dispatch while observing the actual target,
requiring explicit delegate delivery once, the original sender and no fallback
when the delegate is absent. Inactive-host window-focus fixtures failed and
remain diagnostics; no runtime collision reproduction is claimed for them.
The owner's 3.5 crash reports supply the observed stack-overflow evidence.

The uniquely identified nib-free Debug host avoids production startup/profile
access. Tests/build products remain under `/private/tmp`. Current source hashes,
case counts and final log digests are in [test proof](releases/3.5.1-tests.json).
All 1,088 other source/test/script inputs match the previously tested 3.5
snapshot. Its separate 170 routing cases and component checks remain historical
unchanged-source evidence and were not rerun. Fresh dependency inventory and
the 50-entry baseline repair gate passed. No routing/data/layout change is made.

Release packaging, installation and private Latest publication are complete.
The owner reported “tested - looks good” after normal-launch Keychain handoff;
read [completion proof](releases/3.5.1-verification.md).
Ad-hoc signing and controlled tests do not establish live SIP/audio, emergency
calling, sandbox grants or proficient VoiceOver acceptance.

## 3.5 Guided routes local validation — 8 October 2026

The complete current four-bundle run passed **664 test cases, zero failures**:
Domain 28 XCTest; UseCases 201 XCTest + 131 Swift Testing; ReceiptValidation 5
XCTest; isolated Telephone 251 XCTest + 48 Swift Testing. This includes the final
Unavailable status and collapsed/expanded width-retention corrections.

The production Foundation dial-plan harness separately passed **170 cases, zero
failures**, including country/area expansion, longest-prefix precedence,
category/default interaction, blocks, emergency isolation, stale/deleted account
rejection, service literals, malformed URI rejection and legacy link aliases.
Strict Swift 6 concurrency and Objective-C bridge export passed.

Actual native hosted tests verify the single editable offline dial field, one
history table, 368 × 104 minimum content (368 × 268 expanded), fixed 592 × 337
Settings outer bounds, route/exception save/discard/cancel behaviour, bounded
prefix sheet, provider-owned immutable pending requests and current-plan
callbacks. Rendered native Numbers/Routes/Exceptions/Test panes and the main
Dial bar were checked in Light and Dark. They use synthetic data and a uniquely
identified nib-free Debug host; the production MainMenu metadata is retained.

Separate current checks passed: 18 URI assertions across eight native corpus
cases (including explicit TCP preservation), 32 fresh-source SIP lifecycle and
11 callback assertions; 25 Foundation checks; 309 audio-gate and 18 patched
CoreAudio UID assertions; history file preservation/retry/clear, 12 reachability,
4 DNS and nullable-import checks; real synthetic WAV/MP3/Ogg recovery/export;
11 audio wiring and 6 recording model cases. Dependency inventory passed for
7 manifest files, 24 archives and 21 linked libraries; all 50 recorded baseline
repair entries still pass their gate. These component/assertion counts are
separate from the four-bundle test-case total.

Build products and executable fixtures stay under `/private/tmp`; durable logs,
source/object hashes and ten native UI snapshots are under local
`outputs/v3.5`. Framework runs and hosted test-manager runs are serial. The URI
transport reproduction initially failed and then passed after preserving the
native parser's explicit transport; prior failures are diagnostic history.

Release compilation, nested signatures, ZIP/source parity, installation and
private Latest publication completed. All seven uploads match local sizes and
SHA-256 digests; see [3.5 proof](releases/3.5-verification.md). Live provider
routing/negotiation, physical audio/hotplug, actual capture, sandbox grants and
proficient VoiceOver remain manual acceptance boundaries. No emergency call is
placed by a test. Offline classification is not a tariff or live allocation
lookup; consult [numbering metadata](DIAL_PLAN_NUMBERING.md).

## Historical 3.0 verified repair gate and local release policy

The repository is private. All 50 baseline issues #2–51 are recorded
**fixed_verified** in [repair-progress.json](audit-2.1.8/repair-progress.json), with
source fixes at `01ae5734bfd933c9048f00ef4c3ebe035fabeb0b` and issue #39's earlier
`a7cd664` fix. Controlled local validation passed 617 automated cases, zero
failures; all 50 issue records are documented and closed. The baseline repair
gate has passed. Read [the handover](BUG_FIX_HANDOVER.md) and root
[AGENTS.md](../AGENTS.md) before continuing.

**3.0/build 161** completed local Release compilation, ad-hoc signing, packaging
and installation at `/Applications/jps Telephone.app`, then was published as
[GitHub Latest](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.0)
from `6363412d56e2bc142a54058321b7873a69068c62`. The
[release verification record](releases/3.0-verification.md) and
[JSON proof](releases/3.0-verification.json) record the completed checks and seven
uploaded asset size/SHA-256 matches. Use main, `[skip ci]` pushed commits and no
cloud workflow dispatch. Preserve both v2.1.8 and v3.0 tags/assets and the user's
data. The v3.0 tag/source ZIP retain their preparation-time documentation;
publication is recorded on later main without rewriting that snapshot.

`build-test-release.sh`, `run-macos-validation.sh` and
`run-isolated-audio-validation.sh` include Release builds; the former closed
repair gate no longer blocks their local use. Keep hosted tests isolated and
retain exact build/signature/extraction/install/download evidence. Ad-hoc signing
of a modified isolated Debug host serves test isolation; final candidate signing
has its own documented checks. Normal TelephoneTests startup can load real
accounts/defaults, so follow the nib-free unique-identity host guidance.

Historical sections below describe earlier releases. Their earlier passes do
not certify changed code or replace the current 3.5 evidence above.

## 3.0 repair validation and completed publication

The 3.0 repair fixes the finite 50-issue baseline. All four native suites passed
locally on 8 October 2026: **617 automated test cases, zero failures**. This records
controlled regression evidence; it does not certify every possible defect or
live SIP/audio. Separate completed Release checks verify the signed app,
extracted ZIP and installed copy, all 59 installed app payloads, all 1,400 source
ZIP payloads against the release commit, and the size/SHA-256 match of every
uploaded asset. Release ID `406277128` is published, non-draft, non-prerelease
and Latest; the [publication proof](releases/3.0-verification.md) records it.
The authoritative per-issue state is
[repair-progress.json](audit-2.1.8/repair-progress.json); the
[50-issue verification map](REPAIR_VERIFICATION.md) links each repair to its
named regression boundary.

Keep the accepted compact interface: Icon rail Settings with Titled sections,
one Accounts-sized window, Dial bar with one recent call, Pocket call cards,
native close controls, UK English, Light/Dark appearance, green Online and red
Offline. Repairs must not expand the layout or remove calling functions.

Confirmed local development evidence includes:

| Boundary | Result | What the count means |
|---|---|---|
| Complete UseCasesTests development run | 195 XCTest tests and 124 Swift Testing tests in 22 suites, zero failures | Test cases; includes concurrently implemented repairs from several components |
| Complete TelephoneTests isolated local run | 217 XCTest tests and 48 Swift Testing tests in 9 suites, zero failures | Actual compiled hosted suite with a synthetic nib-free app identity |
| Complete Domain local run | 28 XCTest tests, zero failures | Test cases from the full current suite |
| Complete ReceiptValidationTests local run | 5 XCTest tests, zero failures | Test cases from the full current suite |
| Production audio gate with inert backend | 309 checks passed | Assertions in one native harness, not 309 XCTest tests or physical opens |
| Foundation production-component harness | 25 checks passed | Assertions with synthetic timer/playback/settings objects |
| Exact patched CoreAudio UID driver source | 18 assertions passed | Synthetic physical UIDs, no hardware query or SDK startup |
| Resource cleanup | 12 reachability cases and 4 DNS cases passed | Injected C-boundary creation/callback/schedule failures and success |
| History filesystem and activity lifecycle | Passed | Real scratch permission failures plus inert background-activity/DNS import boundaries |
| Recording export/recovery | Passed | Synthetic real WAV/MP3/Ogg encoding, forced export failure, durable reload, stereo integrity, cleanup and simulated scope-token lifetime |
| Native SIP lifecycle and callbacks | 32 lifecycle checks and 11 callback checks passed | Inert SDK boundaries; actual compiled production methods, not provider calls |
| Native/Swift URI round trip | 8 corpus cases and 15 assertions passed | Private parser/pools and synthetic addresses, no endpoint or transport |
| App quit ordering | 4 focused hosted cases passed | Controlled recording/history/retry completions and intercepted termination replies |
| Network saves and hotplug remapping | 5 Network and 3 Hotplug focused hosted cases passed | Actual production transition/mapping/failure-gate boundaries with synthetic workers/settings |

The final Debug15 hosted run passed all 217 XCTest and 48 Swift Testing cases,
including Network saves, hotplug mapping/failure gate, latest-history presenter,
actual nib/keyboard/AX metadata, credential failure handling, call ownership and
callback guards. Domain passed 28 XCTest cases; UseCases passed 195 XCTest plus 124
Swift Testing cases; ReceiptValidation passed 5 XCTest cases. These sum to 617 test
cases, separately from the component assertions listed above.

Earlier hosted runs exposed geometry/ringback and native AX getter mismatches;
those corrections were rerun successfully. Keep earlier failures as diagnostic
history and bind final passes to the corrected revision. A test-launch timeout
before a case starts is not a pass. If macOS FileProvider stalls dyld or signing
under Documents, copy the isolated Debug host and its frameworks to a fresh local
`/private/tmp` directory, preserve production metadata, and run there serially.
Do not use the normal host or the user's account data as a workaround.

The local component entrypoints below do not create a Release candidate:

```sh
xcodebuild -project Telephone.xcodeproj -scheme UseCasesTests \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/v3-persistence-debug ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test
./Scripts/run-history-resource-tests.sh \
  build/v3-persistence-debug/Build/Products/Debug
./Scripts/run-audio-device-tests.sh
./Scripts/run-recording-tests.sh
./Scripts/run-foundation-regression-tests.sh
python3 Tests/run_coreaudio_identity.py --output build/native-uid-fixture
python3 Tests/test_audio_recovery_integration.py
python3 Tests/test_recording_lifecycle_model.py
python3 Scripts/verify-dependency-manifests.py
```

For native URI/lifecycle/callback reproduction, select the actual local Debug
products and retain their successful build log explicitly. This avoids depending
on a prior chat's output directory:

```sh
export JPS_DEBUG_DERIVED_DATA=$(mktemp -d /private/tmp/jps-telephone-debug.XXXXXX)
export JPS_DEBUG_BUILD_LOG="$JPS_DEBUG_DERIVED_DATA/build-for-testing.log"
xcodebuild -project Telephone.xcodeproj -scheme TelephoneTests \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$JPS_DEBUG_DERIVED_DATA" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO build-for-testing > "$JPS_DEBUG_BUILD_LOG" 2>&1
python3 Scripts/run-sip-uri-regression-tests.py /private/tmp/jps-uri-checks
python3 Scripts/run-sip-lifecycle-regression-tests.py /private/tmp/jps-lifecycle-checks
python3 Scripts/run-sip-callback-regression-tests.py /private/tmp/jps-callback-checks
./Scripts/run-history-resource-tests.sh \
  "$JPS_DEBUG_DERIVED_DATA/Build/Products/Debug"
```

`JPS_DEBUG_DERIVED_DATA` selects matching object/framework/derived-header products.
`JPS_DEBUG_BUILD_LOG` must contain their successful Debug application's clang link
command, including `Telephone.debug.dylib`; the lifecycle runner uses it for the
matching link flags. `build-for-testing` above compiles but does not launch the
ordinary app. Use the separately isolated nib-free host for the hosted suite.
Component runners use scratch outputs and write source/object/command provenance;
`JPS_RESOURCE_TEST_DIR` optionally selects the history/resource scratch directory.
Choose fresh output directories when preserving multiple runs.

The history/resource runner requires already-built Debug frameworks. SIP URI,
callback and lifecycle runners use current Debug objects; read their arguments
and saved provenance before rerunning. Source-wiring/model checks complement
native execution and do not substitute for it. Preserve command output, platform,
SDK/compiler versions, source/object hashes and `.xcresult` bundles with final
release evidence. See [dependency rebuild provenance](DEPENDENCY_BUILDS.md),
[audio recovery](AUDIO_RECOVERY.md) and [recording recovery](RECORDING_RECOVERY.md).

These repair/release gates completed for 3.0. For future authorised changes, run
the required suites on the exact revision, build and package locally, verify
nested signatures and the extracted ZIP, install the exact tested app and verify
source/documentation parity. Keep both historical v2.1.8 and v3.0 tags/assets.
Push to main with `[skip ci]`; upload the same locally validated bytes. No cloud
workflow is part of this project's build/release process.

Manual acceptance remains separate: real SIP registration and provider routing,
incoming/outgoing/hold/transfer/DTMF, actual audio devices and hotplug, sleep/wake,
real microphone permission and sandbox folder grants, recording recovery,
proficient VoiceOver speech/navigation, and visible Light/Dark/Reduce Transparency
composition. Record only scenarios actually exercised; passing synthetic tests
does not establish these outcomes or coverage of every supported macOS release.


## 2.1.8 titled Settings sections

Build and package locally from the exact main revision, preserving earlier
release artifacts. Inspect all four Settings panes and all Accounts tabs in
Light and Dark appearance. Every pane must retain the same 592 × 337-point outer
window and 592 × 305-point content area, native Close control and 44-point rail.
General, Sound and app-wide Network must align at the top and leading edge with
their selected native section headings, separators and consistent field columns.
Check containment, focus, outlets, actions and the Network save prompt; Accounts
keeps its existing controls and geometry.

Run the relevant native Settings geometry and lifecycle checks along with status
rendering and compact history regressions. Verify the normal arm64 Release,
UK English resources, nested signatures, extracted ZIP and source parity.
Record only executed checks in BUILD-VERIFICATION.md, including any limit on
visible inspection. Publication commits use `[skip ci]`; no cloud build is used.

## 2.1.7 availability colours

Build and package locally from the exact main revision, preserving the 2.1.6
artifacts. Check the actual rendered availability symbol in Light and Dark:
registered online uses system green, while offline uses system red. Keep
connecting/transient states distinct and retain the status labels and actions.
Check the existing compact geometry and history menu alongside the colour fix.
Property assignments alone do not establish that a rounded popup renders its
symbol in the requested colour.

Run focused controller/rendering checks and the relevant native tests, then
compile, sign and verify the production Release and extracted ZIP. Record only
executed checks in BUILD-VERIFICATION.md. Publication commits use `[skip ci]`;
no cloud build is used. The Settings layout remains unchanged pending selection
of a proposed alternative.

## 2.1.6 local interface refinements

Build this update locally using `Scripts/build-test-release.sh` from a clean
main checkout after Xcode's licence and first-launch setup have been completed
by the user. The script runs the native suites and standalone harnesses,
compiles the production application and nibs, signs nested code and verifies
the extracted distribution. The generated BUILD-VERIFICATION.md records the
checks that actually completed; these requirements are not a claim of a pass.
No cloud build is used for this update. Publication commits use `[skip ci]`
to prevent the existing push workflows from starting a remote build.

Settings regressions check one Accounts-derived window size, an unchanged full
window frame while navigating all four sections in Light and Dark, native Close,
field containment and the actual Connection tab/all-accounts Network scope.
Main-window inspection checks consistent control and recent-call alignment,
the Clear Call History… menu title, absence of a duplicate visibility menu
command and retention of the visible history button's actions.

The exact locally packaged app still needs interface inspection before upload.
Live calls, actual audio devices and VoiceOver remain separate acceptance checks.

## 2.1.5 compact interface candidate

The selected layouts are Icon rail Settings, Dial bar with one recent call, and
Pocket call cards. Hosted regressions load the actual pane and call nibs, check
compact geometry and native close behavior, and exercise compact/full history
without replacing its data or actions. The existing four-suite release pipeline
also covers audio and recording harnesses, Foundation checks, arm64 Release
compilation, ad-hoc signing and ZIP extraction/signature verification.

The current interface supports UK English only. Packaging rejects localization
directories other than the neutral Base resources and en-GB, and checks the
app/framework development languages. Hosted regressions cover UK date and
duration formatting and preservation of saved number-formatting preferences.
Settings geometry checks include each icon's actual visible bounds within the
44-point rail. Historical multilingual checks below describe previous releases.

Local window inspection caught a call backdrop above the caller and controls:
accessibility actions could still reach the covered buttons. Call regressions
therefore check physical hit routing from the entire window content view after
each view replacement, in addition to the individual pane geometry.

The candidate is built from an exact main commit. Its BUILD-VERIFICATION.md and
workflow logs record executed results. The exact packaged binary must then pass
local inspection of all panes, compact/full history and call presentation in
Light and Dark appearance before those same ZIP bytes are uploaded to the
prerelease. Live SIP/audio, VoiceOver and full macOS-version coverage remain
separate manual acceptance tests.

For 2.1.5, Xcode's local first-run setup was incomplete. Standalone source checks
used the command-line tools; full XCTest and packaging used the GitHub macOS
runner. No system setup or appearance preferences were changed.

## 2.1.4 Settings initialization and material composition

Actual local inspection of 2.1.3 found a blank Settings window. The AppKit
exception stack showed `NSTableView.setDataSource` synchronously selecting a row
and entering `displaySettingsController:animate:` before the detail view existed.
The previous component checks and four suites did not cover that startup path.

The corrected controller assembles the hierarchy before populating the table and
guards initial selection. A hosted regression loads the actual Preferences nib
and complete controller. An independent local native harness reproduces the old
exception and checks the corrected content hierarchy. The corrected compiled app
must also pass local General, Accounts, Sound and Network inspection before
release publication.

[Candidate run 37347314079](https://github.com/jpskidmore/telephone-jps/actions/runs/37347314079)
passed all four suites, the Settings lifecycle regression, Release compilation,
signing and ZIP round-trip verification for `989dacb82010b13732c617b8fc0223e70bf955a4`.
The compiled candidate opened all four real settings forms locally and passed
sidebar arrow navigation and close/reopen inspection. Further visual inspection
found that the ordinary white window background made the glass effect too subtle;
the material composition correction requires its own candidate build and local
inspection before publication.

Independent native checks of the material correction passed all four actual pane
nibs and safe-titlebar geometry, desktop-blending material/window configuration,
live Reduce Transparency adaptation and restored sidebar/field-editor focus.
Non-General pane behaviors were stubbed in those isolated harnesses to avoid
account/network writes. Twelve call-layout cases (one to four controls across
English, German and Russian) retained their geometry and a single shared window
backdrop. These component results do not prove the visible WindowServer
composition; the complete compiled app still requires visual inspection.

[Material candidate run 37351331672](https://github.com/jpskidmore/telephone-jps/actions/runs/37351331672)
passed all four suites, Release compilation, signing and ZIP round-trip checks for
`e0723260e14460859991e730bc40a982ebea884d`. Its compiled app opened all four settings
panes locally and passed sidebar keyboard navigation and Command-W close/reopen.
Visual inspection still found that the custom transparent title-bar treatment
did not show an obvious close affordance. The final correction restores a
standard macOS title bar while retaining the glass sidebar and window material.
The hosted lifecycle regression now checks the native close control and actual
close/reopen behavior. The replacement candidate must pass the same release
gates and local window inspection before publication.

[Titlebar candidate run 37357912823](https://github.com/jpskidmore/telephone-jps/actions/runs/37357912823)
passed all 519 tests across the four suites, including the native Close-button
and reopen regression, plus Release signing and ZIP verification for
`e4fd5792d908ada30bf9051ff19010698418e275`. User inspection confirmed the traffic
lights were present and the fields looked correct, but the title bar was too
transparent. The final refinement gives only the title bar a semantic opaque
window backing; the existing field and sidebar materials are preserved. It
follows the same candidate-build and local-interface publication gate.

The workflow now uploads an app/source candidate after all automatic gates pass.
Publication follows local interface acceptance. The tested candidate files can
be uploaded directly, or the explicit `publish_release` workflow can build a
separate candidate. Direct upload preserves the exact locally inspected bytes.
Archive extraction and signature verification are included in the packaging gate.

## 2.1.3 local test release

Version 2.1.3 (build 155) adds Liquid Glass and native call/settings presentation
changes plus bounded bug fixes. `Scripts/build-test-release.sh` requires the
dependency checks, native audio/recording harnesses, portable regressions, all
four XCTest suites, Release compilation, ad-hoc signing and bundle verification
before packaging. `.github/workflows/test-release.yml` publishes the result as a
GitHub prerelease from the exact main SHA. Its generated `BUILD-VERIFICATION.md`
and workflow logs record the actual execution; this paragraph describes the
required pipeline, not a test result.

The local 5 October environment has macOS 27.0.1 and the command-line tools but
no full Xcode installation. Native standalone harnesses run locally; Xcode builds
and XCTest use the standard GitHub arm64 macOS runner. User call/audio acceptance
and visual accessibility checks are separate from compilation and unit tests.
See [release notes](releases/2.1.3.md), [interface checks](LIQUID_GLASS.md) and
[bug review](BUG_REVIEW_2.1.3.md).

Release packaging uses Xcode deployment postprocessing with the `debugging`
strip style, preserving local/global runtime symbols while removing debug-map
paths. Swift and C source paths are mapped to the project root. These settings
apply only to the Release packaging command; Debug XCTest symbols remain intact.
The bundle check still rejects absolute local user paths. See Apple's
[build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference).

[Run 37333179439](https://github.com/jpskidmore/telephone-jps/actions/runs/37333179439)
passed all four test suites, Release compilation, signing and metadata checks
for `2103ae766cd4502cb29961ce524bc9cae12c19f1`, then stopped because debug-map
paths remained in the Swift executables. [Run 37334499180](https://github.com/jpskidmore/telephone-jps/actions/runs/37334499180)
then passed the complete gate for `a3ffaf358773d8d81cff2b53c42ddce0c7594211`,
including Release postprocessing and bundle path verification, and produced the
2.1.3 prerelease. The later local Settings startup failure demonstrates why a
successful automated build must also be inspected in the running application.

## Historical source-cleanup status before 2.1.3

The October 2026 changes are an **unreleased source update**. Application metadata
remains version 2.0.3, build 154. An unsigned Release build now passes the
additional audio-recovery CI below. No distribution signature, release ZIP,
installation or deployment was produced. The initial source-cleanup-only checks
are recorded separately from that later native validation.

Portable checks run on Linux can check hashes, inventories, source structure,
localization keys, shell syntax and the explicit recording-lifecycle model. They
cannot run Cocoa/PJSIP/AudioToolbox, XCTest, the native recording harness, macOS
sandbox scopes, or an application launch. They do not establish that a native
regression test has passed. Existing historical release notes are historical
claims; this cleanup neither reruns nor disproves earlier validation.

The recorded portable result for this cleanup is six passing recording-lifecycle
model tests. Dependency manifests passed for seven source files, 24 static archives
and 21 linked libraries; 47 localization tables parsed without duplicate or removed
keys. Shell scripts and documented shell examples parsed; both PJSIP patches
applied in dry-run to their bundled source. These are structural/model results.

## Audio-recovery validation

On 2 October 2026, [GitHub run 37037958671](https://github.com/jpskidmore/telephone-jps/actions/runs/37037958671)
passed 232 fake-backend production-controller checks, the synthetic recording
harness, an unsigned arm64 Release build, 11 wiring checks and six lifecycle-model
tests. Environment: macOS 15.7.9, Xcode 26.3, Swift 6.2.4, macOS SDK 26.2. This
replaced a local build attempt that stopped before transfer when its executor
disconnected. No hosted XCTest, app launch, signing or real-device testing ran.
See the [versioned validation record](validation/audio-recovery-2026-10-02.md).


The additional audio recovery has a separate safe native entry point,
`Scripts/run-isolated-audio-validation.sh`. It runs the production failure gate
against injected fake operations and the existing synthetic recording harness,
then compiles an unsigned app. It deliberately does not launch the hosted
TelephoneTests app. See [audio behavior and limitations](AUDIO_RECOVERY.md).
Native execution results for the exact candidate must be recorded before claiming
a successful build; source wiring checks alone are insufficient.

## Portable entry points

From the repository root:

```sh
python3 Scripts/verify-dependency-manifests.py
python3 Tests/test_recording_lifecycle_model.py
for script in Scripts/*.sh; do sh -n "$script"; done
```

The dependency check validates seven source-manifest files, the pinned inventory
of 24 prebuilt static archives, and resolution of all 21 linked libraries in the
current project. The Python lifecycle test is a model of ownership and shutdown
ordering, not execution of Objective-C or proof of macOS runtime behavior.

## Native test prerequisites

- Apple silicon Mac running macOS 15.6 or later, without Rosetta
- Full Xcode with a compatible macOS SDK and the intended command-line tools
  selected; complete Xcode's first-run setup yourself if necessary
- Python 3 and `rg` available on `PATH`
- A disposable macOS test account without real SIP credentials or call data:
  `TelephoneTests` is hosted in the application, and normal application startup
  is distinct from a purely isolated unit-test executable
- Space for build products and `.xcresult` bundles under `build/validation/`

Run:

```sh
./Scripts/run-macos-validation.sh
```

The runner stops on failure and performs, in order:

1. Dependency hashes/inventory, all archive arm64 checks, version markers,
   metadata-path checks, and parsed project entitlement checks
2. The ordinary, unsanitized `RecordingHardeningHarness` build and execution
3. Debug XCTest for `Domain`, `UseCasesTests`, `TelephoneTests`, and
   `ReceiptValidationTests`, covering the project's four test bundles
4. An unsigned Release build of the explicit `Telephone` application target

Each run uses a fresh `build/validation/run.*` directory. The test schemes are
checked in. The Release step uses the target directly, so it does not depend on
an Xcode-generated scheme. The shared `Telephone` scheme supports the README's
separate Release build command.

No native step was executed in the Linux cleanup environment. In particular,
unsigned test-host launch compatibility must still be established with the actual
Xcode/macOS combination. If local signing is required, review that failure and
configure an appropriate local development identity; do not disable project
security protections merely to make tests pass. The runner does not configure
credentials, entitlements, a signing identity, or SIP accounts.

The focused script has no sanitizer mode. Any sanitizer run must be configured
and recorded separately with its exact flags, platform and result. This describes
the checked-in entry point, not whether someone ran separate sanitizers historically.

## Recording regressions requiring native execution

Inspect the current native tests and run them before distributing a binary:

- Hold finalization for call A while call B starts and stops in the same window
- Complete overlapping recordings in either order, including the same destination
  folder; verify each session releases its own folder access exactly once
- Tear down controllers and calls while completion is deferred
- Finalize multiple queued conversions with both success and failure outcomes
- Quit while SIP is stopping and conversions are active; complete the main-queue
  recording callbacks before allowing termination
- Reject delayed SIP start/account-add requests during Quit and recheck SIP state
  after conversion completion (including starting/stopping transitions)
- Remove a failed-start output reservation before releasing custom-folder access
- Keep empty-queue termination responsive and preserve recording failure/recovery,
  stereo separation, output privacy, collision handling and WAV-readiness behavior

These are required validation outcomes, not a claim that each has been exercised
by this source-only cleanup. Do not use real calls or recordings without a separate
approved manual-test plan and any required consent.

## Binary release gates (separate from this source update)

Before publishing an application, preserve the exact commit, Xcode/SDK versions,
command output, `.xcresult` files and binary/source SHA-256 values. Review:

- Fresh-checkout unsigned build and all native tests
- Staged app launch and Quit behavior, recording conversions in all three formats,
  channel separation, folder access and failure recovery
- Ad-hoc distribution signatures/entitlements, if that is the intended distribution
- Final application/resource/source-package notices, including encoder notices
  in `Credits.rtf`, corresponding sources and PJSIP patches
- No private local paths or credentials in the release artifacts

For an explicitly authorized ad-hoc release only:

```sh
./Scripts/sign-adhoc-release.sh \
  "build/DerivedData/Build/Products/Release/jps Telephone.app"
./Scripts/verify-adhoc-release.sh \
  "build/DerivedData/Build/Products/Release/jps Telephone.app"
```

The verifier reads version/build from the application's Xcode target metadata,
rejects malformed or missing entitlement plists, and checks signatures and arm64
architecture. It is not a launch, notarization, codec-decoding, or legal-compliance
test. Ad-hoc-only library-validation behavior remains unchanged. A Developer ID
release needs a separate same-team signing workflow and must not use that exception.
