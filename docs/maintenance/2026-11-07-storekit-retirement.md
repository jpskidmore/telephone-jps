> **Later native evidence — 7 November 2026:** corrected source now passes 929 native cases and unsigned arm64 Release. See [native repairs, results and limits](2026-11-07-storekit-native-validation.md). The source-only statements below describe the earlier connector audit; #71 remains open.

# Issue #71 — Purchase/receipt retirement, source checkpoint (7 November 2026)

This record is for the owner-selected **Option B**: this GPL fork has **no in-app purchase, subscription or receipt gates**. If a commercial distribution is considered later, the previously discussed single up-front sale is not authorised by this change. The original release baseline is immutable [3.8.2/build 169](https://github.com/jpskidmore/telephone-jps/releases/tag/v3.8.2).

## Changes published on main

- [8b92e7e](https://github.com/jpskidmore/telephone-jps/commit/8b92e7e778cba06f1ddb5f66e8e1ac56a32f6378): remove receipt checks from SIP startup and history presentation. User-agent start remains asynchronous and sets the existing 30-call capacity.
- [343bf98](https://github.com/jpskidmore/telephone-jps/commit/343bf9864d3116dfc4d28f2b1f59ff7e8da632a0), [6958693](https://github.com/jpskidmore/telephone-jps/commit/6958693a23094d7c259f9550cbbbd406553d10d4): detach StoreKit object creation, payment observers and receipt/purchase dependencies from app composition.
- [05ff925](https://github.com/jpskidmore/telephone-jps/commit/05ff9253de4d9fb444c6ae9d1b53b274d2d83b96), [03f2068](https://github.com/jpskidmore/telephone-jps/commit/03f20680c22450535f2a636379437a857907da25): replace the purchase view with native Local Build Information and bundle the GPLv3 licence with retained Credits; correct the Xcode licence-object identifier.
- [d923257](https://github.com/jpskidmore/telephone-jps/commit/d923257c094251ed3a5400e280b320eaf2fb93e3): remove the old history purchase/restore callbacks; preserve day-change and current-generation history refreshes.
- [60c5ded](https://github.com/jpskidmore/telephone-jps/commit/60c5dedd01a98e383f268776771168d8da09b57e): remove StoreKit linkage, receipt-validation XPC service and test target, retired purchase/receipt source and Xcode object references, and update validation, signing and release scripts. 163 obsolete files/schemes deleted in this commit.
- [118d9b4](https://github.com/jpskidmore/telephone-jps/commit/118d9b4c56b4d4c9d3fc95d35e7dd09670505eea): give the retained information window and menu action purchase-free names.
- [b5bb2a2](https://github.com/jpskidmore/telephone-jps/commit/b5bb2a2646204a988574dcacc8a57bf94e9caf25): remove a final compiled product-presentation type and disable the in-app-purchase Xcode capability.

All changes are source commits with `[skip ci]`, on main. No CI/cloud build was deliberately dispatched. No production SIP/Keychain, installed app, prior release tag, prior release asset, visibility setting or Cloudflare resource was changed.

## What the static checks establish

- The Xcode project defines eight native targets: app, Domain, DomainTests, DomainTestDoubles, UseCases, UseCasesTests, UseCasesTestDoubles and TelephoneTests. The only XCTest bundles left are DomainTests, UseCasesTests and TelephoneTests.
- The project has no live StoreKit link, ReceiptValidation XPC/embed, purchasing code source phase or in-app-purchase capability. Post-cleanup GitHub read-back checked **503 distinct compiled-source filenames, zero missing**, and verified the required local information and bundled licence resources. Structural Xcode project checks found no newly dangling object identifiers. The project object graph, retention of Local Build Information resources and source-path inventory were inspected.
- The active app composition does not construct StoreKit or receipt validators; 30-call engine capacity and full call history no longer depend on a receipt, and history's generation/day-change handling remains.
- Local Build Information uses native controls showing bundle version/build, provenance and licence, with Source, bundled GPL licence and Credits actions. The old purchase UI is removed. Unit-test source covers metadata, visible actions, status text and 30-call startup configuration.
- `Scripts/verify-local-edition.py` is a portable **source-only** regression guard, called by both native validation/build entrypoints. It does not compile or test the macOS program.

**Evidence boundary:** static inspection and project-reference checks only. There has been **no fresh native macOS Xcode type-check, XCTest run, Release compilation, ad-hoc signing, packaged-file parity, installed Light/Dark inspection, live SIP/account/device test or VoiceOver acceptance** for this candidate. Historical 3.8.2 tests do not certify these changes.

## 7 November continuation — reference scan and test hardening

- [`2b852c1`](https://github.com/jpskidmore/telephone-jps/commit/2b852c13ac3b8c68e871b41d9e84a2489d359240): the portable source gate now searches the eight relevant source directories instead of all vendor/build/archive folders; it also checks production source lines for retired purchasing and receipt type references and verifies uniqueness of the project's 24-character object IDs. Both macOS validation and candidate-build scripts now run `plutil -lint Telephone.xcodeproj/project.pbxproj` and `xcodebuild -list -project Telephone.xcodeproj` before compiling.
- A separate connector-based read-back fetched **all 386 currently tracked production .swift/.m/.h/.c/.mm/.cpp files** under `Telephone/`, `UseCases/` and `Domain/` in sequential 16-file batches. A token search for 14 retired payment/receipt type names, ignoring comment-only lines, returned **zero matches and zero fetch failures**. This is source-reference evidence only; an Apple SDK type-check may still detect other defects.
- The exact `Scripts/verify-local-edition.py` content from GitHub (blob SHA `11779682c188d05764e4e1d8b199058895f2bd44`) was reproduced byte-for-byte in an isolated Linux scratch directory; `git hash-object` matched the GitHub blob SHA and `python -m py_compile` **PASSED**. This proves Python syntax only: the full source gate has **not been executed against a full local checkout**, nor has an Xcode project been parsed by macOS `plutil`.
- [`73c3ef9`](https://github.com/jpskidmore/telephone-jps/commit/73c3ef987bd99018e2f23fd169c909d371a1ef41) expands `LocalBuildInformationViewControllerTests.swift` to four XCTest methods, including a bundled GPL licence and Credits lookup and connected three-button target/action checks. These XCTest cases are **not run**; passing status must be recorded only after native execution.

## Next required macOS execution gate

On a clean Apple silicon Mac with supported macOS/Xcode, checkout the exact current main revision, confirm no personal data/defaults are used, then run:

```sh
python3 Scripts/verify-local-edition.py
./Scripts/run-macos-validation.sh
```

The native entrypoint runs portable dependency/recording checks, the Domain and UseCasesTests XCTest schemes, isolated TelephoneTests and an unsigned arm64 Release build. Preserve exact output and failures, and add a dated issue comment with the tested commit, commands and results. Inspect Local Build Information in both Light and Dark mode; verify the bundled GPL licence and Credits open and no purchase or restore controls appear. Any separately chosen signed release should use `Scripts/sign-adhoc-release.sh` and `Scripts/verify-adhoc-release.sh`, with package parity verified before publication.

**Do not close issue #71 or publish/install a new version on this source-only evidence.** Issue #62 remains intentionally closed without a completed 24-scenario practical matrix by the owner's earlier decision. Acceptance requiring real provider/hardware/permissions/VoiceOver is not silently passed by synthetic testing.
