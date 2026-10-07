# Validation and release checks

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
