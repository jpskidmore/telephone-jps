# Recording and call-history recovery

This describes recovery behaviour introduced by the published **3.0/build 161**
repair and retained in **3.5.1/build 163**. Current local packaging, installation
and private publication are complete; start with [current maintenance and release
status](MAINTENANCE.md) and [3.5.1 verification](releases/3.5.1-verification.md).
The [repair map](REPAIR_VERIFICATION.md) preserves the controlled 3.0 evidence;
[VALIDATION.md](VALIDATION.md) defines checks for later authorised changes. This
documentation update adds no test result. Recovery uses compact native alerts
and menu actions without expanding the accepted call or Settings layouts.

## Recovering a recording

If a captured recording cannot be exported, Telephone retains its original local
and remote audio and shows **Recording could not be saved**. Choose **Retry**,
**Save Elsewhere…**, **Show Recovery Files**, or **Later**. The Telephone menu's
**Recover Recordings…** action remains available while a recoverable job exists.
Jobs are discovered again when the app opens.

Retry uses the original filename when it is safe and available. An existing file,
missing/damaged destination metadata, or a destination inside the raw recovery
folder requires a fresh destination. Save Elsewhere uses the native save panel.
Recovery never silently replaces a later recording at the old filename. If the
chosen destination cannot be written, the originals remain available for another
attempt. A granted destination security-scope token remains active for the
complete asynchronous export and is released before the completion callback;
an ungranted token is never stopped.

At Quit, **Keep Files and Quit** retains unfinished recovery jobs for reopening;
**Stay Open** cancels termination. These choices follow pending conversion and
history persistence, rather than interrupting them. If history still cannot be
saved, Quit is cancelled and a separate history error offers retry.

## Durable data and ownership

Each recording stores its two raw WAV tracks and `recovery.plist` in a unique job
below the app's Application Support `Recording Recovery` directory. The root and
job directories use mode 0700; the atomic manifest and tracks use mode 0600. They
are not kept in temporary/cache storage, which macOS may purge. The manifest
records track basenames and the intended export path before capture and again
before final export. A job remains recoverable even if its manifest is missing
or damaged but both default raw tracks survive.

Each native recorder/session owns its own tracks, destination reservation and
folder-access lifetime. Encoder work is serial and finalization is asynchronous.
The export completion cleans the raw job only after successful conversion. An
export inside that job is rejected so cleanup cannot delete the recovered file.
Successful export and failure both finish the session's ownership exactly once;
failed export retains the job independently of a closed call window.

The source fix for [#57](maintenance/2026-10-19-recording-ownership.md), awaiting
the combined roadmap release, makes that ownership exclusive across discovery
and retry. A per-job process lock spans capture through finalisation/cleanup;
version 2 metadata records capturing, finalising, failed or completed. Owned
jobs are hidden from failed recovery. After process death, unowned unfinished
jobs and safe legacy/malformed jobs remain recoverable. Failed exports retain
raw tracks; completed jobs are excluded even when cleanup was interrupted.

If local audio fails during a call, the existing recording segment is stopped and
finalized. A successful explicit audio retry can begin a new separately named
segment under the existing recording preference. No captured audio is claimed
for the unavailable interval. See [audio recovery](AUDIO_RECOVERY.md).

## Call-history persistence

An unreadable or malformed history file is reported as a failure. It is never
treated as an empty file and replaced by the next call. Pending mutations wait
for a successful reload, then merge over the existing history before saving.
Only a genuinely missing file starts empty.

**More → Clear Call History…** clears the combined history across configured
accounts and commits durable deletion before clearing the displayed records.
Failed deletion retains the records and offers retry. Removed accounts
reject held or delayed additions and cannot lazily recreate their history. An
already-failed account deletion remains retained for deletion-only retry after
its cache owner disappears, then releases after success.

History work is admitted synchronously before actor scheduling. Quit closes new
admission, drains all previously admitted and nested writes, retries durable
failures, then replies to termination exactly once. Cancelling Quit reopens
admission. Contacts/receipt/history presentation also carries reload generations
so an older asynchronous result cannot undo a newer clear or update.

## Local verification and limits

The recording harness uses unique scratch roots and real synthetic audio. It
checks WAV/MP3/Ogg output, strict left/right channel integrity, asynchronous
cleanup/drain, a real AudioToolbox export-denial failure, durable reload and retry
elsewhere. It also checks unsafe/missing manifest destinations and simulated
security-scope grants/refusals, including asynchronous conversion failure.
Scope methods alone are redirected in that standalone process; this does not
claim a real macOS sandbox grant or recorder capture.

The history/resource harness forces scratch-file read denial and unlink denial,
checks exact original bytes, recovery merging, transactional clear and delayed
account additions. Controlled hosted termination cases check recording->history
drain->retry ordering, repeat-call idempotence and both recovery Quit choices.
No test queries the user's real history, credentials, Contacts or recovery folder.

Real SIP recording, physical microphone/speaker behaviour, sandbox save-panel
permissions and a full app quit/reopen recovery session remain manual acceptance
boundaries. Record them separately on the exact installed release build.

Apple references: [atomic data writing](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic),
[Using the file system effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively),
and [Task lifetime](https://developer.apple.com/documentation/swift/task).
