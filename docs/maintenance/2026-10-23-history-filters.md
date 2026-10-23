# Expanded history search and filters — 23 October 2026

Issue [#61](https://github.com/jpskidmore/telephone-jps/issues/61) is implemented and natively verified against baseline `610e133b3806105175a0a46340a51b34a5122b59` plus this commit. This completes the source feature; it is not an installed update or a release.

## Repairs found during native acceptance

- Preserve the requested history mode before loading the view, without touching the nil table outlet. The shared dialler can safely request compact history during construction.
- Insert individual account menu items directly rather than using the same-title-replacing popup convenience API. Distinct account UUIDs and the All accounts entry survive duplicate titles. Equal names have a deterministic key tie-break.
- Handle the native Search action so its clear button refreshes visible rows. Clearing text retains the selected call identity and the active account/type filters.
- Update the existing capped-history test to find its table independently of the expanded keyboard entry point, which is now Search. Its original identity/Return assertions remain intact.

## Fresh verification

Local Xcode 27.1, Swift 6.4, arm64, macOS 27.0.1; supported deployment target remains macOS 15.6.

- App and TelephoneTests build-for-testing succeeded.
- Complete isolated Telephone suite: **289 XCTest cases + 48 Swift Testing cases, zero failures**. The host uses a unique bundle identity and no production startup nib; individual native controller tests still load their real nib resources.
- Standalone production-controller AppKit harness: **68 component assertions passed**, separate from the XCTest total. It uses the actual controller/presentation sources and an inert dispatch boundary, with synthetic data and programmatic native view construction.
- Before/after evidence: baseline controller crashes on pre-view collapse and fails the duplicate-account test. The source before the Search action fix fails the native cancel-button regression; corrected source passes.
- Inspected native controller captures in Light/Dark at 368 and 520 points. Native layout, focus-chain, combined-filter, selection, Call/Copy/Delete identity and compact-history regressions pass. These are isolated acceptance checks, not proficient VoiceOver or live calling evidence.
- Dependency manifests verified: seven source files, 24 static archives and 21 linked libraries. No cloud workflow was dispatched.

The first hosted run exposed one stale test assumption (expanded keyView cast to table); its corrected rerun passed. A later complete rerun passed after adding the native Search clear fix. Earlier failing logs remain diagnostic evidence, not final passes.

## Reproduction and evidence

Run `Scripts/run-history-filter-tests.sh` on macOS for the bounded component checks. `JPS_HISTORY_FILTER_TEST_DIR` retains build products and `JPS_HISTORY_FILTER_CONTROLLER_SOURCE` permits an untouched historical controller for red/green reproduction.

Follow `docs/VALIDATION.md` to build TelephoneTests and use `Scripts/prepare-isolated-test-host.py` before running the hosted suite. Do not launch the normal app host as a test workaround.

Local final evidence:

- `/private/tmp/jps-history-final-build-20261023.log`
- `/private/tmp/jps-history-telephone-tests-final-20261023.log`
- `/private/tmp/jps-history-telephone-tests-final-20261023.xcresult` (includes four native image attachments)
- `/private/tmp/jps-history-native-final-snapshots`
- `work/history-filter/final-native-cancel.log` (untracked scratch evidence)

Source and log SHA-256 values are in the adjacent JSON record. Other unchanged framework suites were not rerun. No real provider/audio/device/grant/VoiceOver acceptance, packaging, installation or release is claimed. The next ranked roadmap item is the practical acceptance matrix #62.

Apple API references checked during this repair: [isViewLoaded](https://developer.apple.com/documentation/appkit/nsviewcontroller/isviewloaded), [popup addItem(withTitle:)](https://developer.apple.com/documentation/appkit/nspopupbutton/additem(withtitle:)), and native AppKit Search/cancel behaviour confirmed by an executable probe.
