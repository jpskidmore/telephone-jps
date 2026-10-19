//
//  AKStereoRecording.m
//  Telephone
//

#import "AKStereoRecording.h"

#import <AudioToolbox/AudioToolbox.h>
#import <lame/lame.h>
#import <opus.h>
#import <opusenc.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *const AKRecordingExportDidFailNotification = @"AKRecordingExportDidFailNotification";
static NSString *const RecoveryManifestName = @"recovery.plist";
static NSString *const RecoveryLockName = @".owner.lock";

static void RecordingPOSIXError(NSError **error, int code) {
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

@interface AKRecordingJobOwnership () {
    int _directoryDescriptor;
    int _lockDescriptor;
}
@property(nonatomic, readwrite, copy) NSURL *directoryURL;
@property(nonatomic, readonly) int directoryDescriptor;
- (instancetype)initWithDirectory:(NSURL *)directory directoryDescriptor:(int)directoryDescriptor
                   lockDescriptor:(int)lockDescriptor;
- (BOOL)isCurrent;
- (void)releaseClaim;
@end

@implementation AKRecordingJobOwnership
- (instancetype)initWithDirectory:(NSURL *)directory directoryDescriptor:(int)directoryDescriptor
                   lockDescriptor:(int)lockDescriptor {
    self = [super init];
    if (self) {
        _directoryURL = [directory copy];
        _directoryDescriptor = directoryDescriptor;
        _lockDescriptor = lockDescriptor;
    }
    return self;
}
- (int)directoryDescriptor { return _directoryDescriptor; }
- (BOOL)isCurrent {
    struct stat heldDirectory, currentDirectory, heldLock, currentLock;
    return _directoryDescriptor >= 0 && _lockDescriptor >= 0 &&
        fstat(_directoryDescriptor, &heldDirectory) == 0 &&
        lstat(self.directoryURL.fileSystemRepresentation, &currentDirectory) == 0 &&
        S_ISDIR(currentDirectory.st_mode) &&
        heldDirectory.st_dev == currentDirectory.st_dev && heldDirectory.st_ino == currentDirectory.st_ino &&
        fstat(_lockDescriptor, &heldLock) == 0 &&
        fstatat(_directoryDescriptor, RecoveryLockName.fileSystemRepresentation, &currentLock, AT_SYMLINK_NOFOLLOW) == 0 &&
        S_ISREG(currentLock.st_mode) && heldLock.st_dev == currentLock.st_dev && heldLock.st_ino == currentLock.st_ino;
}
- (void)releaseClaim {
    if (_lockDescriptor >= 0) close(_lockDescriptor);
    if (_directoryDescriptor >= 0) close(_directoryDescriptor);
    _lockDescriptor = _directoryDescriptor = -1;
}
- (void)dealloc { [self releaseClaim]; }
@end

AKRecordingJobOwnership *AKClaimRecordingJob(NSURL *directory, NSError **error) {
    if (![directory isKindOfClass:NSURL.class] || !directory.isFileURL || !directory.path.isAbsolutePath) {
        RecordingPOSIXError(error, EINVAL);
        return nil;
    }
    NSURL *canonical = directory.URLByResolvingSymlinksInPath.standardizedURL;
    int directoryDescriptor = open(canonical.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directoryDescriptor < 0) {
        RecordingPOSIXError(error, errno);
        return nil;
    }
    int descriptor = openat(directoryDescriptor, RecoveryLockName.fileSystemRepresentation,
                            O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
    struct stat lockInfo;
    int claimError = descriptor < 0 ? errno : 0;
    if (!claimError && (fstat(descriptor, &lockInfo) != 0)) claimError = errno;
    if (!claimError && (!S_ISREG(lockInfo.st_mode) || lockInfo.st_nlink != 1 || lockInfo.st_uid != geteuid())) claimError = EINVAL;
    if (!claimError && fchmod(descriptor, 0600) != 0) claimError = errno;
    if (!claimError && flock(descriptor, LOCK_EX | LOCK_NB) != 0) claimError = errno;
    if (claimError) {
        if (descriptor >= 0) close(descriptor);
        close(directoryDescriptor);
        RecordingPOSIXError(error, claimError);
        return nil;
    }
    AKRecordingJobOwnership *owner = [[AKRecordingJobOwnership alloc] initWithDirectory:canonical
        directoryDescriptor:directoryDescriptor lockDescriptor:descriptor];
    if (![owner isCurrent]) {
        [owner releaseClaim];
        RecordingPOSIXError(error, ESTALE);
        return nil;
    }
    // Never unlink a live lock file: replacing its inode would admit a second
    // owner while this descriptor still holds the original exclusive flock.
    return owner;
}

static BOOL ValidRecordingTrackName(NSString *name) {
    return [name isKindOfClass:NSString.class] && name.length > 0 &&
        ![@[@".", @"..", RecoveryManifestName, RecoveryLockName] containsObject:name] &&
        [name isEqualToString:name.lastPathComponent];
}

static BOOL OwnedTrackIsRegular(AKRecordingJobOwnership *owner, NSString *name, BOOL allowMissing, NSError **error) {
    struct stat info;
    if (fstatat(owner.directoryDescriptor, name.fileSystemRepresentation, &info, AT_SYMLINK_NOFOLLOW) != 0) {
        if (allowMissing && errno == ENOENT) return YES;
        RecordingPOSIXError(error, errno);
        return NO;
    }
    if (!S_ISREG(info.st_mode)) {
        RecordingPOSIXError(error, EINVAL);
        return NO;
    }
    return YES;
}

static NSDictionary *OwnedRecordingManifest(AKRecordingJobOwnership *owner) {
    int descriptor = openat(owner.directoryDescriptor, RecoveryManifestName.fileSystemRepresentation,
                            O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (descriptor < 0) return nil;
    struct stat info;
    NSMutableData *data = [NSMutableData data];
    BOOL valid = fstat(descriptor, &info) == 0 && S_ISREG(info.st_mode) && info.st_size <= 1024 * 1024;
    unsigned char bytes[4096];
    while (valid) {
        ssize_t count = read(descriptor, bytes, sizeof(bytes));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) valid = NO;
        if (count <= 0) break;
        [data appendBytes:bytes length:(NSUInteger)count];
        if (data.length > 1024 * 1024) valid = NO;
    }
    close(descriptor);
    id manifest = valid ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
    return [manifest isKindOfClass:NSDictionary.class] ? manifest : nil;
}

static BOOL WriteOwnedRecordingManifest(AKRecordingJobOwnership *owner, NSDictionary *manifest, NSError **error) {
    if (![owner isCurrent]) {
        RecordingPOSIXError(error, ESTALE);
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:manifest
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    NSString *temporaryName = [@".manifest-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int descriptor = openat(owner.directoryDescriptor, temporaryName.fileSystemRepresentation,
                            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (descriptor < 0) {
        RecordingPOSIXError(error, errno);
        return NO;
    }
    const unsigned char *bytes = data.bytes;
    NSUInteger remaining = data.length;
    int writeError = 0;
    while (remaining > 0) {
        ssize_t count = write(descriptor, bytes, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { writeError = count < 0 ? errno : EIO; break; }
        bytes += count;
        remaining -= (NSUInteger)count;
    }
    if (!writeError && fsync(descriptor) != 0) writeError = errno;
    if (close(descriptor) != 0 && !writeError) writeError = errno;
    if (!writeError && ![owner isCurrent]) writeError = ESTALE;
    if (!writeError && renameat(owner.directoryDescriptor, temporaryName.fileSystemRepresentation,
                               owner.directoryDescriptor, RecoveryManifestName.fileSystemRepresentation) != 0) writeError = errno;
    if (writeError) {
        unlinkat(owner.directoryDescriptor, temporaryName.fileSystemRepresentation, 0);
        RecordingPOSIXError(error, writeError);
        return NO;
    }
    // The atomic rename publishes one complete state. Sync the directory where
    // supported as well; the track retention rule does not depend on this call.
    fsync(owner.directoryDescriptor);
    return YES;
}

static BOOL IsCompletedRecordingManifest(NSDictionary *manifest) {
    return [manifest[@"version"] isKindOfClass:NSNumber.class] && [manifest[@"version"] integerValue] >= 2 &&
        [manifest[@"state"] isKindOfClass:NSString.class] && [manifest[@"state"] isEqualToString:@"completed"];
}

static BOOL RecordingDestinationIsOutsideDirectory(NSURL *destination, NSURL *directory) {
    if (![destination isKindOfClass:NSURL.class] || !destination.isFileURL || !destination.path.isAbsolutePath) return NO;
    NSString *path = destination.URLByResolvingSymlinksInPath.standardizedURL.path;
    NSString *directoryPath = directory.path;
    return ![path isEqualToString:directoryPath] && ![path hasPrefix:[directoryPath stringByAppendingString:@"/"]];
}

static BOOL PersistRecordingManifest(AKRecordingJobOwnership *owner, NSURL *local, NSURL *remote,
                                      NSURL *destination, NSString *state, NSError **error) {
    @synchronized (owner) {
        NSString *localName = local.lastPathComponent;
        NSString *remoteName = remote.lastPathComponent;
        if (![owner isCurrent] || !local.isFileURL || !remote.isFileURL ||
            !ValidRecordingTrackName(localName) || !ValidRecordingTrackName(remoteName) || [localName isEqualToString:remoteName] ||
            ![local.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath.standardizedURL isEqual:owner.directoryURL] ||
            ![remote.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath.standardizedURL isEqual:owner.directoryURL] ||
            !RecordingDestinationIsOutsideDirectory(destination, owner.directoryURL)) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError userInfo:nil];
            return NO;
        }
        if (!OwnedTrackIsRegular(owner, localName, YES, error) || !OwnedTrackIsRegular(owner, remoteName, YES, error)) return NO;
        for (NSString *name in @[localName, remoteName]) {
            int descriptor = openat(owner.directoryDescriptor, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
            if (descriptor < 0 && errno == ENOENT) continue;
            if (descriptor < 0) { RecordingPOSIXError(error, errno); return NO; }
            int chmodError = fchmod(descriptor, 0600) != 0 ? errno : 0;
            close(descriptor);
            if (chmodError) { RecordingPOSIXError(error, chmodError); return NO; }
        }
        NSDictionary *previous = OwnedRecordingManifest(owner);
        NSMutableDictionary *manifest = [@{@"version": state ? @2 : @1, @"local": localName,
            @"remote": remoteName, @"destination": destination.path,
            @"created": [previous[@"created"] isKindOfClass:NSDate.class] ? previous[@"created"] : NSDate.date} mutableCopy];
        if (state) manifest[@"state"] = state;
        return WriteOwnedRecordingManifest(owner, manifest, error);
    }
}

BOOL AKPersistOwnedRecordingRecoveryJob(AKRecordingJobOwnership *owner, NSURL *local, NSURL *remote,
                                        NSURL *destination, AKRecordingJobPhase phase, NSError **error) {
    if (phase != AKRecordingJobPhaseCapturing && phase != AKRecordingJobPhaseFinalising) {
        RecordingPOSIXError(error, EINVAL);
        return NO;
    }
    return PersistRecordingManifest(owner, local, remote, destination,
        phase == AKRecordingJobPhaseCapturing ? @"capturing" : @"finalising", error);
}

static void RemoveOwnedRecordingDirectory(AKRecordingJobOwnership *owner) {
    if (![owner isCurrent]) return;
    // Atomically retire the discoverable name before recursively deleting it.
    // A recursive removal could otherwise unlink the lock before the tracks,
    // allowing another claimant to create a new lock inode during cleanup.
    NSURL *retired = [owner.directoryURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:
        [@".finished-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    if (rename(owner.directoryURL.fileSystemRepresentation, retired.fileSystemRepresentation) == 0)
        [NSFileManager.defaultManager removeItemAtURL:retired error:nil];
}

void AKFinishRecordingRecoveryJob(AKRecordingJobOwnership *owner, BOOL succeeded) {
    @synchronized (owner) {
        if (![owner isCurrent]) { [owner releaseClaim]; return; }
        NSMutableDictionary *manifest = [OwnedRecordingManifest(owner) mutableCopy] ?: [NSMutableDictionary dictionary];
        manifest[@"version"] = @2;
        manifest[@"state"] = succeeded ? @"completed" : @"failed";
        WriteOwnedRecordingManifest(owner, manifest, nil);
        if (succeeded) RemoveOwnedRecordingDirectory(owner);
        [owner releaseClaim];
    }
}

void AKDiscardRecordingRecoveryJob(AKRecordingJobOwnership *owner) {
    @synchronized (owner) {
        RemoveOwnedRecordingDirectory(owner);
        [owner releaseClaim];
    }
}

static NSURL *RecordingRecoveryRoot(void) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                         inDomains:NSUserDomainMask].firstObject;
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier ?: @"com.tlphn.Telephone";
    return [[support URLByAppendingPathComponent:identifier isDirectory:YES]
            URLByAppendingPathComponent:@"Recording Recovery" isDirectory:YES];
}

NSURL *AKCreateRecordingRecoveryDirectoryAtRoot(NSURL *root, NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDictionary *attributes = @{NSFilePosixPermissions: @0700};
    if (![manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:attributes error:error] ||
        ![manager setAttributes:attributes ofItemAtPath:root.path error:error]) return nil;
    NSURL *directory = [root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    if (![manager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:attributes error:error]) return nil;
    return directory;
}

NSURL *AKCreateRecordingRecoveryDirectory(NSError **error) {
    return AKCreateRecordingRecoveryDirectoryAtRoot(RecordingRecoveryRoot(), error);
}

BOOL AKPersistRecordingRecoveryJob(NSURL *directory, NSURL *local, NSURL *remote,
                                   NSURL *destination, NSError **error) {
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, error);
    if (!owner) return NO;
    BOOL persisted = PersistRecordingManifest(owner, local, remote, destination, nil, error);
    [owner releaseClaim];
    return persisted;
}

static NSDictionary *RecordingRecoveryJobForOwner(AKRecordingJobOwnership *owner) {
    @synchronized (owner) {
        if (![owner isCurrent]) return nil;
        NSDictionary *manifest = OwnedRecordingManifest(owner);
        if (IsCompletedRecordingManifest(manifest)) return nil;
        NSString *localName = manifest[@"local"];
        NSString *remoteName = manifest[@"remote"];
        // Malformed metadata must not strand a safe pair of conventional raw
        // tracks. Never follow a path or symlink supplied by the manifest.
        if (!ValidRecordingTrackName(localName) || !ValidRecordingTrackName(remoteName) ||
            [localName isEqualToString:remoteName] ||
            !OwnedTrackIsRegular(owner, localName, NO, nil) || !OwnedTrackIsRegular(owner, remoteName, NO, nil)) {
            localName = @"local.wav";
            remoteName = @"remote.wav";
        }
        if (!OwnedTrackIsRegular(owner, localName, NO, nil) || !OwnedTrackIsRegular(owner, remoteName, NO, nil)) return nil;
        NSString *destinationPath = [manifest[@"destination"] isKindOfClass:NSString.class] ? manifest[@"destination"] : nil;
        NSURL *destination = destinationPath.isAbsolutePath ? [NSURL fileURLWithPath:destinationPath] : nil;
        BOOL validDestination = RecordingDestinationIsOutsideDirectory(destination, owner.directoryURL);
        if (!validDestination) destination = [owner.directoryURL.URLByDeletingLastPathComponent
            URLByAppendingPathComponent:@"Recovered recording.wav"];
        struct stat info;
        if (fstat(owner.directoryDescriptor, &info) != 0) return nil;
        NSString *identity = [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev, (unsigned long long)info.st_ino];
        return @{@"directoryURL": owner.directoryURL,
                 @"localURL": [owner.directoryURL URLByAppendingPathComponent:localName],
                 @"remoteURL": [owner.directoryURL URLByAppendingPathComponent:remoteName],
                 @"destinationURL": destination, @"needsNewDestination": @(!validDestination), @"directoryIdentity": identity};
    }
}

NSArray<NSDictionary *> *AKRecordingRecoveryJobsAtRoot(NSURL *root) {
    NSArray *directories = [NSFileManager.defaultManager contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray *jobs = [NSMutableArray array];
    for (NSURL *directory in directories) {
        struct stat info;
        if (lstat(directory.fileSystemRepresentation, &info) != 0 || !S_ISDIR(info.st_mode)) continue;
        // A newly created capture directory has no pair of tracks yet. Do not
        // take its first claim away from capture admission while scanning.
        if ([NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:nil options:0 error:nil].count < 2) continue;
        AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil);
        if (!owner) continue;
        NSDictionary *job = RecordingRecoveryJobForOwner(owner);
        [owner releaseClaim];
        if (job) [jobs addObject:job];
    }
    return jobs;
}

NSArray<NSDictionary *> *AKPendingRecordingRecoveryJobs(void) {
    return AKRecordingRecoveryJobsAtRoot(RecordingRecoveryRoot());
}

void AKReportRecordingExportFailure(NSURL *directory, NSURL *destination, NSError *error) {
    NSMutableDictionary *info = [@{@"recoveryDirectoryURL": directory, @"destinationURL": destination} mutableCopy];
    info[@"error"] = error ?: [NSError errorWithDomain:@"com.tlphn.Telephone.recording" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"The recording could not be exported. Its captured audio has been kept for recovery."}];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:AKRecordingExportDidFailNotification object:nil userInfo:info];
    });
}

