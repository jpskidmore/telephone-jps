# Audio failure containment and recovery

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

## Important limits

This is synchronous **retry containment**, not a rewrite of PJSIP threading or a
claim that all beachballs are fixed. One CoreAudio/PJSIP operation can still take
a long time. PJSIP 2.17 tries six sample-rate candidates while holding its global
lock. Dispatching only the initial open to a worker would leave other UI-side SIP
calls waiting on that same lock, so this patch does not make that unsafe promise.

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

At default log level 3, `AKAudio` entries include the operation and phase,
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

Current candidate status (2 October 2026): independent source review completed,
11 portable wiring checks and six recording-lifecycle model tests passed, and
dependency hashes/inventory plus shell/whitespace checks passed. The Mac became
unavailable before transfer or compilation, so the standalone native harnesses,
unsigned application build and hosted XCTest execution have **not run** for this
candidate. No application was installed. Native verification remains a merge
requirement; a temporary source branch is not a validated release.


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
Objective-C/PJSIP. For an isolated native compile plus the safe standalone
harnesses, use:

```sh
./Scripts/run-isolated-audio-validation.sh
```

This runner does not run the app-hosted `TelephoneTests` bundle. That bundle's
normal host can read real preferences/start the application, so it remains for a
disposable, separately approved test account. An unsigned application build is
not signing, installation, launch, or real-device acceptance.

Required separately approved device scenarios: a healthy wired call; a failing
open; repeated queued media/unmute/ringback events; failed fallback; explicit
retry with changed selection during a call and while idle; hangup and quit while
failed; rapid outgoing requests; sleep/restart and late callback delivery;
hold/unhold; recording recovery into separate segments. Confirm that an idle
successful retry releases hardware through the existing idle-close mechanism.
