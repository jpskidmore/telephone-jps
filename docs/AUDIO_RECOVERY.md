# Audio failure containment and recovery

The audio repairs were published in **3.0/build 161**, whose controlled local
suites passed 617 automated cases with zero failures. The current published
release is **3.5.1/build 163**; local packaging, installation and private
publication are complete. Start with [current maintenance and release status](MAINTENANCE.md)
and [3.5.1 verification](releases/3.5.1-verification.md). The recorded checks below
retain their original scopes; this documentation update adds no test result.
The accepted compact windows and calling functions remain in place. All later
authorised build and test work runs locally under [VALIDATION.md](VALIDATION.md).

## What changes

Telephone now keeps a failed local-audio operation from triggering repeated
hardware opens through media callbacks, ringback, unmute and recording. The
failure gate retains the original error, makes one null-sound fallback attempt,
and blocks further opens/connections until an explicit **Retry Audio** action.
A null device supplies a software clock; it does not mean the microphone or
speakers recovered.

The application menu keeps **Audio unavailable: Retry Audio** available after
the warning sheet is dismissed. Open **Sound Settings** to choose the intended
input/output, then select **Retry Audio**. The retry refreshes the device list
and maps the current saved preferences. Changing ringtone output or receiving
generic device-change notifications does not itself unlock failed audio.

A successful retry restores current call media and ringback where appropriate.
It validates current native dialog identity and media state rather than replaying
stale conference-port IDs. Calls can remain connected while audio has failed;
the persistent call status says **Audio unavailable** rather than showing an
ordinary timer as though local audio worked. Hold and signaling state continue
to be processed normally.

If recording was active when audio failed, its existing segment is stopped and
finalized. Automatic recording does not create/reconnect a recorder under the
failure gate. If audio recovers while a confirmed call remains active, the
existing automatic-recording preference can start a new, separately named
segment. No recording is claimed for the unavailable interval. Hangup, recorder
finalization, and shutdown are never blocked by the retry gate.

Outgoing call requests share an admission barrier until the previous request's
result has been processed on the main thread. This prevents rapid requests from
queuing multiple SDK-internal audio opens before the first error is classified.
Queued/completed work is checked against a SIP lifecycle generation. The existing
SDK preflight before an outgoing INVITE is preserved.

## Worker ordering and current device identity

Main admits SIP/audio work, captures immutable settings, sets pending state and
then submits native operations to the user-agent's serial control worker. This
includes startup/shutdown, device refresh and selection, account operations and
call controls that can enter the SDK lock. CoreAudio device/default-change
delivery first moves its entire ordered fanout to main: refresh is admitted
before remapping, and both execute in order on the control worker. System device
queries, current SDK enumeration and driver opens in the queued selection occur
off main. The Settings pane's device-list property loading remains a separate
CoreAudio query path; it does not open an SDK audio driver.

Native completion must still match endpoint generation, current call ownership
and selection revision before changing UI state or reconnecting routes. An older
selection cannot release a newer pending command, clear its failure, or reconnect
audio after the endpoint stops. Retry remains visibly failed/pending until the
current selection actually succeeds. Saving Network settings during startup or
shutdown coalesces a restart using the latest saved configuration; failed startup
and application termination do not trigger restart loops.