void AKRetryRecordingRecoveryJob(NSDictionary *job, NSURL *destination, void (^completion)(BOOL)) {
    // The dictionary is a UI snapshot, never authority to convert/delete files.
    // Acquire before reading tracks and retain this claim through main cleanup.
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(job[@"directoryURL"], nil);
    NSDictionary *current = owner ? RecordingRecoveryJobForOwner(owner) : nil;
    NSString *snapshotIdentity = job[@"directoryIdentity"];
    if (!current || (snapshotIdentity && ![snapshotIdentity isEqual:current[@"directoryIdentity"]])) {
        [owner releaseClaim];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
        return;
    }
    NSURL *directory = owner.directoryURL;
    NSURL *local = current[@"localURL"];
    NSURL *remote = current[@"remoteURL"];
    BOOL accessGranted = [destination startAccessingSecurityScopedResource];
    void (^finish)(BOOL) = ^(BOOL succeeded) {
        AKFinishRecordingRecoveryJob(owner, succeeded);
        if (!succeeded) AKReportRecordingExportFailure(directory, destination, nil);
        if (accessGranted) [destination stopAccessingSecurityScopedResource];
        if (completion) completion(succeeded);
    };
    NSError *error = nil;
    // A failed original export owns no successful output. Never silently erase a
    // different recording later created at its old destination.
    if ([NSFileManager.defaultManager fileExistsAtPath:destination.path] ||
        !AKPersistOwnedRecordingRecoveryJob(owner, local, remote, destination, AKRecordingJobPhaseFinalising, &error)) {
        AKFinishRecordingRecoveryJob(owner, NO);
        AKReportRecordingExportFailure(directory, destination, error ?: [NSError errorWithDomain:NSCocoaErrorDomain
             code:NSFileWriteFileExistsError userInfo:@{NSLocalizedDescriptionKey: @"Choose a new filename to recover this recording."}]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (accessGranted) [destination stopAccessingSecurityScopedResource];
            if (completion) completion(NO);
        });
        return;
    }
    AKMergeMonoRecordingsIntoStereoAsync(local, remote, destination, finish);
}

