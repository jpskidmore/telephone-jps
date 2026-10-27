# Recording and call-history recovery

The source on main now includes [#68's recovery manager](maintenance/2026-10-26-recording-recovery-browser.md), verified on 26 October 2026. This is not an installed update: the released 3.6.1/build 165 still uses the earlier sequential alert. Start with [current maintenance](MAINTENANCE.md) for delivery status. The durable retention/ownership baseline from 3.0 and 3.6 is preserved.

## Recovering a recording on current main

**jps Telephone → Recover Recordings…** opens a selectable native list with filename, date, retained raw size, state, actual destination and last known error. Choose **Retry**, **Save Elsewhere…**, **Reveal**, or **Refresh**. Closing the window keeps files and admitted work. **Discard…** requires explicit confirmation for only the selected unowned job; no automatic expiry/deletion exists.

Discovery and recovery file work run off main. Cached menu validation performs no scan. Failed checks keep previous entries and show an error rather than an empty success. Pending jobs remain visible with indeterminate progress; closing/reopening cannot submit an old panel choice or duplicate operation.

Retry uses an available original filename or a new native save-panel destination. Invalid metadata requires Save Elsewhere. Existing files are never silently overwritten, including files appearing during conversion: private staging publishes to an exclusively created output. Failed export retains original audio and any staging data for another attempt. Raw size counts original tracks, excluding staging/metadata. A granted scope lasts through export/cleanup and is released before completion; an ungranted token is never stopped.

Quit closes new recovery admission and waits for recording and history drains, then checks recovery asynchronously. **Keep Files and Quit** retains unfinished jobs; **Stay Open** cancels termination and reopens actions. A failed recovery check has its own explicit decision. Failed history persistence cancels Quit separately. Native callbacks/generations reject stale and repeated termination replies.

Actual installed save panels, sandbox grants, quit/reopen, provider/hardware and proficient VoiceOver remain pending in [#62's matrix](MACOS_27_ACCEPTANCE.md). [Fresh source evidence and limits](maintenance/2026-10-26-recording-recovery-browser.md) are separate from installation/release.

## Recordings in call history on current main

New calls carry an optional opaque recording key. Each stop/start produces a distinct segment keyed to that exact call, including segments completed after disconnection or a redial. Older history and recordings remain unlinked; filenames are never used to guess an association.

Select a call and open **More → Recording**, or its history context menu. A single segment offers **Play in Default App** and **Reveal in Finder**; multiple segments have individual submenus. Capturing, saving, failed-start, discarded and recovery states cannot be played. Missing or changed files and unsupported playback show an explanation. **Refresh Recording Details** reloads cached catalogue metadata; **jps Telephone → Recover Recordings…** also attempts retained export-link repair.

A separate versioned `Recording Catalogue.plist` stores attachment metadata. History deletion, clearing all history and removing an account preserve exported recordings and raw recovery files. A later export updates its attachment metadata only and cannot recreate deleted history. The catalogue contains file bookmarks, not an additional capture owner.

File verification and bookmark resolution run off main when an action is chosen. The bookmark may follow a renamed resource; device/inode, length and content checks reject replaced or modified files. This deliberately refuses a new copy at the old path, even with a similar filename. Scoped access remains owned until the player-launch callback or Finder reveal request returns, and Quit drains admitted actions.

Export records an owned journal before writing output, including an exact reservation/file identity and expected encoded content. A successful conversion is not sufficient to remove raw audio: verified output and the available catalogue entry must be durable first. If saving the link fails, retained proof allows metadata-only repair after restart or Retry, without re-encoding into an existing filename. Save Elsewhere creates the explicitly chosen new file and preserves any older export. An unrelated file is never overwritten or adopted.

The durability checks are conservative: a file-only save grant may permit writing the output but deny opening/syncing its parent directory. That outcome retains the encoded output and raw recovery data and reports failure, including during later repair; it does not claim a fully durable link. Real save-panel grants, player/Finder handoff and installed quit/reopen remain unverified in #62. Source and synthetic verification are recorded separately in the dated maintenance evidence.

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
For linked jobs, export completion cleans the raw job only after verified output and durable catalogue publication; legacy unlinked jobs retain their established successful-conversion cleanup. An
export inside that job is rejected so cleanup cannot delete the recovered file.
Successful export and failure both finish the session's ownership exactly once;
failed export retains the job independently of a closed call window.

The fix for [#57](maintenance/2026-10-19-recording-ownership.md), delivered in
3.6/build 164, makes that ownership exclusive across discovery and retry. A per-job process lock spans capture through finalisation/cleanup;
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
