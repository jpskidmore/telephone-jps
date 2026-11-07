> **Subsequent acceptance review — 7 November 2026:** the saved native results and artifact hashes were rechecked with no runtime source changes. #71 is completed; see the [acceptance mapping and unchanged delivery boundaries](2026-11-07-storekit-acceptance.md). The OPEN status below records the earlier run checkpoint.

# Issue #71 — fresh native validation, 7 November 2026

Option B now passes the local Apple silicon automated gate. **Issue #71 remains OPEN; no installation or release was performed.** This supersedes the earlier source-only status, while preserving its dated evidence.

## Exact candidate and environment

- Baseline main: `a35aa1b877f72fba1b55ca6852d339880f6a42b7`.
- Corrected source: [`a82611f`](https://github.com/jpskidmore/telephone-jps/commit/a82611fa8e5f33bcfe97dacfcc23f56e31fb9815), tree `40f4138812765df9116425efb0a4dcce20f246b9`. The locally staged tree matched the GitHub tree exactly before publication. Later evidence commits change documentation only.
- Mac mini arm64, macOS 27.2 (26B123), Xcode 27.2 (27B52), macOS SDK 27.2, Apple Swift 6.4.2.
- Fresh checkout on main; build products and result bundles in `/private/tmp/jps-telephone-validation.SlOFo3`.

## Substantiated repairs

Native compilation found obsolete references missed by the previous static audit: `SettingsFake: PurchaseReminderSettings`, the deleted receipt bridging-header import, `RecordCountingPurchaseCheckUseCaseOutput`, and two test initializer arguments named `purchaseCheck`. The compiled legacy account view also retained the removed purchase-check factory, store presenter and nib action. These references are removed; history target creation now goes directly through the retained async factory. The footer stays hidden, and history/day-change/generation/recording behaviour remains covered by the existing suites. No changes were made to credentials, capacity, routing or live data.

Both edited shell entrypoints had lost executable mode (`100644`); they now retain `100755`. The native entrypoint comment accurately distinguishes disposable-host ad-hoc signing from release signing. The release packaging script was syntax-checked, **not executed**.

The source guard now covers tests, test doubles, headers and nibs as well as production code. In a separate scratch copy, each of six old defective files was restored individually: all six were rejected, and the corrected fixture passed. A native integration test also checks that the renamed information-window nib loads with the information view controller and expected title.

## Final completed run

```sh
python3 Scripts/verify-local-edition.py
./Scripts/run-macos-validation.sh
```

The final unmodified script completed with **exit 0**, including its unsigned arm64 Release build.

| Suite | XCTest | Swift Testing | Failures / skips |
| --- | ---: | ---: | ---: |
| Domain | 28 | 0 | 0 / 0 |
| UseCasesTests | 192 | 123 | 0 / 0 |
| Isolated TelephoneTests | 538 | 48 | 0 / 0 |
| Total | 758 | 171 | 0 / 0 |

**929 suite cases passed.** Counts were independently read from the three `.xcresult` summaries (28, 315, 586). All five Local Build Information tests passed. Reduced counts relative to historical 3.8.2 reflect retired purchase/receipt tests; historical test totals are not reused to certify this source.

Separate checks: 503-source-name gate; macOS `plutil` project parsing and `xcodebuild -list`; all 50 baseline repair entries; seven dependency source files, 24 static archives and 21 linked libraries; **105 recording ownership assertions**; 11 audio source-wiring checks; six recording lifecycle model/wiring checks. These are not added to the 929 native suite cases. Shell syntax and `git diff --check` passed.

The disposable Debug test host had bundle ID `uk.jpsit.telephone.tests.a5bb10d4fbc6499db2ed45a9f13032a3` and no `NSMainNibFile`; the original built app retained `uk.jpsit.telephone` and `MainMenu`. Tests did not use the owner's production startup/profile or actual Keychain, Contacts, SIP accounts, history or recordings. Only the disposable Debug test host was explicitly ad-hoc signed.

## Information and built-product inspection

A standalone scratch app compiled the original information-view source with synthetic version/copyright metadata and a separate bundle identity. Native Light and Dark screenshots were inspected: text and the Source/GPL Licence/Credits buttons were readable, with no purchase/restore controls. This was a component preview, not an installed production-app launch. Copies of the built Debug app's exact GPL and Credits resources were put into that disposable preview; clicking its original GPL Licence and Credits actions opened the expected documents in TextEdit. No owner document was edited. A first offscreen bitmap attempt produced blank images and is not accepted as visual evidence.

The real renamed window nib loaded successfully in the isolated native test. Release inspection independently confirmed arm64, no StoreKit dynamic linkage and no `.xpc` bundles. `LICENSE` (35,142 bytes) and `Credits.rtf` (66,141 bytes) in the Release app matched their source bytes and SHA-256 hashes. The source version/build remains 3.8.2/169; this scratch binary is **not** the immutable published 3.8.2 asset.

## Diagnostic history and limits

Earlier logs retain the missing-protocol, missing-header and extra-argument build failures. One otherwise passing 928-case run stopped before Release because a script-comment edit during execution shifted the shell's input position; this was an agent execution error, not a remaining script syntax defect. The final fresh run includes the added window-nib test and completes all commands with 929 passes and Release success. Xcode reported a non-fatal outdated iOS simulator service and system shortcut-service diagnostics; no simulator or OS setting was changed.

No normal production-profile startup, installed application, real provider/hardware/permissions, VoiceOver, release signing, packaging, installation or publication is claimed. #62 remains closed not planned; its practical matrix is not passed or reopened. No cloud workflow was dispatched and Cloudflare was untouched. #71 is left open in this continuation with the native evidence now available; no additional release authority is inferred.

The [machine-readable record](2026-11-07-storekit-native-validation.json) contains source/tree IDs, commands, exact counts, paths and SHA-256 hashes of the full local and diagnostic logs. Raw logs and `.xcresult` bundles remain local; the record is not a remote copy of those artifacts. The earlier [source-only record](2026-11-07-storekit-retirement.md) remains historical. Apple's [Xcode test-result documentation](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results) was consulted for the native validation boundary.