Saved audio selections include physical CoreAudio UIDs. The patched native helper
resolves the exact current PJSIP global index through its driver table to the
physical CoreAudio device. Duplicate display names and independent enumeration
positions are not stable identity. Missing/ambiguous mapping fails visibly after
Null sound and remains gated until explicit recovery. See
[the pinned driver rebuild](DEPENDENCY_BUILDS.md#7a-30-native-coreaudio-uid-helper-and-local-archive-rebuild).

Recording encoding has its own serial worker and durable recovery jobs. History
uses a separate actor and synchronously admitted drain barrier. Quit waits for
native/recording shutdown and queued history persistence before its final reply;
see [recording recovery](RECORDING_RECOVERY.md).

## Important limits

The 3.0 changes move audited SDK-lock/audio-open entrypoints onto the serial
control worker and prevent repeated attempts after failure. They do not impose a
safe timeout on native driver calls. One CoreAudio/PJSIP operation can still take
a long time or stall that worker; PJSIP 2.17 can try six sample-rate candidates
while holding its global lock. The failure gate bounds repeated attempts, not the
duration of an individual backend call. New SDK call sites must preserve worker
ownership and completion-generation checks.

The known `-1936570544` PJSIP status decodes through the bundled macro
`440000 - OSStatus` to `1937010544`, Apple's `'stop'`
(`kAudioHardwareNotRunningError`). This says hardware was not running for an
operation that required it; it does not identify a particular connection type,
a driver, another application, or the precise blocking API. Do not infer that a
reboot, permission reset or service kill is required from this code alone.

Every failed explicit selection is gated. Conference connections and generic SDK
results are gated for known PJMEDIA audio errors and the verified encoded
`'stop'` error. An ordinary stale-port/SIP error must not poison working audio.
Unknown negative statuses remain raw, unclassified diagnostics until their
origin is established. Device refresh known to be an audio operation has a
separate fail-closed reporting path.

## Diagnostics

At default log level 3, `audio-device` entries include the operation and phase,
main/background context, numeric input/output and conference-port IDs, raw
status, and monotonic operation duration. The known `'stop'` mapping also includes
the native number and symbol. No new diagnostic contains SIP addresses,
credentials, device names, call contents, or recording destinations. Existing
SIP logging has its own historical behavior; these entries do not require
turning on SIP packet logging.

A future naturally occurring hang still needs a permitted sample of the exact
Telephone process, the contemporaneous audio-service evidence if accessible,
and actual selected device IDs/transport. The sample distinguishes a direct
CoreAudio wait from a PJSIP mutex wait or shutdown wait. No automatic timer
reproduces calls or changes device settings for this investigation.

## Validation

Recorded 3.0 component evidence includes 309 assertions against the production
audio gate with fake backend operations, 18 assertions from the exact patched
CoreAudio UID source with synthetic factory/device records, the real synthetic
recording encoder/recovery harness, and ordered mapping/worker regression tests.
Keep assertion counts separate from XCTest/Swift Testing test counts. The full
isolated 3.0 hosted suite also passed; [the repair map](REPAIR_VERIFICATION.md)
records that evidence, while [VALIDATION.md](VALIDATION.md) defines requirements
for later changes. No physical device or provider outcome is implied.

The following CI result is historical evidence of the earlier synchronous gate:
Native CI passed on 2 October 2026: [run 37037958671](https://github.com/jpskidmore/telephone-jps/actions/runs/37037958671)
built commit `fcd45a2f0fc12b5b9c0352091a4859ac6d3bd6fd` on a standard arm64
runner with macOS 15.7.9, Xcode 26.3, Swift 6.2.4 and macOS SDK 26.2. The log
records **232 production audio-controller checks**, the synthetic recording
harness, 11 wiring checks, six lifecycle-model tests and the unsigned Release
build all passing. See [the validation record](validation/audio-recovery-2026-10-02.md).

This did not run Telephone, the hosted XCTest suite, or physical audio/SIP tests.
It is not verification of macOS 27 hardware behavior. No application was signed,
installed or deployed. It does not verify changed 3.0 code. The current process
requires local validation and `[skip ci]` publication commits; no new cloud run
is authorised by this historical note. A native hardware stall remains possible.


Run the standalone policy harness on a Mac:

```sh
./Scripts/run-audio-device-tests.sh
```

It compiles the production `AKAudioDeviceController` against fake backend
operations only. It does not initialize PJSUA, open audio devices, register SIP,
launch Telephone, access its preferences/Keychain, or make calls. Coverage includes
first failure, one fallback, failed fallback, duplicate opens/connections,
explicit reset/retry, outgoing admission, error classification and safe logging.

Portable wiring checks:

```sh
python3 Tests/test_audio_recovery_integration.py
python3 Tests/test_recording_lifecycle_model.py
python3 Scripts/verify-dependency-manifests.py
```

These checks inspect source or execute explicit models; they do not execute
Objective-C/PJSIP. The historical combined runner below also compiles Release:

```sh
./Scripts/run-isolated-audio-validation.sh
```

The 50-issue repair gate completed in 3.0. For later authorised work, select the
required component runners and isolated Debug host through
[VALIDATION.md](VALIDATION.md); the historical combined runner is not the full
current release gate. The normal `TelephoneTests` host can load real
preferences and start the app; test-host isolation must remove its main nib,
use a synthetic bundle/defaults identity and preserve production metadata. A
development build does not establish installation or real-device acceptance.

Manual device scenarios still to record: a healthy wired call; a failing
open; repeated queued media/unmute/ringback events; failed fallback; explicit
retry with changed selection during a call and while idle; hangup and quit while
failed; rapid outgoing requests; sleep/restart and late callback delivery;
hold/unhold; recording recovery into separate segments. Confirm that an idle
successful retry releases hardware through the existing idle-close mechanism.
