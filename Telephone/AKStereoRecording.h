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
BOOL AKPersistRecordingRecoveryJob(NSURL *directory, NSURL *local, NSURL *remote,
                                   NSURL *destination, NSError **error);
NSArray<NSDictionary *> *AKPendingRecordingRecoveryJobs(void);
NSArray<NSDictionary *> *AKRecordingRecoveryJobsAtRoot(NSURL *root);
void AKReportRecordingExportFailure(NSURL *directory, NSURL *destination, NSError * _Nullable error);
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

// Asynchronously waits for conversions already submitted, including their main-
// queue completion/cleanup callbacks. Stop call production before using this as
// the application-termination barrier. Always calls back on the main queue.
void AKWaitForPendingRecordingFinalizations(dispatch_block_t completion);

NS_ASSUME_NONNULL_END
