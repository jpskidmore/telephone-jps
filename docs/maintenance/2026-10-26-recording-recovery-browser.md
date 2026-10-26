# Recording recovery management — 26 October 2026

Issue [#68](https://github.com/jpskidmore/telephone-jps/issues/68) is source-verified against main baseline `e78bb51aa9752b19264f881cad56797f5502a905`. This completes the owner's next sequential item. The installed/released 3.6.1/build 165 and immutable release assets remain unchanged.

## Behaviour

**Recover Recordings…** now opens a dedicated native 650×460-point secondary window, preserving the existing Settings/dialler/call layouts. A selectable list identifies each eligible job by filename, creation date, retained raw size and state. Destination and last recorded error remain readable for the selected identity. Known error domain/code/description is retained; unknown failures are labelled without inventing a native diagnosis. Missing/damaged metadata retains safe orphan-track recovery. Raw size counts the two original tracks, excluding manifests, locks and encoded staging files.

Actions are **Retry**, **Save Elsewhere…**, **Reveal**, **Refresh** and **Discard…**. Save/cancel/confirmation use asynchronous native sheets; discard requires explicit per-job confirmation, with Cancel as the default keyboard choice. Progress is indeterminate. Per-job admission prevents duplicates while independent jobs can queue. Busy jobs hidden by exclusive ownership keep a cached presentation placeholder and remain reachable through the menu. Closing/reopening retires old panel choices while admitted operations continue; quitting closes new action admission and waits for cleanup.

[Light capture](images/2026-10-26-recovery-light.png) · [Dark capture](images/2026-10-26-recovery-dark.png). Both final native captures were inspected for readable pending/error state, selection, layout and button clipping. Native tests check accessibility properties and geometry; these do not replace proficient VoiceOver or installed save-panel acceptance.

## Asynchronous discovery and quit

A main-owned immutable index loads on a utility queue. Stable directory identity preserves selection across sorting and refresh; generations reject obsolete results. Read errors remain distinct from a genuinely empty/missing root and preserve the previous jobs. Menu validation reads only cached state, including pending managed entries; no validation starts a scan or builds the recovery window.

Startup refreshes asynchronously; export failures and explicit menu actions refresh the same cache. Quit first stops SIP and closes recovery action admission, then drains admitted recording work, history writes and durable retry. It then obtains a fresh asynchronous recovery snapshot. Pending scan/barrier state and termination generations prevent repeated Quit, duplicate callbacks or an old cancelled attempt from replying early or twice. A failed scan has an explicit Keep Files and Quit/Stay Open decision; it is not treated as empty. Cancelling reopens action admission.

## Ownership and file safety

The existing exclusive process claim spans current tracks and descriptor-based identity checks. Discovery excludes owned/completed jobs and never follows manifest track paths or symlinks. Created date sorts deterministically, with a directory timestamp fallback for unlabelled orphan jobs. Actual error records are bounded and persisted under ownership; production finalisation transfers the retained owner to the utility worker. Compatibility reporting can mutate a legacy manifest only with its original identity/revision authority.

Retry, report, confirmed discard and owned final cleanup admit into the finalisation group before worker dispatch. Main notifications, granted-scope release, callbacks and nested cleanup complete before their group count leaves. The serial utility worker owns claim/read/manifest/encoding work. Native capture-start metadata retains its existing admission behaviour; this change does not claim every recording-related file operation is asynchronous.

Each retry encodes into a unique private staging file. Publication creates the chosen destination exclusively, copies and syncs it; it never overwrites a file that appears after preflight or another queued export. Failure retains raw/staging data and the actual copy error. Partial-output cleanup checks the created inode before removing only that attempt's output. Successful export marks completion before owner cleanup. Confirmed discard reclaims/revalidates only the chosen unowned identity, retires its name atomically and removes flat entries through held descriptors, with the lock last. It refuses unexpected nested directories and restores surviving data to the original name when safe. There is no automatic deletion or retention expiry.

## Fresh validation and observed limits

The complete local isolated Telephone suite passed **428 XCTest + 48 Swift Testing cases, zero failures**. This includes 51 new cases: 12 metadata/discard, 5 index, 9 asynchronous ownership/export, 15 native UI, 4 application integration, 2 synthetic-collection measurements and 4 additional quit scenarios. Scope wrappers, calls and application collaborators are synthetic/inert; actual scratch filesystem permission denials and real tiny-WAV encoding exercise the controlled failure paths.

Separate checks passed: **105 recording ownership assertions** with real synthetic encoding/recovery, **32 native SIP-worker lifecycle checks**, **11 audio source-wiring checks** and **6 recording lifecycle model/wiring checks**. These are not added to suite cases. No unchanged supporting framework suite is claimed freshly rerun.

| Synthetic collection | First utility scan | Main queue callbacks during scan | 1,000 cached menu validations | Loader calls before→after validation |
| --- | ---: | ---: | ---: | ---: |
| 100 jobs / 12,800 raw bytes | 0.0250s | 25 | 0.000150s | 1→1 |
| 500 jobs / 64,000 raw bytes | 0.1187s | 119 | 0.000142s | 1→1 |

These are single first-read samples on the current filesystem cache, not cold-cache or production latency guarantees. CPU/time and actual retained-byte measurements are recorded in the [JSON evidence](2026-10-26-recording-recovery-browser.json). The main queue remained active during scanning, and validation performed no additional loads. No energy/battery benefit is claimed.

Validation caught and repaired lazy window initialisation. Initial fixture compilation exposed an ARC-reserved property name and an XCTest macro comma; both were corrected. Three earlier recording-start fixtures expected immediate scope release; they now wait on the actual finalisation drain while preserving all ownership assertions. The standalone harness's consumed semaphore predicate now latches its signal. An old source-wiring check was scoped to the encoder callback rather than the first unrelated group leave. Final complete results above follow these corrections, not the failed/interrupted runs.

All hosted runs used the disposable unique-identity Debug host with its main nib removed; production metadata was preserved. Actual provider/audio hardware, installed save panels/grants, quit/reopen and proficient VoiceOver remain pending by owner choice in [#62's matrix](../MACOS_27_ACCEPTANCE.md). No source change is an installation/release claim.

## Reproduction

Use local TelephoneTests build-for-testing, then `Scripts/prepare-isolated-test-host.py DERIVED_DATA`; test-without-building against `DERIVED_DATA/Build/Products/IsolatedTelephoneTests.xctestrun`. The six `RecordingRecovery*Tests` classes plus AppTerminationRegressionTests cover this issue; run the complete suite for the final gate. `Scripts/run-recording-tests.sh` exercises real synthetic formats/ownership. `Scripts/run-sip-lifecycle-regression-tests.py` uses `JPS_DEBUG_DERIVED_DATA` and a successful Debug link log; it redirects native lifecycle effects. Keep native hosted test-manager runs serial. Use only disposable fixture roots.

Final logs/results: `/private/tmp/jps-recovery68-final-v2-build.log`, `...-final-v2-full.log/.xcresult`, `...-final-harness-v2.log`, and `...-native-lifecycle/`. Source/log/capture hashes are in JSON. Independent review covered cache generations, repeated/stale quit, panel lifetime, filename collisions, legacy-report authority and descriptor cleanup.

Apple references rechecked 26 October 2026: [directory contents](https://developer.apple.com/documentation/foundation/filemanager/contentsofdirectory(at:includingpropertiesforkeys:options:)), [responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [asynchronous save sheets](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:)) and [indeterminate progress](https://developer.apple.com/documentation/appkit/nsprogressindicator/isindeterminate). Established APIs retain macOS 15.6 support; no macOS 27-only dependency was added.
