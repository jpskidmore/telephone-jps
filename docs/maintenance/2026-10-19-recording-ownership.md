# Recording recovery ownership — issue #57

Capture now claims its private job before writing metadata or creating tracks.
The same exclusive claim survives native recorder shutdown and asynchronous
finalisation. Discovery and retry cannot admit an owned job, even with missing
or malformed metadata; retry revalidates current files and identity after claiming
the job. Busy, stale and duplicate requests complete asynchronously on main with
failure, without generating another export-failure notification.

A protected per-job `flock` coordinates processes. Version 2 manifests record
capturing, finalising, failed or completed. Process death releases the lock, so
abandoned jobs remain recoverable; safe legacy/missing/malformed manifests remain
supported. Failure keeps raw tracks. Success marks completed and atomically
retires the directory before removal while still owning it. Completed jobs are
excluded if cleanup is interrupted. Old claim objects cannot remove a new job.
Discovery skips empty new directories to avoid competing with capture admission.

## Fresh verification — 19 October 2026

The original source reproduced the gap with isolated synthetic WAV tracks: jobs
appeared during open-writer capture and queued finalisation before main cleanup.
This did not reproduce real-call audio loss.

- Final isolated app suite: **310 cases, zero failures** — 262 XCTest plus
  48 Swift Testing. Three new cases exercise held capture/encoder completion,
  stale completion ownership and finalisation-manifest failure. Existing native
  stop, scope-lifetime and termination tests passed.
- Standalone recording harness: existing synthetic codec/channel/collision/
  scope/recovery/drain checks passed, plus **102 new ownership assertions**.
  Separate synthetic processes prove live exclusion and recovery after process
  death for capturing/finalising jobs. Duplicate/stale retries, failure retention,
  legacy/malformed/completed manifests and cleanup ownership are covered.
- Separately counted: six recording lifecycle model/source checks and eleven
  audio integration checks. Unchanged framework results remain historical.

The [JSON evidence](issue-57-verification.json) records source and log hashes.
Builds used a fresh unique nib-free Debug host; files and recording processes
were synthetic and isolated. Native physical capture, actual sandbox grants and
the full installed-app quit/reopen scenario remain practical acceptance work
under [#62](https://github.com/jpskidmore/telephone-jps/issues/62).

This source fix does not install, publish or bump the app version. The owner
chose one verified commit per fix and a combined release after the roadmap.
Installed baseline remains 3.5.1/build 163; release tags/assets are preserved.

Official references: [OpenAI best practices](https://learn.chatgpt.com/docs/learn/best-practices),
[Apple macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes),
[DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
and [Apple's flock manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html).
These guide scoped work and ownership; no OpenAI runtime or new macOS-only API
requirement is introduced.