typedef NS_ENUM(NSUInteger, AKRecordingEncoder) {
    AKRecordingEncoderWave,
    AKRecordingEncoderMP3,
    AKRecordingEncoderOggOpus,
};

static AudioStreamBasicDescription FloatPCMFormat(Float64 sampleRate, UInt32 channels);
static AudioStreamBasicDescription Int16PCMFormat(Float64 sampleRate, UInt32 channels);
static BOOL RecordingEncoderForURL(NSURL *URL, AKRecordingEncoder *encoder);
static OSStatus OpenFinalizedRecordingTrack(NSURL *URL, ExtAudioFileRef *file);

NSURL *AKReserveRecordingURL(NSURL *directoryURL,
                             NSString *filenameStem,
                             NSString *extension,
                             NSError **error) {
    for (NSUInteger index = 1; index <= 9999; index++) {
        NSString *suffix = index == 1 ? @"" : [NSString stringWithFormat:@" (%lu)", (unsigned long)index];
        NSString *filename = [NSString stringWithFormat:@"%@%@.%@", filenameStem, suffix, extension];
        NSURL *candidate = [directoryURL URLByAppendingPathComponent:filename isDirectory:NO];
        int descriptor = open(candidate.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (descriptor >= 0) {
            if (close(descriptor) == 0) {
                return candidate;
            }
            int closeError = errno;
            unlink(candidate.fileSystemRepresentation);
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:closeError userInfo:nil];
            }
            return nil;
        }
        if (errno != EEXIST) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            }
            return nil;
        }
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EEXIST userInfo:nil];
    }
    return nil;
}

