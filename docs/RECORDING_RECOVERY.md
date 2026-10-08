# Recording and call-history recovery

This documents the 3.0 repair, which passed controlled local component and hosted
validation. Release packaging, installation and publication remain pending; [repair progress](audit-2.1.8/repair-progress.json) and
[VALIDATION.md](VALIDATION.md) record the current status. Recovery adds compact
native alerts and menu actions without expanding the accepted call or Settings
layouts.

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

If local audio fails during a call, the existing recording segment is stopped and
finalized. A successful explicit audio retry can begin a new separately named
segment under the existing recording preference. No captured audio is claimed
for the unavailable interval. See [audio recovery](AUDIO_RECOVERY.md).

## Call-history persistence

An unreadable or malformed history file is reported as a failure. It is never
treated as an empty file and replaced by the next call. Pending mutations wait
for a successful reload, then merge over the existing history before saving.
Only a genuinely missing file starts empty.

**Clear Call History…** commits durable deletion before clearing the displayed
records. Failed deletion retains the records and offers retry. Removed accounts
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
