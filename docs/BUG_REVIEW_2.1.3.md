# Foundation and lifecycle bug review for 2.1.3

Reviewed on 5 October 2026 against baseline
`a58e04eb9817c68970ee269dde89397c91e192a0`.

This bounded source review covered ringtone lifetime, reminder preferences,
receipt device-property handling, notification cleanup, Core Audio listener
ownership, and call-history file operations. It is not an exhaustive audit or
physical audio/SIP acceptance test. The UI work is documented separately in
[LIQUID_GLASS.md](LIQUID_GLASS.md).

## Fixed bugs

### 1. Releasing a playing ringtone could leave it repeating

`UseCases/RepeatingSound.swift` previously had no teardown for its running timer.
Releasing the ringtone without calling `stopPlaying()` released its own timer
reference, but the run loop still retained the repeating Foundation timer. Its
adapter and `sound.play` action kept the sound alive and able to fire again.
The normal explicit stop path worked; owner teardown was the missing path.

The ringtone now invalidates an outstanding timer and stops its active sound
during deinitialization. Explicitly stopped and never-started ringtones do not
receive extra teardown stops. The Foundation timer factory now imports and
names Foundation's timer explicitly rather than relying on the app's bridging
header for the unqualified `Timer` symbol.

Apple explains the run loop's timer retention and the need to invalidate a
repeating timer. Invalidation releases the target. Apple also requires
invalidation on the thread where the timer was installed; the application's
existing ringtone operations and the actual-timer regression test use the
main thread. [Timer](https://developer.apple.com/documentation/foundation/timer),
[invalidate()](https://developer.apple.com/documentation/foundation/timer/invalidate()).

Verification uses the production timer adapters and a fake sound: actual
repeated firing occurs before release, the owner/adapter/sound release on
teardown, and another run-loop interval produces no further play. Three added
`UseCasesTests/RepeatingSoundTests.swift` cases cover active release, release
after explicit stop, and unstarted release.

### 2. Incorrectly typed saved reminder values could crash

`Telephone/UserDefaultsPurchaseReminderSettings.swift` forcibly cast the
stored date and unwrapped the version. A stored string instead of a date, or
an array instead of a version, takes priority over registration defaults and
can make those operations trap. Registering defaults supplies missing values;
it does not validate stored values. [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults).

Both getters now use the established fallbacks (`Date.distantPast` and the
empty string) when the stored value has an invalid type. Valid values and
setters keep their behavior. The local Pro configuration does not depend on
purchase reminders, so this is a retained-code robustness fix rather than a
claim that reminder UI was exercised in this build.

Verification uses a fresh UUID-named defaults suite, checks missing and valid
values, inserts the invalid stored types, and confirms subsequent valid writes
recover. The suite's persistent domain is removed when the test completes.

### 3. Missing or unexpected IOKit MAC properties could crash the receipt helper

`ReceiptValidation/DeviceGUID.swift` forcibly unwrapped the result of
`IORegistryEntryCreateCFProperty` and cast it to `CFData`. That API returns an
optional unmanaged CF value, and registry values have several possible CF
types. The helper now consumes a successful Create result once, conditionally
converts it to data, and skips absent or unexpected properties. Iterator,
parent, and service ownership is retained; iterator cleanup now uses `defer`.
This preserves the existing empty-data result when no usable address is found
and does not bypass receipt signature/checksum checks. [IORegistryEntryCreateCFProperty](https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty).

Verification injects a missing property, retained CF string, and retained valid
MAC bytes into the production conversion helper. The tests do not query the
machine's registry or instantiate a receipt-validation service. This local
Pro build does not require the Store/receipt path.

## Redundant code removed

- `Telephone/SimplePropertyListStorage.swift`: removed two catch clauses whose
  sole action was to rethrow the same error. Missing-file handling and atomic
  saves remain; unmatched errors still propagate from the throwing methods.
- `Telephone/AKSIPUserAgentEventSource.swift`: replaced three partial observer
  removals with one removal during deinitialization, covering all five
  subscriptions. This object owns those subscriptions and is ending its
  lifetime. Apple documents removal of all subscriptions as safe during
  deallocation; modern selector observers already have automatic cleanup, so
  this is cleanup consistency rather than a claimed use-after-free fix.
  [removeObserver(_:)](https://developer.apple.com/documentation/foundation/notificationcenter/removeobserver(_:)-2yciv).

No feature modules, third-party libraries, account settings, SIP callbacks,
recording conversions, or audio-recovery policy were removed as speculative
dead code.

## Reviewed candidates retained

- **Core Audio listeners:** `CoreAudioChangeEventSource` already stores the
  exact callback and dispatch queue used for registration and removes the
  matching listener at teardown. Its wrappers forward device notifications
  to the existing actor-isolated targets. This matches the relevant ownership
  requirements; no listener rewrite was justified.
  [AudioObjectAddPropertyListenerBlock](https://developer.apple.com/documentation/coreaudio/audioobjectaddpropertylistenerblock(_:_:_:_:)).
- **Audio error containment and recording recovery:** retained the existing
  failure gate, explicit retry, lifecycle generation checks, separate recovery
  recording segments, and native-recorder finalization. A threading rewrite
  would affect call behavior and needs device evidence. The known first-open
  blocking limitation is described in [AUDIO_RECOVERY.md](AUDIO_RECOVERY.md).
- **History persistence:** existing writes already use Foundation's atomic
  option and serialize through the call-history actor. Valid existing behavior
  did not justify a new storage format or broad persistence rewrite.
  [Data.WritingOptions.atomic](https://developer.apple.com/documentation/foundation/data/writingoptions/atomic).
- **Force casts for private app notification payloads:** these use payloads
  constructed by the app's own SIP/account producers. The review did not
  establish an unexpected producer or reproduce an invalid production
  payload, so it did not substitute speculative fallback behavior.
- **Store and receipt modules:** retained despite local Pro bypasses. They are
  referenced by other configurations and existing tests; absence from a local
  feature path alone is insufficient evidence that they are safe to delete.

## Verification

```sh
./Scripts/run-foundation-regression-tests.sh
```

Passed **25 checks** on macOS with Apple Swift 6.4 on 5 October 2026. This
standalone runner compiles the actual production types and a minimal real
UseCases module. It matches the application's isolated-conformance compiler
feature. It uses a real Foundation timer with fake playback, a UUID-named
defaults suite, and injected CF properties. It does not launch Telephone,
start PJSUA, make calls, open audio hardware, query IOKit, read Contacts, or
access the user's normal preferences/Keychain.

The existing UseCases XCTest suite includes the three additional ringtone
regressions. Full suite/build evidence is recorded by the release validation
runner in [VALIDATION.md](VALIDATION.md) and the release-specific validation
record. The standalone checks do not substitute for live-device call, audio,
recording, receipt, or UI acceptance.

### Full-suite fixture correction

The initial full release gate on main commit
`9a997a97211dd9a9cd5d5d609f0f9cc228196a76` stopped in the hosted Telephone
tests. `AKSIPUserAgentEventSourceTests.testCallsDidMakeCall` and
`testCallsUserAgentDidReceiveCall` posted call notifications with `object: nil`.
The hosted app's existing `AKSIPCallEventSource` also receives those notifications
and requires the normal `Call` payload, producing a cast failure at its
`didMake`/`didReceive` handlers. Initial evidence:
[release validation run 37331757663](https://github.com/jpskidmore/telephone-jps/actions/runs/37331757663).

The shared fixture now uses `CallTestFactory().make()`, the same in-memory
`SimpleCall` fixture used by other call-event tests. Constructing it does not
register SIP, make a native call, open audio hardware, or read account settings.
No production notification fallback was added. This corrects a pre-existing
test payload; the full gate must be rerun to verify the updated fixture and
release packaging.
