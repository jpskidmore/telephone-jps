//
//  AKStereoRecording.h
//  Telephone
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const AKRecordingExportDidFailNotification;
// Captured tracks and an atomic retry manifest live in protected Application
// Support rather than purgeable temporary storage. The AtRoot variants permit
// synthetic, disposable file tests without touching the user's recovery folder.
NSURL * _Nullable AKCreateRecordingRecoveryDirectory(NSError **error);
NSURL * _Nullable AKCreateRecordingRecoveryDirectoryAtRoot(NSURL *root, NSError **error);

// The claim is exclusive across processes and lasts until finish/discard or the
// owner's lifetime ends. A process exit releases the claim without destroying
// raw tracks, so abandoned capture/finalisation remains recoverable.
@interface AKRecordingJobOwnership : NSObject
@property(nonatomic, readonly, copy) NSURL *directoryURL;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

typedef NS_ENUM(NSUInteger, AKRecordingJobPhase) {
    AKRecordingJobPhaseCapturing,
    AKRecordingJobPhaseFinalising,
};

AKRecordingJobOwnership * _Nullable AKClaimRecordingJob(NSURL *directory, NSError **error);
BOOL AKPersistOwnedRecordingRecoveryJob(AKRecordingJobOwnership *owner,
                                        NSURL *local, NSURL *remote, NSURL *destination,
                                        AKRecordingJobPhase phase, NSError **error);
// Idempotent. Failure records failed state and retains raw tracks; success marks
// completed before owner-only cleanup. Both release the exclusive claim.
void AKFinishRecordingRecoveryJob(AKRecordingJobOwnership *owner, BOOL succeeded);
// Retains the existing claim through utility-worker metadata/cleanup. A failure
// records its actual error (or truthful generic detail) before notifying on main.
// Completion is asynchronous on main and included in the termination drain. A
// nil destination omits the export notification for incomplete-session cleanup.
void AKFinishRecordingRecoveryJobAsync(AKRecordingJobOwnership *owner, BOOL succeeded,
                                       NSURL * _Nullable destination, NSError * _Nullable error,
                                       dispatch_block_t _Nullable completion);
// Owner-only cleanup for a recording which could not start.
void AKDiscardRecordingRecoveryJob(AKRecordingJobOwnership *owner);

// Compatibility entry point for an already-abandoned/legacy job. It acquires a
// transient claim and cannot rewrite another capture or finalisation's manifest.
BOOL AKPersistRecordingRecoveryJob(NSURL *directory, NSURL *local, NSURL *remote,
                                   NSURL *destination, NSError **error);
NSArray<NSDictionary *> *AKPendingRecordingRecoveryJobs(void);
NSArray<NSDictionary *> *AKRecordingRecoveryJobsAtRoot(NSURL *root);
// Synchronous discovery; callers should run it on their utility worker. A missing
// root is an empty result; an unreadable root/job returns nil and its real error.
// Busy/completed jobs are excluded. Stable snapshots include directoryIdentity
// (device:inode), created, title, retainedRawBytes, phase, lastErrorDescription,
// and lastError only when an actual NSError was recorded. Safe legacy/orphan
// tracks have truthful unknown metadata. Results sort by created, then identity.
NSArray<NSDictionary *> * _Nullable AKPendingRecordingRecoveryJobsWithError(NSError **error);
NSArray<NSDictionary *> * _Nullable AKRecordingRecoveryJobsAtRootWithError(NSURL *root, NSError **error);
// For an explicitly confirmed UI snapshot only. Requires its exact nonempty
// directoryIdentity, reacquires ownership and rereads eligibility before retiring
// the directory name and removing it. No automatic discard or expiry is implied.
BOOL AKDiscardPendingRecordingRecoveryJob(NSDictionary *job, NSError **error);
void AKDiscardPendingRecordingRecoveryJobAsync(NSDictionary *job,
    void (^completion)(BOOL succeeded, NSError * _Nullable error));
// Asynchronously reports on main after best-effort utility-worker persistence.
// The legacy persist entry point binds identity/revision to its directory URL;
// without that context this API only notifies. Owned finalizers use the async
// finish API so a late report cannot rewrite a replacement or newer attempt.
// Nil error does not invent a native error code. Included in termination drain.
void AKReportRecordingExportFailure(NSURL *directory, NSURL *destination, NSError * _Nullable error);
// Copies the chosen snapshot and admits before dispatching any file I/O. Its
// exact directoryIdentity is required. Revalidates on a serial utility worker;
// busy/stale admission is rejected on main without a new export failure. Scope
// release, notification and main completion are included in termination drain.
void AKRetryRecordingRecoveryJob(NSDictionary *job, NSURL *destination,
                                 void (^completion)(BOOL succeeded));

// Atomically reserves a collision-free file in directoryURL. The caller owns the
// empty file and should remove it if recording cannot be started.
NSURL * _Nullable AKReserveRecordingURL(NSURL *directoryURL,
                                        NSString *filenameStem,
                                        NSString *extension,
                                        NSError **error);

// Interleaves synchronized mono WAV files into a stereo WAV, MP3, or Ogg/Opus file.
// The local file becomes the left channel and the remote file becomes the right channel.
BOOL AKMergeMonoRecordingsIntoStereo(NSURL *localURL, NSURL *remoteURL, NSURL *destinationURL);

// Performs the potentially long merge and compression work on a serial utility queue.
// Completion is delivered on the main queue.
void AKMergeMonoRecordingsIntoStereoAsync(NSURL *localURL,
                                          NSURL *remoteURL,
                                          NSURL *destinationURL,
                                          void (^completion)(BOOL succeeded));

// Waits for admitted conversions, retries, async discards and finalization/error
// reports, including their main completion/cleanup callbacks and nested work.
// Stop call/recovery action production before this termination barrier.
// Always calls back asynchronously on the main queue.
void AKWaitForPendingRecordingFinalizations(dispatch_block_t completion);

NS_ASSUME_NONNULL_END
