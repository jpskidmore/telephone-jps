# Validation and release checks

## Current source-cleanup status

The October 2026 changes are an **unreleased source update**. Application metadata
remains version 2.0.3, build 154. No new binary, signature, release ZIP or deployment
was produced as part of this cleanup.

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
