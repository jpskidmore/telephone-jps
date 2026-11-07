# Issue #71 — Option B native acceptance complete, 7 November 2026

The required local implementation and native validation gates are satisfied for source `a82611fa8e5f33bcfe97dacfcc23f56e31fb9815` (tree `40f4138812765df9116425efb0a4dcce20f246b9`). Issue #71 can be closed as completed under its recorded Option B decision and maintenance execution order. No new application code or tests were changed in this final acceptance review.

## Evidence rechecked

Main at review was `8ef3bd28212df9f7c3a645e61ac8429311a951f3`; all changes since the tested source are under `docs/`. The full local and diagnostic log sizes/SHA-256 values were recomputed and matched the committed [native evidence record](2026-11-07-storekit-native-validation.json). Fresh reads of the existing native `.xcresult` bundles confirmed Domain 28, UseCasesTests 315 and isolated TelephoneTests 586 cases: **929 passed, zero failures and zero skips**. This rechecks the completed run; it does not claim another full test execution.

The final log records successful unsigned arm64 Release compilation and successful execution of the 30-call startup, bundled licence/Credits, purchase-free information view and actual renamed-window-nib regressions. The Release binary hash and both bundled document hashes match the native record. `otool -L` was additionally checked on the application, Domain and UseCases framework binaries: no StoreKit linkage. No `.xpc` bundle exists in the Release app. The prior native run also passed dependency checks and 105 separate recording ownership assertions; source/model checks remain separately counted.

## Acceptance decision

| Required Option B property | Evidence and outcome |
| --- | --- |
| Full history and 30-call capacity without a purchase/Apple account | Receipt/purchase gate removed from the actual history factories; complete native history/reload/generation suites passed; `testLocalEditionStartsWithThirtyCallCapacityWithoutPurchaseCheck` passed with a synthetic agent. No actual calls or accounts used. |
| No payment observer, purchase, restoration or receipt infrastructure in the maintained composition | Full-tree source guard passes; native app/frameworks compile; no StoreKit linkage or receipt XPC product in the built Release application. |
| Discoverable version/build, provenance, GPL and Credits | Menu action wiring retained; all five information tests passed, including the real window nib. Native Light/Dark component previews were inspected, and GPL/Credits actions opened copied built resources in TextEdit. |
| Native regression and Release gates | 929 native suite cases, dependency/recording gates and unsigned arm64 Release passed on the documented Apple silicon Mac/Xcode toolchain. |
| Retained non-local StoreKit purchase path | Not applicable: Option B removes this path. The earlier Option A StoreKit test failure is historical. No StoreKit purchase test or real Apple account is required to retire the path. |
| Performance claims | None. This change is validated code simplification; no startup, CPU, memory, battery or network improvement is claimed. |

## Backlog and delivery boundary

With #71 completed, the original 19-item roadmap is **18 implemented, one closed not planned (#62)**. #62's incomplete actual provider/hardware/permission/VoiceOver matrix remains unverified and is not reopened. Additional #76/#77 fixes remain closed. The roadmap issue itself remains closed; only its current status is refreshed.

There is no remaining implementation or native-validation blocker for #71. This does not certify a signed distribution, normal production-profile launch, installation, actual Keychain/provider/Contacts/hardware/permission/VoiceOver acceptance or a new release. Published 3.8.2/build 169, all release tags/assets, visibility, Cloudflare and live user data remain untouched. No cloud workflow is dispatched. Any later release remains a separate task with its own exact-build/signing/package/download checks.

Read the [complete run and diagnostic history](2026-11-07-storekit-native-validation.md) for commands, counts, platform, synthetic isolation and limitations. The earlier native-run JSON intentionally records `issue71State: OPEN`, which was true when that evidence was captured; this acceptance review records the subsequent completion decision without rewriting that historical snapshot.
