//
//  AKStereoRecording.m
//  Telephone
//

#import "AKStereoRecording.h"

#import <AudioToolbox/AudioToolbox.h>
#import <lame/lame.h>
#import <opus.h>
#import <opusenc.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *const AKRecordingExportDidFailNotification = @"AKRecordingExportDidFailNotification";
static NSString *const RecoveryManifestName = @"recovery.plist";
static NSString *const RecoveryLockName = @".owner.lock";
static char LegacyRecordingReportContextKey;
static char RecordingWorkerQueueKey;
static char RecordingReservationIdentityKey;

static AKRecordingAttachmentPublisher AttachmentPublisher;
static NSObject *AttachmentPublisherLock(void) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; }); return lock;
}
void AKSetRecordingAttachmentPublisher(AKRecordingAttachmentPublisher publisher) {
    @synchronized (AttachmentPublisherLock()) { AttachmentPublisher = [publisher copy]; }
}
static AKRecordingAttachmentPublisher CurrentAttachmentPublisher(void) {
    @synchronized (AttachmentPublisherLock()) { return [AttachmentPublisher copy]; }
}
BOOL AKRecordingAttachmentPublicationEnabled(void) { return CurrentAttachmentPublisher() != nil; }
static void QueueOwnedAttachmentState(AKRecordingJobOwnership *owner);
static void QueueRecordingAttachmentSnapshot(NSDictionary *snapshot, AKRecordingAttachmentPublisher publisher);
static NSDictionary *RecordingAttachmentSnapshot(NSDictionary *manifest);
static BOOL FinishJournalledExport(AKRecordingJobOwnership *owner, NSError **error);
static BOOL ExportOwnedRecording(AKRecordingJobOwnership *owner, NSURL *local, NSURL *remote,
    NSURL *destination, BOOL reserved, NSError **error);

static dispatch_group_t RecordingFinalizations(void) {
    static dispatch_group_t group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ group = dispatch_group_create(); });
    return group;
}

static dispatch_queue_t RecordingWorkerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlphn.Telephone.recording-encoder",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        dispatch_queue_set_specific(queue, &RecordingWorkerQueueKey, &RecordingWorkerQueueKey, NULL);
    });
    return queue;
}

static NSString *RecordingDirectoryIdentity(struct stat info);