static dispatch_group_t RecordingFinalizations(void) {
    static dispatch_group_t group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ group = dispatch_group_create(); });
    return group;
}

void AKWaitForPendingRecordingFinalizations(dispatch_block_t completion) {
    dispatch_group_notify(RecordingFinalizations(), dispatch_get_main_queue(), completion);
}

void AKMergeMonoRecordingsIntoStereoAsync(NSURL *localURL,
                                          NSURL *remoteURL,
                                          NSURL *destinationURL,
                                          void (^completion)(BOOL succeeded)) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlphn.Telephone.recording-encoder", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(queue, ^{
        BOOL succeeded = AKMergeMonoRecordingsIntoStereo(localURL, remoteURL, destinationURL);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(succeeded);
            }
            // Leave after cleanup on the main queue, not just after encoding.
            dispatch_group_leave(RecordingFinalizations());
        });
    });
}

BOOL AKMergeMonoRecordingsIntoStereo(NSURL *localURL, NSURL *remoteURL, NSURL *destinationURL) {
    ExtAudioFileRef localFile = NULL;
    ExtAudioFileRef remoteFile = NULL;
    ExtAudioFileRef waveFile = NULL;
    OggOpusEnc *opusEncoder = NULL;
    lame_t lameEncoder = NULL;
    FILE *mp3File = NULL;
    Float32 *localSamples = NULL;
    Float32 *remoteSamples = NULL;
    Float32 *stereoSamples = NULL;
    unsigned char *mp3Bytes = NULL;
    OggOpusComments *opusComments = NULL;
    BOOL succeeded = NO;
    BOOL audioWritten = NO;
    AKRecordingEncoder encoder = AKRecordingEncoderWave;
    OSStatus status = noErr;
    int encoderStatus = 0;

    if (!RecordingEncoderForURL(destinationURL, &encoder)) {
        goto cleanup;
    }

    status = OpenFinalizedRecordingTrack(localURL, &localFile);
    if (status != noErr) {
        NSLog(@"Could not open local recording track (AudioToolbox error %d)", status);
        goto cleanup;
    }
    status = OpenFinalizedRecordingTrack(remoteURL, &remoteFile);
    if (status != noErr) {
        NSLog(@"Could not open remote recording track (AudioToolbox error %d)", status);
        goto cleanup;
    }

    AudioStreamBasicDescription sourceFormat = {0};
    AudioStreamBasicDescription remoteSourceFormat = {0};
    UInt32 propertySize = sizeof(sourceFormat);
    status = ExtAudioFileGetProperty(localFile, kExtAudioFileProperty_FileDataFormat, &propertySize, &sourceFormat);
    if (status != noErr || sourceFormat.mSampleRate <= 0 || sourceFormat.mChannelsPerFrame != 1) {
        NSLog(@"Could not read call recording format (AudioToolbox error %d)", status);
        goto cleanup;
    }
    propertySize = sizeof(remoteSourceFormat);
    status = ExtAudioFileGetProperty(remoteFile, kExtAudioFileProperty_FileDataFormat, &propertySize, &remoteSourceFormat);
    if (status != noErr || remoteSourceFormat.mSampleRate != sourceFormat.mSampleRate ||
        remoteSourceFormat.mChannelsPerFrame != 1) {
        NSLog(@"The local and remote call tracks have incompatible formats (AudioToolbox error %d)", status);
        goto cleanup;
    }

    AudioStreamBasicDescription monoClientFormat = FloatPCMFormat(sourceFormat.mSampleRate, 1);
    status = ExtAudioFileSetProperty(localFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(monoClientFormat),
                                     &monoClientFormat);
    if (status != noErr) {
        NSLog(@"Could not configure local recording track (AudioToolbox error %d)", status);
        goto cleanup;
    }
    status = ExtAudioFileSetProperty(remoteFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(monoClientFormat),
                                     &monoClientFormat);
    if (status != noErr) {
        NSLog(@"Could not configure remote recording track (AudioToolbox error %d)", status);
        goto cleanup;
    }

    if (encoder == AKRecordingEncoderWave) {
        AudioStreamBasicDescription fileFormat = Int16PCMFormat(sourceFormat.mSampleRate, 2);
        status = ExtAudioFileCreateWithURL((__bridge CFURLRef)destinationURL,
                                           kAudioFileWAVEType,
                                           &fileFormat,
                                           NULL,
                                           kAudioFileFlags_EraseFile,
                                           &waveFile);
        if (status != noErr) {
            NSLog(@"Could not create Source recording (AudioToolbox error %d)", status);
            goto cleanup;
        }
        AudioStreamBasicDescription stereoClientFormat = FloatPCMFormat(sourceFormat.mSampleRate, 2);
        status = ExtAudioFileSetProperty(waveFile,
                                         kExtAudioFileProperty_ClientDataFormat,
                                         sizeof(stereoClientFormat),
                                         &stereoClientFormat);
        if (status != noErr) {
            NSLog(@"Could not configure Source recording (AudioToolbox error %d)", status);
            goto cleanup;
        }
    } else if (encoder == AKRecordingEncoderMP3) {
        mp3File = fopen(destinationURL.fileSystemRepresentation, "wb");
        if (mp3File == NULL) {
            NSLog(@"Could not create MP3 call recording");
            goto cleanup;
        }
        lameEncoder = lame_init();
        if (lameEncoder == NULL) {
            NSLog(@"Could not initialize MP3 call recording encoder");
            goto cleanup;
        }
        // Independent stereo avoids blending the two callers together.
        lame_set_write_id3tag_automatic(lameEncoder, 0);
        if (lame_set_in_samplerate(lameEncoder, (int)sourceFormat.mSampleRate) < 0 ||
            lame_set_num_channels(lameEncoder, 2) < 0 ||
            lame_set_mode(lameEncoder, STEREO) < 0 ||
            lame_set_VBR(lameEncoder, vbr_off) < 0 ||
            lame_set_brate(lameEncoder, 64) < 0 ||
            lame_set_quality(lameEncoder, 2) < 0 ||
            lame_init_params(lameEncoder) < 0) {
            NSLog(@"Could not configure MP3 call recording encoder");
            goto cleanup;
        }
    } else {
        opusComments = ope_comments_create();
        if (opusComments == NULL) {
            NSLog(@"Could not create Ogg call recording metadata");
            goto cleanup;
        }
        opusEncoder = ope_encoder_create_file(destinationURL.fileSystemRepresentation,
                                              opusComments,
                                              (opus_int32)sourceFormat.mSampleRate,
                                              2,
                                              -1,
                                              &encoderStatus);
        if (opusEncoder == NULL || encoderStatus != OPE_OK) {
            NSLog(@"Could not create Ogg call recording (encoder error %d)", encoderStatus);
            goto cleanup;
        }
        // Two uncoupled Opus streams keep local strictly left and remote strictly right.
        const unsigned char channelMapping[2] = {0, 1};
        encoderStatus = ope_encoder_deferred_init_with_mapping(opusEncoder, 1, 2, 0, channelMapping);
        if (encoderStatus != OPE_OK) {
            NSLog(@"Could not configure Ogg call recording encoder (encoder error %d)", encoderStatus);
            goto cleanup;
        }
        encoderStatus = ope_encoder_ctl(opusEncoder, OPUS_SET_BITRATE(24000));
        if (encoderStatus == OPE_OK) encoderStatus = ope_encoder_ctl(opusEncoder, OPUS_SET_VBR(1));
        if (encoderStatus == OPE_OK) encoderStatus = ope_encoder_ctl(opusEncoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
        if (encoderStatus == OPE_OK) encoderStatus = ope_encoder_ctl(opusEncoder, OPUS_SET_COMPLEXITY(10));
        if (encoderStatus != OPE_OK) {
            NSLog(@"Could not configure Ogg call recording encoder (encoder error %d)", encoderStatus);
            goto cleanup;
        }
    }

    const UInt32 capacity = 4096;
    const int mp3ByteCapacity = (int)(capacity * 5 / 4 + 7200);
    localSamples = calloc(capacity, sizeof(Float32));
    remoteSamples = calloc(capacity, sizeof(Float32));
    stereoSamples = calloc(capacity * 2, sizeof(Float32));
    if (encoder == AKRecordingEncoderMP3) {
        mp3Bytes = malloc((size_t)mp3ByteCapacity);
    }
    if (localSamples == NULL || remoteSamples == NULL || stereoSamples == NULL ||
        (encoder == AKRecordingEncoderMP3 && mp3Bytes == NULL)) {
        NSLog(@"Could not allocate buffers for stereo call recording");
        goto cleanup;
    }

    while (YES) {
        memset(localSamples, 0, capacity * sizeof(Float32));
        memset(remoteSamples, 0, capacity * sizeof(Float32));
        UInt32 localFrames = capacity;
        UInt32 remoteFrames = capacity;
        AudioBufferList localBuffer = {1, {{1, capacity * sizeof(Float32), localSamples}}};
        AudioBufferList remoteBuffer = {1, {{1, capacity * sizeof(Float32), remoteSamples}}};

        status = ExtAudioFileRead(localFile, &localFrames, &localBuffer);
        if (status != noErr) {
            NSLog(@"Could not read local recording track (AudioToolbox error %d)", status);
            goto cleanup;
        }
        status = ExtAudioFileRead(remoteFile, &remoteFrames, &remoteBuffer);
        if (status != noErr) {
            NSLog(@"Could not read remote recording track (AudioToolbox error %d)", status);
            goto cleanup;
        }

        UInt32 frames = MAX(localFrames, remoteFrames);
        if (frames == 0) {
            break;
        }
        for (UInt32 frame = 0; frame < frames; frame++) {
            stereoSamples[frame * 2] = localSamples[frame];
            stereoSamples[frame * 2 + 1] = remoteSamples[frame];
        }

        if (encoder == AKRecordingEncoderWave) {
            AudioBufferList stereoBuffer = {1, {{2, frames * 2 * sizeof(Float32), stereoSamples}}};
            status = ExtAudioFileWrite(waveFile, frames, &stereoBuffer);
            if (status != noErr) {
                NSLog(@"Could not write Source recording (AudioToolbox error %d)", status);
                goto cleanup;
            }
        } else if (encoder == AKRecordingEncoderMP3) {
            int bytes = lame_encode_buffer_interleaved_ieee_float(lameEncoder,
                                                                   stereoSamples,
                                                                   (int)frames,
                                                                   mp3Bytes,
                                                                   mp3ByteCapacity);
            if (bytes < 0 || (bytes > 0 && fwrite(mp3Bytes, 1, (size_t)bytes, mp3File) != (size_t)bytes)) {
                NSLog(@"Could not write MP3 call recording (encoder error %d)", bytes);
                goto cleanup;
            }
        } else {
            encoderStatus = ope_encoder_write_float(opusEncoder, stereoSamples, (int)frames);
            if (encoderStatus != OPE_OK) {
                NSLog(@"Could not write Ogg call recording (encoder error %d)", encoderStatus);
                goto cleanup;
            }
        }
        audioWritten = YES;
    }

    if (encoder == AKRecordingEncoderMP3) {
        int bytes = lame_encode_flush(lameEncoder, mp3Bytes, mp3ByteCapacity);
        if (bytes < 0 || (bytes > 0 && fwrite(mp3Bytes, 1, (size_t)bytes, mp3File) != (size_t)bytes)) {
            NSLog(@"Could not finalize MP3 call recording (encoder error %d)", bytes);
            goto cleanup;
        }
        if (fflush(mp3File) != 0) {
            NSLog(@"Could not flush MP3 call recording");
            goto cleanup;
        }
    } else if (encoder == AKRecordingEncoderOggOpus) {
        encoderStatus = ope_encoder_drain(opusEncoder);
        if (encoderStatus != OPE_OK) {
            NSLog(@"Could not finalize Ogg call recording (encoder error %d)", encoderStatus);
            goto cleanup;
        }
    }

    succeeded = audioWritten;

cleanup:
    if (localFile != NULL) {
        ExtAudioFileDispose(localFile);
    }
    if (remoteFile != NULL) {
        ExtAudioFileDispose(remoteFile);
    }
    if (waveFile != NULL) {
        OSStatus disposeStatus = ExtAudioFileDispose(waveFile);
        if (disposeStatus != noErr) {
            NSLog(@"Could not finalize Source recording (AudioToolbox error %d)", disposeStatus);
            succeeded = NO;
        }
    }
    if (opusEncoder != NULL) {
        ope_encoder_destroy(opusEncoder);
    }
    if (opusComments != NULL) {
        ope_comments_destroy(opusComments);
    }
    if (lameEncoder != NULL) {
        lame_close(lameEncoder);
    }
    if (mp3File != NULL && fclose(mp3File) != 0) {
        succeeded = NO;
    }
    free(localSamples);
    free(remoteSamples);
    free(stereoSamples);
    free(mp3Bytes);
    if (!succeeded) {
        [NSFileManager.defaultManager removeItemAtURL:destinationURL error:nil];
    }
    return succeeded;
}

static AudioStreamBasicDescription FloatPCMFormat(Float64 sampleRate, UInt32 channels) {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mBytesPerPacket = sizeof(Float32) * channels;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(Float32) * channels;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = 8 * sizeof(Float32);
    return format;
}

static AudioStreamBasicDescription Int16PCMFormat(Float64 sampleRate, UInt32 channels) {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = sizeof(SInt16) * channels;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(SInt16) * channels;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = 8 * sizeof(SInt16);
    return format;
}

static OSStatus OpenFinalizedRecordingTrack(NSURL *URL, ExtAudioFileRef *file) {
    // pjsua_recorder_destroy() can return from a call-state callback just
    // before its WAV writer has made the finalized header visible to another
    // queue. The file is briefly reported as kAudioFileInvalidFileError even
    // though it becomes a valid WAV moments later. Conversion already runs on
    // a background queue, so retry this transient state without blocking UI.
    static const NSUInteger attemptCount = 41;
    static const useconds_t retryDelayMicroseconds = 50000;
    OSStatus status = noErr;
    for (NSUInteger attempt = 0; attempt < attemptCount; attempt++) {
        status = ExtAudioFileOpenURL((__bridge CFURLRef)URL, file);
        if (status == noErr ||
            (status != kAudioFileInvalidFileError && status != kAudioFileUnsupportedFileTypeError)) {
            return status;
        }
        if (attempt + 1 < attemptCount) {
            usleep(retryDelayMicroseconds);
        }
    }
    return status;
}

static BOOL RecordingEncoderForURL(NSURL *URL, AKRecordingEncoder *encoder) {
    NSString *extension = URL.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"wav"]) {
        *encoder = AKRecordingEncoderWave;
        return YES;
    }
    if ([extension isEqualToString:@"mp3"]) {
        *encoder = AKRecordingEncoderMP3;
        return YES;
    }
    if ([extension isEqualToString:@"ogg"]) {
        *encoder = AKRecordingEncoderOggOpus;
        return YES;
    }
    NSLog(@"Unsupported call recording extension: %@", extension);
    return NO;
}
