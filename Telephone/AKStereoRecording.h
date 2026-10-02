//
//  AKStereoRecording.h
//  Telephone
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