static void RecordingPOSIXError(NSError **error, int code) {
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

@interface AKRecordingJobOwnership () {
    int _directoryDescriptor;
    int _lockDescriptor;
}
@property(nonatomic, readwrite, copy) NSURL *directoryURL;
@property(nonatomic, readonly) int directoryDescriptor;
@property(nonatomic, copy) NSString *lastManifestRevision;
@property(nonatomic, copy) AKRecordingAttachmentPublisher attachmentPublisher;
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
        _attachmentPublisher = CurrentAttachmentPublisher();
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

static NSDictionary *OwnedRecordingManifestWithError(AKRecordingJobOwnership *owner, NSError **error) {
    int descriptor = openat(owner.directoryDescriptor, RecoveryManifestName.fileSystemRepresentation,
                            O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (descriptor < 0) {
        // Missing/damaged metadata must not strand conventional safe raw tracks.
        if (errno != ENOENT && errno != ELOOP) RecordingPOSIXError(error, errno);
        return nil;
    }
    struct stat info;
    NSMutableData *data = [NSMutableData data];
    int readError = fstat(descriptor, &info) != 0 ? errno : 0;
    BOOL valid = !readError && S_ISREG(info.st_mode) && info.st_size <= 1024 * 1024;
    unsigned char bytes[4096];
    while (valid) {
        ssize_t count = read(descriptor, bytes, sizeof(bytes));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { valid = NO; readError = errno; }
        if (count <= 0) break;
        [data appendBytes:bytes length:(NSUInteger)count];
        if (data.length > 1024 * 1024) valid = NO;
    }
    close(descriptor);
    if (readError) RecordingPOSIXError(error, readError);
    id manifest = valid ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
    return [manifest isKindOfClass:NSDictionary.class] ? manifest : nil;
}

static NSDictionary *OwnedRecordingManifest(AKRecordingJobOwnership *owner) {
    return OwnedRecordingManifestWithError(owner, nil);
}

static BOOL WriteOwnedRecordingManifest(AKRecordingJobOwnership *owner, NSDictionary *manifest, NSError **error) {
    if (![owner isCurrent]) {
        RecordingPOSIXError(error, ESTALE);
        return NO;
    }
    NSMutableDictionary *published = [manifest mutableCopy];
    NSString *revision = NSUUID.UUID.UUIDString;
    published[@"revision"] = revision;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:published
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
    owner.lastManifestRevision = revision;
    if (fsync(owner.directoryDescriptor) != 0) { RecordingPOSIXError(error, errno); return NO; }
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
        // Rewrites preserve the exact owned identity and export proof. Legacy
        // jobs stay unlinked; directory names and filenames grant no identity.
        for (NSString *key in @[@"callIdentifier", @"segmentIdentifier", @"exportJournal", @"reservedOutputIdentity"])
            if (previous[key]) manifest[key] = previous[key];
        if ([state isEqualToString:@"capturing"] && !previous[@"reservedOutputIdentity"]) {
            NSDictionary *reservation = objc_getAssociatedObject(destination, &RecordingReservationIdentityKey);
            if (reservation) manifest[@"reservedOutputIdentity"] = reservation;
            else if (!owner.attachmentPublisher) {
                // Legacy standalone callers historically provide their own empty
                // file. App captures use only proof from the exclusive reservation.
                struct stat reserved;
                if (lstat(destination.fileSystemRepresentation, &reserved) == 0 && S_ISREG(reserved.st_mode) && reserved.st_size == 0)
                    manifest[@"reservedOutputIdentity"] = @{@"dev": [NSString stringWithFormat:@"%llu", (unsigned long long)reserved.st_dev],
                        @"ino": [NSString stringWithFormat:@"%llu", (unsigned long long)reserved.st_ino], @"size": @0};
            }
        }
        if (state) manifest[@"state"] = state;
        BOOL persisted = WriteOwnedRecordingManifest(owner, manifest, error);
        if (persisted) QueueOwnedAttachmentState(owner);
        return persisted;
    }
}

static BOOL ValidOpaqueRecordingIdentifier(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 && [value length] <= 1024;
}
BOOL AKSetOwnedRecordingIdentity(AKRecordingJobOwnership *owner, NSString *callIdentifier,
                                  NSString *segmentIdentifier, NSError **error) {
    @synchronized (owner) {
        if (![owner isCurrent] || !ValidOpaqueRecordingIdentifier(callIdentifier) || !ValidOpaqueRecordingIdentifier(segmentIdentifier)) {
            RecordingPOSIXError(error, EINVAL); return NO;
        }
        NSMutableDictionary *manifest = [OwnedRecordingManifest(owner) mutableCopy] ?: [NSMutableDictionary dictionary];
        if ((manifest[@"callIdentifier"] && ![manifest[@"callIdentifier"] isEqual:callIdentifier]) ||
            (manifest[@"segmentIdentifier"] && ![manifest[@"segmentIdentifier"] isEqual:segmentIdentifier])) {
            RecordingPOSIXError(error, ESTALE); return NO;
        }
        manifest[@"callIdentifier"] = [callIdentifier copy]; manifest[@"segmentIdentifier"] = [segmentIdentifier copy];
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

static BOOL RetireOwnedRecordingDirectory(AKRecordingJobOwnership *owner, NSString *prefix, NSError **error);

static void RemoveOwnedRecordingDirectory(AKRecordingJobOwnership *owner) {
    RetireOwnedRecordingDirectory(owner, @".finished-", nil);
}

void AKFinishRecordingRecoveryJob(AKRecordingJobOwnership *owner, BOOL succeeded) {
    @synchronized (owner) {
        if (![owner isCurrent]) { [owner releaseClaim]; return; }
        NSMutableDictionary *manifest = [OwnedRecordingManifest(owner) mutableCopy] ?: [NSMutableDictionary dictionary];
        // A linked export may be retired only after its durable catalogue
        // acknowledgement. Public legacy callers cannot bypass that boundary.
        if (succeeded && owner.attachmentPublisher && ValidOpaqueRecordingIdentifier(manifest[@"callIdentifier"]) &&
            ![manifest[@"attachmentPublished"] boolValue]) succeeded = NO;
        manifest[@"version"] = @2;
        manifest[@"state"] = succeeded ? @"completed" : @"failed";
        WriteOwnedRecordingManifest(owner, manifest, nil);
        if (succeeded) RemoveOwnedRecordingDirectory(owner);
        [owner releaseClaim];
    }
}

void AKDiscardRecordingRecoveryJob(AKRecordingJobOwnership *owner) {
    @synchronized (owner) {
        NSMutableDictionary *manifest = [OwnedRecordingManifest(owner) mutableCopy];
        if (manifest) {
            manifest[@"state"] = @"failed"; manifest[@"discarded"] = @YES; manifest[@"startFailed"] = @YES;
            manifest[@"reason"] = @"Recording did not start; no exported audio is available.";
            if (WriteOwnedRecordingManifest(owner, manifest, nil)) QueueOwnedAttachmentState(owner);
        }
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
    struct stat info;
    if (persisted && !objc_getAssociatedObject(directory, &LegacyRecordingReportContextKey) &&
        fstat(owner.directoryDescriptor, &info) == 0) {
        // Keep this compatibility report context on the caller's immutable URL,
        // rather than a process-wide path registry. Reusing a pathname or later
        // rewriting the manifest never grants an old report new authority.
        NSDictionary *context = @{@"directoryIdentity": RecordingDirectoryIdentity(info),
                                  @"revision": owner.lastManifestRevision};
        objc_setAssociatedObject(directory, &LegacyRecordingReportContextKey, context, OBJC_ASSOCIATION_RETAIN);
    }
    [owner releaseClaim];
    return persisted;
}

static NSString *RecordingDirectoryIdentity(struct stat info) {
    return [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev, (unsigned long long)info.st_ino];
}

static BOOL RecordingTrackStat(AKRecordingJobOwnership *owner, NSString *name, struct stat *info, NSError **error) {
    if (fstatat(owner.directoryDescriptor, name.fileSystemRepresentation, info, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno != ENOENT) RecordingPOSIXError(error, errno);
        return NO;
    }
    return S_ISREG(info->st_mode) && info->st_size >= 0;
}

static NSError *RecordedExportError(NSDictionary *manifest) {
    NSDictionary *record = [manifest[@"lastError"] isKindOfClass:NSDictionary.class] ? manifest[@"lastError"] : nil;
    NSString *domain = [record[@"domain"] isKindOfClass:NSString.class] ? record[@"domain"] : nil;
    NSNumber *code = [record[@"code"] isKindOfClass:NSNumber.class] ? record[@"code"] : nil;
    NSString *description = [record[@"description"] isKindOfClass:NSString.class] ? record[@"description"] : nil;
    if (!domain.length || !code || !description.length) return nil;
    return [NSError errorWithDomain:domain code:code.integerValue userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSDictionary *RecordingRecoveryJobForOwnerWithError(AKRecordingJobOwnership *owner, NSError **error) {
    @synchronized (owner) {
        if (![owner isCurrent]) { RecordingPOSIXError(error, ESTALE); return nil; }
        NSError *readError = nil;
        NSDictionary *manifest = OwnedRecordingManifestWithError(owner, &readError);
        if (readError) { if (error) *error = readError; return nil; }
        if (IsCompletedRecordingManifest(manifest)) return nil;
        NSString *localName = manifest[@"local"];
        NSString *remoteName = manifest[@"remote"];
        struct stat localInfo, remoteInfo;
        // Malformed metadata must not strand a safe pair of conventional raw
        // tracks. Never follow a path or symlink supplied by the manifest.
        if (!ValidRecordingTrackName(localName) || !ValidRecordingTrackName(remoteName) ||
            [localName isEqualToString:remoteName] ||
            !RecordingTrackStat(owner, localName, &localInfo, &readError) ||
            !RecordingTrackStat(owner, remoteName, &remoteInfo, &readError)) {
            if (readError) { if (error) *error = readError; return nil; }
            localName = @"local.wav";
            remoteName = @"remote.wav";
        }
        if (!RecordingTrackStat(owner, localName, &localInfo, &readError) ||
            !RecordingTrackStat(owner, remoteName, &remoteInfo, &readError)) {
            if (error && readError) *error = readError;
            return nil;
        }
        NSString *destinationPath = [manifest[@"destination"] isKindOfClass:NSString.class] ? manifest[@"destination"] : nil;
        NSURL *destination = destinationPath.isAbsolutePath ? [NSURL fileURLWithPath:destinationPath] : nil;
        BOOL validDestination = RecordingDestinationIsOutsideDirectory(destination, owner.directoryURL);
        if (!validDestination) destination = [owner.directoryURL.URLByDeletingLastPathComponent
            URLByAppendingPathComponent:@"Recovered recording.wav"];
        struct stat info;
        if (fstat(owner.directoryDescriptor, &info) != 0) { RecordingPOSIXError(error, errno); return nil; }
        NSDate *created = [manifest[@"created"] isKindOfClass:NSDate.class] ? manifest[@"created"] : nil;
        if (!created) {
            struct timespec timestamp = info.st_birthtimespec.tv_sec > 0 ? info.st_birthtimespec : info.st_mtimespec;
            created = [NSDate dateWithTimeIntervalSince1970:timestamp.tv_sec + timestamp.tv_nsec / 1e9];
        }
        NSString *phase = [manifest[@"state"] isKindOfClass:NSString.class] ? manifest[@"state"] : @"unknown";
        if (![@[@"capturing", @"finalising", @"failed"] containsObject:phase]) phase = @"unknown";
        NSError *lastError = RecordedExportError(manifest);
        NSString *errorDescription = lastError.localizedDescription ?: ([phase isEqualToString:@"failed"] ?
            @"The recording could not be exported. No detailed error was reported." :
            @"No export error was recorded; the recording may have been interrupted.");
        NSMutableDictionary *job = [@{@"directoryURL": owner.directoryURL,
                 @"localURL": [owner.directoryURL URLByAppendingPathComponent:localName],
                 @"remoteURL": [owner.directoryURL URLByAppendingPathComponent:remoteName],
                 @"destinationURL": destination, @"needsNewDestination": @(!validDestination),
                 @"directoryIdentity": RecordingDirectoryIdentity(info), @"created": created,
                 @"title": destination.lastPathComponent, @"phase": phase,
                 @"retainedRawBytes": @((unsigned long long)localInfo.st_size + (unsigned long long)remoteInfo.st_size),
                 @"lastErrorDescription": errorDescription} mutableCopy];
        if (lastError) job[@"lastError"] = lastError;
        for (NSString *key in @[@"callIdentifier", @"segmentIdentifier"])
            if (ValidOpaqueRecordingIdentifier(manifest[key])) job[key] = manifest[key];
        if ([manifest[@"exportJournal"] isKindOfClass:NSDictionary.class]) job[@"exportPendingLink"] = @YES;
        return job;
    }
}

static NSDictionary *RecordingRecoveryJobForOwner(AKRecordingJobOwnership *owner) {
    return RecordingRecoveryJobForOwnerWithError(owner, nil);
}

NSArray<NSDictionary *> *AKRecordingRecoveryJobsAtRootWithError(NSURL *root, NSError **error) {
    if (error) *error = nil;
    if (![root isKindOfClass:NSURL.class] || !root.isFileURL || !root.path.isAbsolutePath) {
        RecordingPOSIXError(error, EINVAL); return nil;
    }
    int rootDescriptor = open(root.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (rootDescriptor < 0) {
        if (errno == ENOENT) return @[];
        RecordingPOSIXError(error, errno); return nil;
    }
    // macOS commonly exposes /var through an ancestor alias. Reject a symlink
    // root above, but accept those ancestors only after matching the held root.
    NSURL *canonicalRoot = root.URLByResolvingSymlinksInPath.standardizedURL;
    struct stat heldRoot, currentRoot;
    if (fstat(rootDescriptor, &heldRoot) != 0 ||
        lstat(canonicalRoot.fileSystemRepresentation, &currentRoot) != 0 || !S_ISDIR(currentRoot.st_mode) ||
        heldRoot.st_dev != currentRoot.st_dev || heldRoot.st_ino != currentRoot.st_ino) {
        close(rootDescriptor); RecordingPOSIXError(error, ESTALE); return nil;
    }
    root = canonicalRoot;
    DIR *stream = fdopendir(rootDescriptor);
    if (!stream) { int code = errno; close(rootDescriptor); RecordingPOSIXError(error, code); return nil; }
    NSMutableArray *jobs = [NSMutableArray array];
    NSError *scanError = nil;
    struct dirent *entry;
    while (YES) {
        errno = 0;
        entry = readdir(stream);
        if (!entry) { if (errno) RecordingPOSIXError(&scanError, errno); break; }
        if (entry->d_name[0] == '.') continue;
        NSString *name = [NSFileManager.defaultManager stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
        NSURL *directory = [root URLByAppendingPathComponent:name isDirectory:YES];
        struct stat info;
        if (fstatat(rootDescriptor, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
            if (errno == ENOENT) continue;
            RecordingPOSIXError(&scanError, errno); break;
        }
        if (!S_ISDIR(info.st_mode)) continue;
        // A newly created capture directory has no pair of tracks yet. Do not
        // take its first claim away from capture admission while scanning.
        NSArray *contents = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:nil options:0 error:&scanError];
        if (!contents) {
            if ([scanError.domain isEqualToString:NSCocoaErrorDomain] && scanError.code == NSFileReadNoSuchFileError) { scanError = nil; continue; }
            break;
        }
        if (contents.count < 2) continue;
        AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, &scanError);
        if (!owner) {
            if ([scanError.domain isEqualToString:NSPOSIXErrorDomain] &&
                (scanError.code == EWOULDBLOCK || scanError.code == EAGAIN || scanError.code == ENOENT || scanError.code == ESTALE)) {
                scanError = nil; continue;
            }
            break;
        }
        struct stat claimedInfo;
        BOOL sameDirectory = fstat(owner.directoryDescriptor, &claimedInfo) == 0 &&
            info.st_dev == claimedInfo.st_dev && info.st_ino == claimedInfo.st_ino &&
            [owner.directoryURL isEqual:directory.standardizedURL];
        NSDictionary *job = sameDirectory ? RecordingRecoveryJobForOwnerWithError(owner, &scanError) : nil;
        [owner releaseClaim];
        if (scanError) break;
        if (job) [jobs addObject:job];
    }
    closedir(stream);
    if (scanError) { if (error) *error = scanError; return nil; }
    return [jobs sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSComparisonResult order = [left[@"created"] compare:right[@"created"]];
        return order == NSOrderedSame ? [left[@"directoryIdentity"] compare:right[@"directoryIdentity"] options:NSLiteralSearch] : order;
    }];
}

NSArray<NSDictionary *> *AKRecordingRecoveryJobsAtRoot(NSURL *root) {
    return AKRecordingRecoveryJobsAtRootWithError(root, nil) ?: @[];
}

NSArray<NSDictionary *> *AKPendingRecordingRecoveryJobsWithError(NSError **error) {
    return AKRecordingRecoveryJobsAtRootWithError(RecordingRecoveryRoot(), error);
}

NSArray<NSDictionary *> *AKPendingRecordingRecoveryJobs(void) {
    return AKPendingRecordingRecoveryJobsWithError(nil) ?: @[];
}

static BOOL RemoveRetiredRecordingDirectory(AKRecordingJobOwnership *owner, int parentDescriptor,
                                            NSString *retiredName, NSString *identity, NSError **error) {
    int duplicate = dup(owner.directoryDescriptor);
    if (duplicate < 0) { RecordingPOSIXError(error, errno); return NO; }
    DIR *stream = fdopendir(duplicate);
    if (!stream) { int code = errno; close(duplicate); RecordingPOSIXError(error, code); return NO; }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    int removeError = 0;
    while (YES) {
        errno = 0;
        struct dirent *entry = readdir(stream);
        if (!entry) { removeError = errno; break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        struct stat info;
        if (fstatat(owner.directoryDescriptor, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) { removeError = errno; break; }
        // A recovery job has flat files. Refuse unexpected nested directories
        // rather than recursively entering a moved-in job or mounted directory.
        if (S_ISDIR(info.st_mode)) { removeError = ENOTEMPTY; break; }
        NSString *name = [NSFileManager.defaultManager stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
        if (![name isEqualToString:RecoveryLockName]) [names addObject:name];
    }
    closedir(stream);
    if (!removeError) {
        // Retain the lock inode until every other entry has been unlinked.
        [names addObject:RecoveryLockName];
        for (NSString *name in names) {
            if (unlinkat(owner.directoryDescriptor, name.fileSystemRepresentation, 0) != 0) { removeError = errno; break; }
        }
    }
    struct stat retired;
    if (!removeError && (fstatat(parentDescriptor, retiredName.fileSystemRepresentation, &retired, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISDIR(retired.st_mode) || ![identity isEqualToString:RecordingDirectoryIdentity(retired)])) removeError = ESTALE;
    if (!removeError && unlinkat(parentDescriptor, retiredName.fileSystemRepresentation, AT_REMOVEDIR) != 0) removeError = errno;
    if (removeError) { RecordingPOSIXError(error, removeError); return NO; }
    return YES;
}

static BOOL RetireOwnedRecordingDirectory(AKRecordingJobOwnership *owner, NSString *prefix, NSError **error) {
    struct stat held;
    if (![owner isCurrent] || fstat(owner.directoryDescriptor, &held) != 0) {
        RecordingPOSIXError(error, ESTALE); return NO;
    }
    NSString *identity = RecordingDirectoryIdentity(held);
    NSURL *parent = owner.directoryURL.URLByDeletingLastPathComponent;
    int parentDescriptor = open(parent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (parentDescriptor < 0) { RecordingPOSIXError(error, errno); return NO; }
    NSString *name = owner.directoryURL.lastPathComponent;
    NSString *retiredName = [prefix stringByAppendingString:NSUUID.UUID.UUIDString];
    struct stat before, after;
    int retireError = 0;
    if (![owner isCurrent] ||
        fstatat(parentDescriptor, name.fileSystemRepresentation, &before, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISDIR(before.st_mode) || ![identity isEqualToString:RecordingDirectoryIdentity(before)]) retireError = ESTALE;
    if (!retireError && renameatx_np(parentDescriptor, name.fileSystemRepresentation,
        parentDescriptor, retiredName.fileSystemRepresentation, RENAME_EXCL) != 0) retireError = errno;
    if (!retireError && (fstatat(parentDescriptor, retiredName.fileSystemRepresentation, &after, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISDIR(after.st_mode) || ![identity isEqualToString:RecordingDirectoryIdentity(after)])) {
        // A name can change between validation and rename. Never remove the
        // moved replacement; restore it only if the original name remains free.
        renameatx_np(parentDescriptor, retiredName.fileSystemRepresentation,
            parentDescriptor, name.fileSystemRepresentation, RENAME_EXCL);
        retireError = ESTALE;
    }
    BOOL removed = NO;
    if (!retireError) {
        removed = RemoveRetiredRecordingDirectory(owner, parentDescriptor, retiredName, identity, error);
        if (!removed) {
            // Descriptor-relative cleanup never enters a replacement. Surviving
            // data is rediscoverable when the original name is still available.
            renameatx_np(parentDescriptor, retiredName.fileSystemRepresentation,
                parentDescriptor, name.fileSystemRepresentation, RENAME_EXCL);
        }
    } else RecordingPOSIXError(error, retireError);
    close(parentDescriptor);
    return removed;
}

BOOL AKDiscardPendingRecordingRecoveryJob(NSDictionary *job, NSError **error) {
    if (error) *error = nil;
    if (![job isKindOfClass:NSDictionary.class]) { RecordingPOSIXError(error, EINVAL); return NO; }
    NSURL *directory = [job[@"directoryURL"] isKindOfClass:NSURL.class] ? job[@"directoryURL"] : nil;
    NSString *identity = [job[@"directoryIdentity"] isKindOfClass:NSString.class] ? job[@"directoryIdentity"] : nil;
    struct stat original;
    if (!directory.isFileURL || !directory.path.isAbsolutePath || !identity.length) {
        RecordingPOSIXError(error, EINVAL); return NO;
    }
    if (lstat(directory.fileSystemRepresentation, &original) != 0) { RecordingPOSIXError(error, errno); return NO; }
    if (!S_ISDIR(original.st_mode) || ![identity isEqualToString:RecordingDirectoryIdentity(original)]) {
        RecordingPOSIXError(error, ESTALE); return NO;
    }
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, error);
    if (!owner) return NO;
    @synchronized (owner) {
        NSDictionary *current = RecordingRecoveryJobForOwnerWithError(owner, error);
        if (!current || ![owner.directoryURL isEqual:directory.standardizedURL] ||
            ![identity isEqualToString:current[@"directoryIdentity"]]) {
            [owner releaseClaim];
            if (!error || !*error) RecordingPOSIXError(error, ESTALE);
            return NO;
        }
        NSMutableDictionary *discarded = [RecordingAttachmentSnapshot(OwnedRecordingManifest(owner)) mutableCopy];
        BOOL removed = RetireOwnedRecordingDirectory(owner, @".discarded-", error);
        if (removed && discarded) {
            discarded[@"state"] = @"failed"; discarded[@"discarded"] = @YES;
            discarded[@"reason"] = @"The retained recovery audio was discarded. Any exported file was preserved.";
            QueueRecordingAttachmentSnapshot([discarded copy], owner.attachmentPublisher);
        }
        [owner releaseClaim];
        return removed;
    }
}

static NSDictionary *RecordingJobSnapshot(NSDictionary *job) {
    if (![job isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    // No caller-owned mutable dictionary/string is consulted by a later worker.
    for (NSString *key in @[@"directoryURL", @"directoryIdentity"]) {
        id value = job[key];
        if (([key isEqualToString:@"directoryURL"] && [value isKindOfClass:NSURL.class]) ||
            ([key isEqualToString:@"directoryIdentity"] && [value isKindOfClass:NSString.class])) snapshot[key] = [value copy];
    }
    return [snapshot copy];
}

static NSError *RecordingExportErrorSnapshot(NSError *error) {
    if (![error isKindOfClass:NSError.class]) return nil;
    NSString *description = error.localizedDescription, *domain = error.domain;
    if (!description.length || !domain.length) return nil;
    return [NSError errorWithDomain:[domain substringToIndex:MIN(domain.length, 1024)] code:error.code
        userInfo:@{NSLocalizedDescriptionKey: [description substringToIndex:MIN(description.length, 4096)]}];
}

static void RecordOwnedExportFailure(AKRecordingJobOwnership *owner, NSError *error) {
    @synchronized (owner) {
        if (![owner isCurrent]) return;
        NSDictionary *previous = OwnedRecordingManifest(owner);
        if (IsCompletedRecordingManifest(previous)) return;
        NSMutableDictionary *manifest = [previous mutableCopy] ?: [NSMutableDictionary dictionary];
        manifest[@"version"] = @2;
        manifest[@"state"] = @"failed";
        [manifest removeObjectForKey:@"lastError"];
        if (error) manifest[@"lastError"] = @{@"domain": error.domain, @"code": @(error.code),
                                                 @"description": error.localizedDescription};
        WriteOwnedRecordingManifest(owner, manifest, nil);
        QueueOwnedAttachmentState(owner);
    }
}

static void NotifyRecordingExportFailure(NSURL *directory, NSURL *destination, NSError *error) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (directory) info[@"recoveryDirectoryURL"] = directory;
    if (destination) info[@"destinationURL"] = destination;
    info[@"error"] = error ?: [NSError errorWithDomain:@"com.tlphn.Telephone.recording" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"The recording could not be exported. Its captured audio has been kept for recovery. No detailed error was reported."}];
    [NSNotificationCenter.defaultCenter postNotificationName:AKRecordingExportDidFailNotification object:nil userInfo:info];
}

void AKFinishRecordingRecoveryJobAsync(AKRecordingJobOwnership *owner, BOOL succeeded,
                                       NSURL *destination, NSError *error, dispatch_block_t completion) {
    NSURL *directory = [owner.directoryURL copy], *chosenDestination = [destination copy];
    NSError *failure = RecordingExportErrorSnapshot(error);
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(RecordingWorkerQueue(), ^{
        @synchronized (owner) {
            if (succeeded) AKFinishRecordingRecoveryJob(owner, YES);
            else {
                RecordOwnedExportFailure(owner, failure);
                [owner releaseClaim];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!succeeded && chosenDestination) NotifyRecordingExportFailure(directory, chosenDestination, failure);
            if (completion) completion();
            dispatch_group_leave(RecordingFinalizations());
        });
    });
}

void AKDiscardPendingRecordingRecoveryJobAsync(NSDictionary *job, void (^completion)(BOOL, NSError *)) {
    NSDictionary *snapshot = RecordingJobSnapshot(job);
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(RecordingWorkerQueue(), ^{
        NSError *error = nil;
        BOOL succeeded = AKDiscardPendingRecordingRecoveryJob(snapshot, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(succeeded, error);
            dispatch_group_leave(RecordingFinalizations());
        });
    });
}

void AKReportRecordingExportFailure(NSURL *directory, NSURL *destination, NSError *error) {
    NSURL *failedDirectory = [directory copy], *chosenDestination = [destination copy];
    NSError *failure = RecordingExportErrorSnapshot(error);
    NSDictionary *context = [objc_getAssociatedObject(directory, &LegacyRecordingReportContextKey) copy];
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(RecordingWorkerQueue(), ^{
        // An unbound legacy path is insufficient authority to mutate a job.
        // The retained owner's API above is the production finalization path.
        AKRecordingJobOwnership *owner = context ? AKClaimRecordingJob(failedDirectory, nil) : nil;
        if (owner) {
            @synchronized (owner) {
                struct stat info;
                NSDictionary *previous = OwnedRecordingManifest(owner);
                if ([owner isCurrent] && fstat(owner.directoryDescriptor, &info) == 0 &&
                    [context[@"directoryIdentity"] isEqualToString:RecordingDirectoryIdentity(info)] &&
                    [context[@"revision"] isEqual:previous[@"revision"]] &&
                    !IsCompletedRecordingManifest(previous) &&
                    ![@[@"capturing", @"finalising"] containsObject:previous[@"state"] ?: @""]) {
                    RecordOwnedExportFailure(owner, failure);
                }
                [owner releaseClaim];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NotifyRecordingExportFailure(failedDirectory, chosenDestination, failure);
            dispatch_group_leave(RecordingFinalizations());
        });
    });
}

static NSMutableSet<NSString *> *AdmittedRecordingRecoveryJobs(void) {
    static NSMutableSet<NSString *> *jobs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ jobs = [NSMutableSet set]; });
    return jobs;
}

static BOOL PublishRecoveredRecording(NSURL *staged, NSURL *destination, NSError **error) {
    int input = open(staged.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (input < 0) { RecordingPOSIXError(error, errno); return NO; }
    int output = open(destination.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (output < 0) { int code = errno; close(input); RecordingPOSIXError(error, code); return NO; }
    struct stat created;
    BOOL hasIdentity = fstat(output, &created) == 0;
    int copyError = hasIdentity ? 0 : errno;
    unsigned char bytes[64 * 1024];
    while (!copyError) {
        ssize_t count = read(input, bytes, sizeof(bytes));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { copyError = errno; break; }
        if (!count) break;
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = write(output, bytes + offset, (size_t)(count - offset));
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) { copyError = written < 0 ? errno : EIO; break; }
            offset += written;
        }
    }
    if (!copyError && fsync(output) != 0) copyError = errno;
    close(input);
    if (close(output) != 0 && !copyError) copyError = errno;
    if (copyError) {
        struct stat current;
        // Only the file this attempt exclusively created is eligible for
        // partial-output cleanup. Keep the encoded staging file and raw tracks.
        if (hasIdentity && lstat(destination.fileSystemRepresentation, &current) == 0 &&
            S_ISREG(current.st_mode) && created.st_dev == current.st_dev && created.st_ino == current.st_ino)
            unlink(destination.fileSystemRepresentation);
        RecordingPOSIXError(error, copyError);
        return NO;
    }
    return YES;
}

static NSDictionary *RecordingAttachmentSnapshot(NSDictionary *manifest) {
    if (!ValidOpaqueRecordingIdentifier(manifest[@"callIdentifier"]) || !ValidOpaqueRecordingIdentifier(manifest[@"segmentIdentifier"])) return nil;
    NSMutableDictionary *attachment = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"callIdentifier", @"segmentIdentifier", @"created", @"destination", @"state", @"discarded", @"startFailed", @"reason"])
        if (manifest[key]) attachment[key] = manifest[key];
    NSDictionary *journal = [manifest[@"exportJournal"] isKindOfClass:NSDictionary.class] ? manifest[@"exportJournal"] : nil;
    if (journal) {
        for (NSString *key in @[@"outputIdentity", @"outputBookmark", @"bookmarkIsDirectory"])
            if (journal[key]) attachment[key] = journal[key];
    }
    return [attachment copy];
}

static void QueueOwnedAttachmentState(AKRecordingJobOwnership *owner) {
    QueueRecordingAttachmentSnapshot(RecordingAttachmentSnapshot(OwnedRecordingManifest(owner)), owner.attachmentPublisher);
}
static void QueueRecordingAttachmentSnapshot(NSDictionary *snapshot, AKRecordingAttachmentPublisher publisher) {
    if (!publisher || !snapshot) return;
    if (dispatch_get_specific(&RecordingWorkerQueueKey)) {
        // Already inside an admitted worker operation. Publish before its
        // completion so restart refresh cannot race these state updates.
        publisher(snapshot, nil); return;
    }
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(RecordingWorkerQueue(), ^{
        publisher(snapshot, nil); // Raw manifest remains authoritative after a metadata failure.
        dispatch_group_leave(RecordingFinalizations());
    });
}

static NSDictionary *RecordingFileIdentity(int descriptor, BOOL hash, NSError **error) {
    struct stat before, after;
    if (fstat(descriptor, &before) != 0) { RecordingPOSIXError(error, errno); return nil; }
    if (!S_ISREG(before.st_mode) || before.st_size < 0) { RecordingPOSIXError(error, EINVAL); return nil; }
    NSMutableDictionary *identity = [@{@"dev": [NSString stringWithFormat:@"%llu", (unsigned long long)before.st_dev],
        @"ino": [NSString stringWithFormat:@"%llu", (unsigned long long)before.st_ino], @"size": @(before.st_size)} mutableCopy];
    if (hash) {
        if (lseek(descriptor, 0, SEEK_SET) < 0) { RecordingPOSIXError(error, errno); return nil; }
        CC_SHA256_CTX context; CC_SHA256_Init(&context);
        unsigned char bytes[64 * 1024];
        for (;;) {
            ssize_t count = read(descriptor, bytes, sizeof(bytes));
            if (count < 0 && errno == EINTR) continue;
            if (count < 0) { RecordingPOSIXError(error, errno); return nil; }
            if (!count) break;
            CC_SHA256_Update(&context, bytes, (CC_LONG)count);
        }
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &context);
        NSMutableString *hex = [NSMutableString stringWithCapacity:64];
        for (NSUInteger index = 0; index < sizeof(digest); index++) [hex appendFormat:@"%02x", digest[index]];
        identity[@"sha256"] = hex;
    }
    if (fstat(descriptor, &after) != 0 || before.st_dev != after.st_dev || before.st_ino != after.st_ino ||
        before.st_size != after.st_size || before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec ||
        before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec) { RecordingPOSIXError(error, ESTALE); return nil; }
    return [identity copy];
}

static BOOL RecordingIdentityMatches(NSDictionary *actual, NSDictionary *expected, BOOL content) {
    if (![actual isKindOfClass:NSDictionary.class] || ![expected isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *key in content ? @[@"dev", @"ino", @"size", @"sha256"] : @[@"dev", @"ino"])
        if (!actual[key] || ![actual[key] isEqual:expected[key]]) return NO;
    return YES;
}

static BOOL RecordingDestinationPathsEqual(NSString *left, NSString *right) {
    if (!left.isAbsolutePath || !right.isAbsolutePath) return NO;
    return [[NSURL fileURLWithPath:left].URLByResolvingSymlinksInPath.standardizedURL
        isEqual:[NSURL fileURLWithPath:right].URLByResolvingSymlinksInPath.standardizedURL];
}

static BOOL WriteOwnedExportJournal(AKRecordingJobOwnership *owner, NSDictionary *journal, NSError **error) {
    NSMutableDictionary *manifest = [OwnedRecordingManifest(owner) mutableCopy];
    if (!manifest) { RecordingPOSIXError(error, ESTALE); return NO; }
    manifest[@"exportJournal"] = journal;
    if ([journal[@"destination"] isKindOfClass:NSString.class] && [journal[@"destination"] isAbsolutePath])
        manifest[@"destination"] = journal[@"destination"];
    return WriteOwnedRecordingManifest(owner, manifest, error);
}

static BOOL SyncRecordingOutputParent(NSURL *destination, NSError **error) {
    int descriptor = open(destination.URLByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (descriptor < 0) { RecordingPOSIXError(error, errno); return NO; }
    int code = fsync(descriptor) != 0 ? errno : 0;
    close(descriptor);
    if (code) { RecordingPOSIXError(error, code); return NO; }
    return YES;
}

static BOOL FinishJournalledExport(AKRecordingJobOwnership *owner, NSError **error) {
    NSDictionary *manifest = OwnedRecordingManifest(owner);
    AKRecordingAttachmentPublisher publisher = owner.attachmentPublisher;
    if (!publisher || !RecordingAttachmentSnapshot(manifest)) return YES;
    NSDictionary *journal = [manifest[@"exportJournal"] isKindOfClass:NSDictionary.class] ? manifest[@"exportJournal"] : nil;
    NSDictionary *expected = [journal[@"outputIdentity"] isKindOfClass:NSDictionary.class] ? journal[@"outputIdentity"] : nil;
    NSString *destinationPath = [journal[@"destination"] isKindOfClass:NSString.class] ? journal[@"destination"] : nil;
    if (![@[@"publishing", @"ready"] containsObject:journal[@"phase"] ?: @""] || !destinationPath.isAbsolutePath || !expected[@"sha256"]) {
        RecordingPOSIXError(error, EINVAL); return NO;
    }
    NSURL *destination = [NSURL fileURLWithPath:destinationPath];
    BOOL access = NO;
    NSData *bookmark = [journal[@"outputBookmark"] isKindOfClass:NSData.class] ? journal[@"outputBookmark"] : nil;
    if (bookmark) {
        BOOL stale = NO;
        NSURL *resolved = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI
            relativeToURL:nil bookmarkDataIsStale:&stale error:error];
        if (!resolved) return NO;
        destination = resolved;
        access = [destination startAccessingSecurityScopedResource];
    }
    int descriptor = open(destination.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    NSDictionary *actual = descriptor >= 0 ? RecordingFileIdentity(descriptor, YES, error) : nil;
    if (descriptor < 0) RecordingPOSIXError(error, errno);
    if (descriptor >= 0 && actual && fsync(descriptor) != 0) { RecordingPOSIXError(error, errno); actual = nil; }
    if (descriptor >= 0) close(descriptor);
    BOOL succeeded = RecordingIdentityMatches(actual, expected, YES);
    if (succeeded) succeeded = SyncRecordingOutputParent(destination, error);
    if (!succeeded && (!error || !*error)) RecordingPOSIXError(error, ESTALE);
    if (succeeded) {
        // The publishing journal was committed before any output bytes. A
        // completed inode+length+digest also repairs a crash before ready write.
        NSMutableDictionary *ready = [journal mutableCopy]; ready[@"phase"] = @"ready";
        ready[@"destination"] = destination.path;
        NSData *freshBookmark = [destination bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
            includingResourceValuesForKeys:nil relativeToURL:nil error:error];
        if (!freshBookmark) succeeded = NO;
        else {
            ready[@"outputBookmark"] = freshBookmark; ready[@"bookmarkIsDirectory"] = @NO;
            succeeded = WriteOwnedExportJournal(owner, ready, error);
        }
        if (succeeded) {
            NSMutableDictionary *attachment = [RecordingAttachmentSnapshot(OwnedRecordingManifest(owner)) mutableCopy];
            attachment[@"state"] = @"available"; attachment[@"destination"] = destination.path;
            succeeded = publisher([attachment copy], error);
            if (!succeeded && (!error || !*error)) {
                if (error) *error = [NSError errorWithDomain:@"com.tlphn.Telephone.recording" code:2
                    userInfo:@{NSLocalizedDescriptionKey: @"The audio was exported, but its history link could not be saved. The audio and recovery tracks have been kept."}];
            }
            if (succeeded) {
                NSMutableDictionary *linked = [OwnedRecordingManifest(owner) mutableCopy];
                linked[@"attachmentPublished"] = @YES;
                // Failure here also retains raw: restart publication is idempotent.
                succeeded = WriteOwnedRecordingManifest(owner, linked, error);
            }
        }
    }
    if (access) [destination stopAccessingSecurityScopedResource];
    return succeeded;
}

static BOOL ExportOwnedRecording(AKRecordingJobOwnership *owner, NSURL *local, NSURL *remote,
    NSURL *destination, BOOL reserved, NSError **error) {
    NSDictionary *original = OwnedRecordingManifest(owner);
    if ([original[@"exportJournal"] isKindOfClass:NSDictionary.class] &&
        RecordingDestinationPathsEqual(original[@"exportJournal"][@"destination"], destination.path)) {
        // Retry at the recorded destination is metadata-only. Save Elsewhere
        // is a distinct request and must create the newly selected output.
        return FinishJournalledExport(owner, error);
    }
    NSString *name = [[@".export-" stringByAppendingString:NSUUID.UUID.UUIDString] stringByAppendingPathExtension:destination.pathExtension];
    NSURL *stage = [owner.directoryURL URLByAppendingPathComponent:name];
    if (!AKMergeMonoRecordingsIntoStereo(local, remote, stage)) {
        if (error) *error = [NSError errorWithDomain:@"com.tlphn.Telephone.recording" code:3
            userInfo:@{NSLocalizedDescriptionKey: @"The captured audio could not be encoded. Its raw tracks have been kept."}];
        return NO;
    }
    int input = openat(owner.directoryDescriptor, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (input < 0) { RecordingPOSIXError(error, errno); return NO; }
    NSDictionary *stageIdentity = RecordingFileIdentity(input, YES, error);
    if (!stageIdentity || [stageIdentity[@"size"] unsignedLongLongValue] == 0 || fsync(input) != 0) {
        if (stageIdentity && (!error || !*error)) RecordingPOSIXError(error, errno ?: EIO); close(input); return NO;
    }
    // Record the immutable stage before claiming the output. A crash at any
    // later point retains both raw audio and this complete encoded source.
    NSMutableDictionary *journal = [@{@"version": @1, @"phase": @"prepared", @"stage": name,
        @"stageIdentity": stageIdentity, @"destination": destination.path} mutableCopy];
    if (!WriteOwnedExportJournal(owner, journal, error)) { close(input); return NO; }
    int flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK;
    int output = open(destination.fileSystemRepresentation, flags | (reserved ? 0 : O_CREAT | O_EXCL), 0600);
    if (output < 0) { int code = errno; close(input); RecordingPOSIXError(error, code); return NO; }
    NSDictionary *outputIdentity = RecordingFileIdentity(output, NO, error);
    BOOL valid = outputIdentity && [outputIdentity[@"size"] unsignedLongLongValue] == 0;
    if (reserved) valid = valid && RecordingIdentityMatches(outputIdentity, original[@"reservedOutputIdentity"], NO);
    if (!valid) { close(input); close(output); if (!error || !*error) RecordingPOSIXError(error, ESTALE); return NO; }
    NSMutableDictionary *proof = [outputIdentity mutableCopy];
    proof[@"size"] = stageIdentity[@"size"]; proof[@"sha256"] = stageIdentity[@"sha256"];
    journal[@"outputIdentity"] = proof; journal[@"phase"] = @"publishing";
    NSData *bookmark = [destination bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:error];
    if (bookmark) { journal[@"outputBookmark"] = bookmark; journal[@"bookmarkIsDirectory"] = @NO; }
    // This identity+expected content is durable BEFORE the first output byte.
    // A crash after exclusive create but before this write leaves only an empty
    // unproved reservation, which is never overwritten or called available.
    if (!bookmark || !WriteOwnedExportJournal(owner, journal, error)) { close(input); close(output); return NO; }
    int copyError = lseek(input, 0, SEEK_SET) < 0 ? errno : 0;
    unsigned char bytes[64 * 1024];
    while (!copyError) {
        ssize_t count = read(input, bytes, sizeof(bytes));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { copyError = errno; break; }
        if (!count) break;
        for (ssize_t offset = 0; offset < count;) {
            ssize_t written = write(output, bytes + offset, (size_t)(count - offset));
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) { copyError = written < 0 ? errno : EIO; break; }
            offset += written;
        }
    }
    if (!copyError && fsync(output) != 0) copyError = errno;
    close(input); if (close(output) != 0 && !copyError) copyError = errno;
    if (copyError) { RecordingPOSIXError(error, copyError); return NO; }
    if (!SyncRecordingOutputParent(destination, error)) return NO;
    journal[@"phase"] = @"ready";
    if (!WriteOwnedExportJournal(owner, journal, error)) return NO;
    return FinishJournalledExport(owner, error);
}

void AKFinalizeOwnedRecordingAsync(AKRecordingJobOwnership *owner, NSURL *local, NSURL *remote,
    NSURL *destination, void (^completion)(BOOL)) {
    NSURL *capturedLocal = [local copy], *capturedRemote = [remote copy], *capturedDestination = [destination copy];
    if (!owner.attachmentPublisher) owner.attachmentPublisher = CurrentAttachmentPublisher();
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(RecordingWorkerQueue(), ^{
        NSError *error = nil;
        BOOL succeeded = ExportOwnedRecording(owner, capturedLocal, capturedRemote, capturedDestination, YES, &error);
        if (succeeded) AKFinishRecordingRecoveryJob(owner, YES);
        else { RecordOwnedExportFailure(owner, error); [owner releaseClaim]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!succeeded) NotifyRecordingExportFailure(owner.directoryURL, capturedDestination, error);
            if (completion) completion(succeeded);
            dispatch_group_leave(RecordingFinalizations());
        });
    });
}

void AKReconcilePendingRecordingAttachmentsAtRoot(NSURL *root, void (^completion)(BOOL, NSError *)) {
    NSURL *capturedRoot = [root copy];
    AKRecordingAttachmentPublisher admittedPublisher = CurrentAttachmentPublisher();
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(RecordingWorkerQueue(), ^{
        NSError *error = nil;
        BOOL succeeded = YES;
        // Enumerate manifests independently of raw-track discovery: a complete
        // exported journal can still repair metadata after external raw loss.
        int rootDescriptor = admittedPublisher ? open(capturedRoot.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) : -1;
        if (!admittedPublisher) errno = ENOENT;
        DIR *entries = rootDescriptor >= 0 ? fdopendir(rootDescriptor) : NULL;
        if (!entries && errno != ENOENT) { RecordingPOSIXError(&error, errno); succeeded = NO; }
        if (!entries && rootDescriptor >= 0) close(rootDescriptor);
        if (entries) {
            struct dirent *entry;
            for (;;) {
                errno = 0; entry = readdir(entries);
                if (!entry) {
                    if (errno) { RecordingPOSIXError(&error, errno); succeeded = NO; }
                    break;
                }
                if (entry->d_name[0] == '.') continue;
                struct stat named;
                if (fstatat(rootDescriptor, entry->d_name, &named, AT_SYMLINK_NOFOLLOW) != 0 || !S_ISDIR(named.st_mode)) continue;
                NSString *name = [NSFileManager.defaultManager stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
                if (!name.length) continue;
                NSError *claimError = nil;
                AKRecordingJobOwnership *owner = AKClaimRecordingJob([capturedRoot URLByAppendingPathComponent:name isDirectory:YES], &claimError);
                if (!owner && claimError && claimError.code != EWOULDBLOCK && claimError.code != EAGAIN &&
                    claimError.code != ENOENT && claimError.code != ESTALE) {
                    succeeded = NO; error = error ?: claimError;
                }
                if (owner) owner.attachmentPublisher = admittedPublisher;
                struct stat held;
                BOOL current = owner && fstat(owner.directoryDescriptor, &held) == 0 &&
                    held.st_dev == named.st_dev && held.st_ino == named.st_ino;
                NSError *manifestError = nil;
                NSDictionary *manifest = current ? OwnedRecordingManifestWithError(owner, &manifestError) : nil;
                if (!manifest && !manifestError && current) {
                    struct stat metadata;
                    if (fstatat(owner.directoryDescriptor, RecoveryManifestName.fileSystemRepresentation, &metadata, AT_SYMLINK_NOFOLLOW) == 0)
                        manifestError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError
                            userInfo:@{NSLocalizedDescriptionKey: @"Recording recovery metadata is damaged. Its retained files were left untouched."}];
                }
                if (manifestError) { succeeded = NO; error = error ?: manifestError; }
                if (RecordingAttachmentSnapshot(manifest) && !IsCompletedRecordingManifest(manifest)) {
                    NSError *jobError = nil;
                    if ([manifest[@"exportJournal"] isKindOfClass:NSDictionary.class]) {
                        if (FinishJournalledExport(owner, &jobError)) AKFinishRecordingRecoveryJob(owner, YES);
                        else { succeeded = NO; error = error ?: jobError; RecordOwnedExportFailure(owner, jobError); }
                    } else {
                        // A claimable capture/finalisation survived its process.
                        // It is recovery work, never an active recording now.
                        if ([@[@"capturing", @"finalising"] containsObject:manifest[@"state"] ?: @""])
                            RecordOwnedExportFailure(owner, nil);
                        else QueueOwnedAttachmentState(owner);
                    }
                }
                [owner releaseClaim];
            }
            closedir(entries);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(succeeded, error);
            dispatch_group_leave(RecordingFinalizations());
        });
    });
}
void AKReconcilePendingRecordingAttachments(void (^completion)(BOOL, NSError *)) {
    AKReconcilePendingRecordingAttachmentsAtRoot(RecordingRecoveryRoot(), completion);
}

void AKRetryRecordingRecoveryJob(NSDictionary *job, NSURL *destination, void (^completion)(BOOL)) {
    AKRecordingAttachmentPublisher admittedPublisher = CurrentAttachmentPublisher();
    NSDictionary *snapshot = RecordingJobSnapshot(job);
    NSURL *chosenDestination = [destination copy];
    NSString *identity = snapshot[@"directoryIdentity"];
    NSURL *directory = snapshot[@"directoryURL"];
    NSString *admission = directory && identity.length ? [NSString stringWithFormat:@"%@|%@", directory.absoluteString, identity] : nil;
    NSMutableSet *admitted = AdmittedRecordingRecoveryJobs();
    __block BOOL duplicate = NO;
    @synchronized (admitted) {
        duplicate = !admission || [admitted containsObject:admission];
        if (!duplicate) [admitted addObject:admission];
    }
    // Admission precedes dispatch, including the asynchronous rejection path.
    dispatch_group_enter(RecordingFinalizations());
    if (duplicate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO);
            dispatch_group_leave(RecordingFinalizations());
        });
        return;
    }
    dispatch_async(RecordingWorkerQueue(), ^{
        // The dictionary is a presentation snapshot. Only the claimed current
        // manifest selects tracks, and the selected inode must still match.
        AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil);
        if (owner) owner.attachmentPublisher = admittedPublisher;
        NSDictionary *current = owner ? RecordingRecoveryJobForOwner(owner) : nil;
        BOOL eligible = current && [identity isEqualToString:current[@"directoryIdentity"]] &&
            [owner.directoryURL isEqual:directory.standardizedURL];
        BOOL accessGranted = NO, succeeded = NO, attempted = NO;
        NSError *error = nil;
        if (eligible) {
            attempted = YES;
            accessGranted = [chosenDestination startAccessingSecurityScopedResource];
            // Preflight, manifest write and conversion share one serial block.
            // Two admitted jobs cannot both pass an absent destination check.
            NSDictionary *manifest = OwnedRecordingManifest(owner);
            BOOL linked = owner.attachmentPublisher && RecordingAttachmentSnapshot(manifest);
            BOOL repairing = linked && [manifest[@"exportJournal"] isKindOfClass:NSDictionary.class] &&
                RecordingDestinationPathsEqual(manifest[@"exportJournal"][@"destination"], chosenDestination.path);
            BOOL exists = chosenDestination && [NSFileManager.defaultManager fileExistsAtPath:chosenDestination.path];
            if (repairing) {
                succeeded = FinishJournalledExport(owner, &error);
            } else if (exists) {
                error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError
                    userInfo:@{NSLocalizedDescriptionKey: @"Choose a new filename to recover this recording."}];
            } else if (AKPersistOwnedRecordingRecoveryJob(owner, current[@"localURL"], current[@"remoteURL"],
                                                          chosenDestination, AKRecordingJobPhaseFinalising, &error)) {
                error = nil;
                if (linked) succeeded = ExportOwnedRecording(owner, current[@"localURL"], current[@"remoteURL"], chosenDestination, NO, &error);
                else {
                    NSString *stagedName = [[@".export-" stringByAppendingString:NSUUID.UUID.UUIDString]
                        stringByAppendingPathExtension:chosenDestination.pathExtension];
                    NSURL *staged = [owner.directoryURL URLByAppendingPathComponent:stagedName];
                    if (AKMergeMonoRecordingsIntoStereo(current[@"localURL"], current[@"remoteURL"], staged))
                        succeeded = PublishRecoveredRecording(staged, chosenDestination, &error);
                }
            }
            if (succeeded) AKFinishRecordingRecoveryJob(owner, YES);
            else RecordOwnedExportFailure(owner, error);
        }
        [owner releaseClaim];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (attempted && !succeeded) NotifyRecordingExportFailure(directory, chosenDestination, error);
            if (accessGranted) [chosenDestination stopAccessingSecurityScopedResource];
            @synchronized (admitted) { [admitted removeObject:admission]; }
            if (completion) completion(succeeded);
            dispatch_group_leave(RecordingFinalizations());
        });
    });
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
            struct stat reserved;
            BOOL identified = fstat(descriptor, &reserved) == 0;
            int identityError = identified ? 0 : errno;
            if (close(descriptor) == 0 && identified) {
                NSDictionary *proof = @{@"dev": [NSString stringWithFormat:@"%llu", (unsigned long long)reserved.st_dev],
                    @"ino": [NSString stringWithFormat:@"%llu", (unsigned long long)reserved.st_ino], @"size": @0};
                objc_setAssociatedObject(candidate, &RecordingReservationIdentityKey, proof, OBJC_ASSOCIATION_COPY_NONATOMIC);
                return candidate;
            }
            int closeError = identityError ?: errno;
            struct stat named;
            if (identified && lstat(candidate.fileSystemRepresentation, &named) == 0 && S_ISREG(named.st_mode) &&
                named.st_dev == reserved.st_dev && named.st_ino == reserved.st_ino) unlink(candidate.fileSystemRepresentation);
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

void AKRemoveUnusedRecordingReservation(NSURL *URL) {
    if (!URL.isFileURL) return;
    NSDictionary *expected = objc_getAssociatedObject(URL, &RecordingReservationIdentityKey);
    if (!expected && CurrentAttachmentPublisher()) return;
    int descriptor = open(URL.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (descriptor < 0) return;
    NSDictionary *actual = RecordingFileIdentity(descriptor, NO, nil);
    struct stat named, held;
    BOOL current = actual && [actual[@"size"] unsignedLongLongValue] == 0 &&
        (!expected || RecordingIdentityMatches(actual, expected, NO)) && fstat(descriptor, &held) == 0 &&
        lstat(URL.fileSystemRepresentation, &named) == 0 && S_ISREG(named.st_mode) &&
        named.st_dev == held.st_dev && named.st_ino == held.st_ino;
    if (current) unlink(URL.fileSystemRepresentation);
    close(descriptor);
}

void AKWaitForPendingRecordingFinalizations(dispatch_block_t completion) {
    dispatch_group_notify(RecordingFinalizations(), dispatch_get_main_queue(), completion);
}

void AKMergeMonoRecordingsIntoStereoAsync(NSURL *localURL,
                                          NSURL *remoteURL,
                                          NSURL *destinationURL,
                                          void (^completion)(BOOL succeeded)) {
    dispatch_group_enter(RecordingFinalizations());
    dispatch_async(RecordingWorkerQueue(), ^{
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
