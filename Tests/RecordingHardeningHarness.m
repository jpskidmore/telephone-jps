#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#import "AKStereoRecording.h"

#include <math.h>
#include <unistd.h>
#import <objc/runtime.h>

// Redirect only the two NSURL scope-token boundaries while the scratch retry
// cases run. The actual file conversion stays real; no sandbox grant is requested.
static NSUInteger ScopeStarts, ScopeStops;
static BOOL ScopeGrant;
static NSString *ScopeBlockedTarget;
static dispatch_semaphore_t ScopeBlockedEntered, ScopeBlockedRelease;
static BOOL ScopeStart(NSURL *URL, SEL selector) {
    ScopeStarts++;
    if ([URL.absoluteString isEqual:ScopeBlockedTarget]) {
        dispatch_semaphore_signal(ScopeBlockedEntered);
        dispatch_semaphore_wait(ScopeBlockedRelease, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
    return ScopeGrant;
}
static void ScopeStop(NSURL *URL, SEL selector) { ScopeStops++; }

static AudioStreamBasicDescription FloatPCM(Float64 rate, UInt32 channels) {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mBytesPerPacket = sizeof(Float32) * channels;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(Float32) * channels;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = 8 * sizeof(Float32);
    return format;
}

static AudioStreamBasicDescription Int16PCM(Float64 rate, UInt32 channels) {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = sizeof(SInt16) * channels;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(SInt16) * channels;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = 8 * sizeof(SInt16);
    return format;
}

static BOOL WriteTrack(NSURL *URL, Float64 rate, BOOL toneFirst) {
    AudioStreamBasicDescription fileFormat = Int16PCM(rate, 1);
    ExtAudioFileRef file = NULL;
    OSStatus status = ExtAudioFileCreateWithURL((__bridge CFURLRef)URL, kAudioFileWAVEType,
                                                &fileFormat, NULL, kAudioFileFlags_EraseFile, &file);
    if (status != noErr) return NO;
    AudioStreamBasicDescription clientFormat = FloatPCM(rate, 1);
    status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(clientFormat), &clientFormat);
    UInt32 frames = (UInt32)(rate * 2);
    Float32 *samples = calloc(frames, sizeof(Float32));
    for (UInt32 frame = 0; frame < frames; frame++) {
        BOOL active = toneFirst ? frame < rate : frame >= rate;
        if (active) samples[frame] = 0.6f * sinf(2.0f * (float)M_PI * 440.0f * frame / rate);
    }
    AudioBufferList buffer = {1, {{1, frames * sizeof(Float32), samples}}};
    if (status == noErr) status = ExtAudioFileWrite(file, frames, &buffer);
    free(samples);
    OSStatus disposeStatus = ExtAudioFileDispose(file);
    return status == noErr && disposeStatus == noErr;
}

static BOOL HasPrefix(NSURL *URL, const char *prefix, NSUInteger length) {
    NSData *data = [NSData dataWithContentsOfURL:URL];
    return data.length >= length && memcmp(data.bytes, prefix, length) == 0;
}

static BOOL CheckWaveChannels(NSURL *URL) {
    ExtAudioFileRef file = NULL;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)URL, &file) != noErr) return NO;
    AudioStreamBasicDescription clientFormat = FloatPCM(16000, 2);
    if (ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                sizeof(clientFormat), &clientFormat) != noErr) return NO;
    Float32 samples[4096 * 2];
    double energy[4] = {0};
    UInt64 totalFrames = 0;
    OSStatus status = noErr;
    while (status == noErr) {
        UInt32 frames = 4096;
        AudioBufferList buffer = {1, {{2, sizeof(samples), samples}}};
        status = ExtAudioFileRead(file, &frames, &buffer);
        if (frames == 0) break;
        for (UInt32 frame = 0; frame < frames; frame++) {
            NSUInteger segment = totalFrames + frame < 16000 ? 0 : 1;
            energy[segment * 2] += samples[frame * 2] * samples[frame * 2];
            energy[segment * 2 + 1] += samples[frame * 2 + 1] * samples[frame * 2 + 1];
        }
        totalFrames += frames;
    }
    ExtAudioFileDispose(file);
    return status == noErr && totalFrames >= 31500 &&
           energy[0] > energy[1] * 25 && energy[3] > energy[2] * 25;
}

static NSUInteger OwnershipChecks;
#define REQUIRE_OWNERSHIP(condition) do { \
    OwnershipChecks++; \
    if (!(condition)) { fprintf(stderr, "Recording ownership failed at line %d: %s\n", __LINE__, #condition); return NO; } \
} while (0)

static BOOL SpinUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}

static NSDictionary *ReadManifest(NSURL *directory) {
    NSData *data = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"recovery.plist"]];
    return data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
}

static BOOL WriteManifest(NSURL *directory, NSDictionary *manifest) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:manifest
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return [data writeToURL:[directory URLByAppendingPathComponent:@"recovery.plist"] atomically:YES];
}

static BOOL WriteJobTracks(NSURL *directory) {
    return WriteTrack([directory URLByAppendingPathComponent:@"local.wav"], 16000, YES) &&
        WriteTrack([directory URLByAppendingPathComponent:@"remote.wav"], 16000, NO);
}

static BOOL RunOwnershipCases(NSURL *scratch, NSURL *executable) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *root = [scratch URLByAppendingPathComponent:@"Owned recovery" isDirectory:YES];
    NSURL *directory = AKCreateRecordingRecoveryDirectoryAtRoot(root, nil);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    REQUIRE_OWNERSHIP(![manager fileExistsAtPath:[directory URLByAppendingPathComponent:@".owner.lock"].path]);
    NSURL *local = [directory URLByAppendingPathComponent:@"local.wav"];
    NSURL *remote = [directory URLByAppendingPathComponent:@"remote.wav"];
    NSURL *output = [scratch URLByAppendingPathComponent:@"owned-recovered.wav"];
    REQUIRE_OWNERSHIP(directory && WriteJobTracks(directory));
    REQUIRE_OWNERSHIP(AKPersistRecordingRecoveryJob(directory, local, remote, output, nil));
    NSDictionary *snapshot = AKRecordingRecoveryJobsAtRoot(root).firstObject;
    REQUIRE_OWNERSHIP(snapshot != nil);
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil);
    REQUIRE_OWNERSHIP(owner != nil);
    REQUIRE_OWNERSHIP(AKPersistOwnedRecordingRecoveryJob(owner, local, remote, output, AKRecordingJobPhaseCapturing, nil));
    REQUIRE_OWNERSHIP([ReadManifest(directory)[@"version"] isEqual:@2] &&
        [ReadManifest(directory)[@"state"] isEqual:@"capturing"]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    REQUIRE_OWNERSHIP(AKClaimRecordingJob(directory, nil) == nil);
    NSNumber *lockPermissions = [manager attributesOfItemAtPath:
        [directory URLByAppendingPathComponent:@".owner.lock"].path error:nil][NSFilePosixPermissions];
    REQUIRE_OWNERSHIP(lockPermissions.unsignedIntegerValue == 0600);
    NSURL *alias = [scratch URLByAppendingPathComponent:@"owned-alias"];
    REQUIRE_OWNERSHIP([manager createSymbolicLinkAtURL:alias withDestinationURL:directory error:nil]);
    REQUIRE_OWNERSHIP(AKClaimRecordingJob(alias, nil) == nil);

    __block NSUInteger failures = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKRecordingExportDidFailNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) { failures++; }];
    __block NSUInteger rejectedCallbacks = 0;
    __block BOOL rejectionOnMain = YES;
    AKRetryRecordingRecoveryJob(snapshot, output, ^(BOOL succeeded) {
        rejectedCallbacks++; rejectionOnMain &= !succeeded && NSThread.isMainThread;
    });
    REQUIRE_OWNERSHIP(rejectedCallbacks == 0);
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return rejectedCallbacks == 1; }, 2));
    REQUIRE_OWNERSHIP(rejectionOnMain && failures == 0 && ![manager fileExistsAtPath:output.path]);
    // Ownership, rather than a readable manifest, hides a healthy recording.
    REQUIRE_OWNERSHIP([@"malformed" writeToURL:[directory URLByAppendingPathComponent:@"recovery.plist"]
        atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    REQUIRE_OWNERSHIP(AKPersistOwnedRecordingRecoveryJob(owner, local, remote, output, AKRecordingJobPhaseFinalising, nil));
    REQUIRE_OWNERSHIP([ReadManifest(directory)[@"state"] isEqual:@"finalising"]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    REQUIRE_OWNERSHIP(!AKPersistRecordingRecoveryJob(directory, local, remote, output, nil));
    AKRetryRecordingRecoveryJob(snapshot, output, ^(BOOL succeeded) {
        rejectedCallbacks++; rejectionOnMain &= !succeeded && NSThread.isMainThread;
    });
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return rejectedCallbacks == 2; }, 2));
    REQUIRE_OWNERSHIP(rejectionOnMain && failures == 0);
    AKFinishRecordingRecoveryJob(owner, NO);
    REQUIRE_OWNERSHIP([ReadManifest(directory)[@"state"] isEqual:@"failed"]);
    AKFinishRecordingRecoveryJob(owner, YES);
    AKDiscardRecordingRecoveryJob(owner);
    REQUIRE_OWNERSHIP([manager fileExistsAtPath:local.path] && [manager fileExistsAtPath:remote.path]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 1);

    // A snapshot's track URLs are ignored; the currently claimed manifest wins.
    NSMutableDictionary *forgedTracks = [snapshot mutableCopy];
    forgedTracks[@"localURL"] = [scratch URLByAppendingPathComponent:@"not-this-job.wav"];
    forgedTracks[@"remoteURL"] = forgedTracks[@"localURL"];
    __block NSUInteger successfulCallbacks = 0;
    __block BOOL successfulOnMain = NO;
    Method blockedStart = class_getInstanceMethod(NSURL.class, @selector(startAccessingSecurityScopedResource));
    IMP originalBlockedStart = method_setImplementation(blockedStart, (IMP)ScopeStart);
    ScopeBlockedTarget = output.absoluteString;
    ScopeBlockedEntered = dispatch_semaphore_create(0); ScopeBlockedRelease = dispatch_semaphore_create(0);
    ScopeGrant = NO;
    AKRetryRecordingRecoveryJob(forgedTracks, output, ^(BOOL succeeded) {
        successfulCallbacks++; successfulOnMain = succeeded && NSThread.isMainThread;
    });
    // Admission returns before any file I/O. Hold the actual claimed worker at
    // this attempt's scope boundary while main processes its duplicate rejection.
    __block BOOL blockedWorkerEntered = NO;
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL {
        if (!blockedWorkerEntered)
            blockedWorkerEntered = dispatch_semaphore_wait(ScopeBlockedEntered, DISPATCH_TIME_NOW) == 0;
        return blockedWorkerEntered;
    }, 2));
    REQUIRE_OWNERSHIP([ReadManifest(directory)[@"state"] isEqual:@"failed"]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    REQUIRE_OWNERSHIP(AKClaimRecordingJob(directory, nil) == nil);
    AKRetryRecordingRecoveryJob(snapshot, [scratch URLByAppendingPathComponent:@"duplicate.wav"], ^(BOOL succeeded) {
        rejectedCallbacks++; rejectionOnMain &= !succeeded && NSThread.isMainThread;
    });
    __block BOOL drained = NO;
    AKWaitForPendingRecordingFinalizations(^{
        drained = successfulCallbacks == 1 && ![manager fileExistsAtPath:directory.path] && NSThread.isMainThread;
    });
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return rejectedCallbacks == 3; }, 2));
    REQUIRE_OWNERSHIP(!drained && successfulCallbacks == 0);
    dispatch_semaphore_signal(ScopeBlockedRelease);
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return drained && rejectedCallbacks == 3; }, 10));
    method_setImplementation(blockedStart, originalBlockedStart); ScopeBlockedTarget = nil;
    REQUIRE_OWNERSHIP(successfulOnMain && rejectionOnMain && failures == 0 && CheckWaveChannels(output));
    REQUIRE_OWNERSHIP(![manager fileExistsAtPath:[scratch URLByAppendingPathComponent:@"duplicate.wav"].path]);
    AKRetryRecordingRecoveryJob(snapshot, [scratch URLByAppendingPathComponent:@"stale.wav"], ^(BOOL succeeded) {
        rejectedCallbacks++; rejectionOnMain &= !succeeded && NSThread.isMainThread;
    });
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return rejectedCallbacks == 4; }, 2));
    REQUIRE_OWNERSHIP(rejectionOnMain && failures == 0);

    // A real converter failure releases ownership, marks failed and keeps raw.
    directory = AKCreateRecordingRecoveryDirectoryAtRoot(root, nil);
    local = [directory URLByAppendingPathComponent:@"local.wav"];
    remote = [directory URLByAppendingPathComponent:@"remote.wav"];
    REQUIRE_OWNERSHIP(WriteJobTracks(directory));
    snapshot = AKRecordingRecoveryJobsAtRoot(root).firstObject;
    __block BOOL failedCallback = NO;
    AKRetryRecordingRecoveryJob(snapshot, [scratch URLByAppendingPathComponent:@"bad-export.invalid"], ^(BOOL succeeded) {
        failedCallback = !succeeded && NSThread.isMainThread;
    });
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return failedCallback && failures == 1; }, 10));
    REQUIRE_OWNERSHIP([ReadManifest(directory)[@"state"] isEqual:@"failed"]);
    REQUIRE_OWNERSHIP([manager fileExistsAtPath:local.path] && [manager fileExistsAtPath:remote.path]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 1);
    owner = AKClaimRecordingJob(directory, nil);
    REQUIRE_OWNERSHIP(owner != nil);
    AKDiscardRecordingRecoveryJob(owner);
    REQUIRE_OWNERSHIP(![manager fileExistsAtPath:directory.path]);
    // Neither a stale UI snapshot nor a finished owner can remove a replacement
    // directory which happens to reuse the old pathname.
    REQUIRE_OWNERSHIP([manager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:nil]);
    REQUIRE_OWNERSHIP(WriteJobTracks(directory));
    NSDictionary *replacement = AKRecordingRecoveryJobsAtRoot(root).firstObject;
    REQUIRE_OWNERSHIP(![snapshot[@"directoryIdentity"] isEqual:replacement[@"directoryIdentity"]]);
    AKFinishRecordingRecoveryJob(owner, YES);
    AKDiscardRecordingRecoveryJob(owner);
    REQUIRE_OWNERSHIP([manager fileExistsAtPath:local.path] && [manager fileExistsAtPath:remote.path]);
    AKRetryRecordingRecoveryJob(snapshot, [scratch URLByAppendingPathComponent:@"reused-stale.wav"], ^(BOOL succeeded) {
        rejectedCallbacks++; rejectionOnMain &= !succeeded && NSThread.isMainThread;
    });
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return rejectedCallbacks == 5; }, 2));
    REQUIRE_OWNERSHIP(rejectionOnMain && failures == 1 && [manager fileExistsAtPath:local.path]);
    owner = AKClaimRecordingJob(directory, nil);
    REQUIRE_OWNERSHIP(owner != nil);
    AKDiscardRecordingRecoveryJob(owner);

    // Missing, legacy and malformed metadata keep a safe conventional pair.
    directory = AKCreateRecordingRecoveryDirectoryAtRoot(root, nil);
    REQUIRE_OWNERSHIP(WriteJobTracks(directory));
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 1);
    REQUIRE_OWNERSHIP([@"bad plist" writeToURL:[directory URLByAppendingPathComponent:@"recovery.plist"]
        atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 1);
    REQUIRE_OWNERSHIP(WriteManifest(directory, @{@"version": @2, @"state": @"capturing", @"local": @"../escape.wav", @"remote": @7}));
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 1);
    REQUIRE_OWNERSHIP(AKPersistRecordingRecoveryJob(directory,
        [directory URLByAppendingPathComponent:@"local.wav"], [directory URLByAppendingPathComponent:@"remote.wav"], output, nil));
    REQUIRE_OWNERSHIP([ReadManifest(directory)[@"version"] isEqual:@1] && AKRecordingRecoveryJobsAtRoot(root).count == 1);
    REQUIRE_OWNERSHIP(WriteManifest(directory, @{@"version": @2, @"state": @"completed"}));
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    AKRetryRecordingRecoveryJob(@{@"directoryURL": directory}, [scratch URLByAppendingPathComponent:@"completed.wav"], ^(BOOL succeeded) {
        rejectedCallbacks++; rejectionOnMain &= !succeeded && NSThread.isMainThread;
    });
    REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return rejectedCallbacks == 6; }, 2));
    REQUIRE_OWNERSHIP(rejectionOnMain && failures == 1);
    owner = AKClaimRecordingJob(directory, nil);
    REQUIRE_OWNERSHIP(owner != nil);
    AKFinishRecordingRecoveryJob(owner, YES);
    REQUIRE_OWNERSHIP(![manager fileExistsAtPath:directory.path]);

    // Lock and raw-file symlinks are never followed.
    directory = AKCreateRecordingRecoveryDirectoryAtRoot(root, nil);
    REQUIRE_OWNERSHIP(WriteJobTracks(directory));
    NSURL *outside = [scratch URLByAppendingPathComponent:@"outside-lock"];
    REQUIRE_OWNERSHIP([@"unchanged" writeToURL:outside atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    REQUIRE_OWNERSHIP([manager createSymbolicLinkAtURL:[directory URLByAppendingPathComponent:@".owner.lock"]
        withDestinationURL:outside error:nil]);
    REQUIRE_OWNERSHIP(AKClaimRecordingJob(directory, nil) == nil && AKRecordingRecoveryJobsAtRoot(root).count == 0);
    REQUIRE_OWNERSHIP([[NSString stringWithContentsOfURL:outside encoding:NSUTF8StringEncoding error:nil] isEqual:@"unchanged"]);
    REQUIRE_OWNERSHIP([manager removeItemAtURL:[directory URLByAppendingPathComponent:@".owner.lock"] error:nil]);
    REQUIRE_OWNERSHIP([manager removeItemAtURL:[directory URLByAppendingPathComponent:@"local.wav"] error:nil]);
    REQUIRE_OWNERSHIP([manager createSymbolicLinkAtURL:[directory URLByAppendingPathComponent:@"local.wav"]
        withDestinationURL:outside error:nil]);
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    owner = AKClaimRecordingJob(directory, nil);
    AKDiscardRecordingRecoveryJob(owner);

    // A deallocated owner leaves abandoned capturing raw audio recoverable.
    directory = AKCreateRecordingRecoveryDirectoryAtRoot(root, nil);
    REQUIRE_OWNERSHIP(WriteJobTracks(directory));
    @autoreleasepool {
        AKRecordingJobOwnership *abandoned = AKClaimRecordingJob(directory, nil);
        REQUIRE_OWNERSHIP(abandoned != nil);
        REQUIRE_OWNERSHIP(AKPersistOwnedRecordingRecoveryJob(abandoned,
            [directory URLByAppendingPathComponent:@"local.wav"], [directory URLByAppendingPathComponent:@"remote.wav"],
            output, AKRecordingJobPhaseCapturing, nil));
        REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
    }
    REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 1);
    owner = AKClaimRecordingJob(directory, nil);
    AKDiscardRecordingRecoveryJob(owner);

    // A separate process holds the claim while alive. Terminating it models an
    // abrupt capture/finalisation exit, without running finish or deallocation.
    for (NSString *phase in @[@"capturing", @"finalising"]) {
        directory = AKCreateRecordingRecoveryDirectoryAtRoot(root, nil);
        REQUIRE_OWNERSHIP(WriteJobTracks(directory));
        snapshot = AKRecordingRecoveryJobsAtRoot(root).firstObject;
        NSTask *child = [[NSTask alloc] init];
        child.executableURL = executable;
        child.arguments = @[@"--abandon-job", directory.path, phase];
        REQUIRE_OWNERSHIP([child launchAndReturnError:nil]);
        NSURL *ready = [directory URLByAppendingPathComponent:@"ready"];
        BOOL readyToTest = SpinUntil(^BOOL { return [manager fileExistsAtPath:ready.path] || !child.isRunning; }, 5) && child.isRunning;
        if (!readyToTest && child.isRunning) [child terminate];
        REQUIRE_OWNERSHIP(readyToTest);
        REQUIRE_OWNERSHIP([ReadManifest(directory)[@"state"] isEqual:phase]);
        REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 0);
        REQUIRE_OWNERSHIP(AKClaimRecordingJob(directory, nil) == nil);
        __block BOOL childRejection = NO;
        AKRetryRecordingRecoveryJob(snapshot, [scratch URLByAppendingPathComponent:@"child-busy.wav"], ^(BOOL succeeded) {
            childRejection = !succeeded && NSThread.isMainThread;
        });
        REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return childRejection; }, 2));
        REQUIRE_OWNERSHIP(failures == 1);
        [child terminate];
        [child waitUntilExit];
        REQUIRE_OWNERSHIP(AKRecordingRecoveryJobsAtRoot(root).count == 1);
        REQUIRE_OWNERSHIP([ReadManifest(directory)[@"state"] isEqual:phase]);
        NSURL *restartOutput = [scratch URLByAppendingPathComponent:[phase stringByAppendingString:@"-restart.wav"]];
        __block BOOL restartRecovered = NO;
        AKRetryRecordingRecoveryJob(snapshot, restartOutput, ^(BOOL succeeded) {
            restartRecovered = succeeded && NSThread.isMainThread;
        });
        REQUIRE_OWNERSHIP(SpinUntil(^BOOL { return restartRecovered; }, 10));
        REQUIRE_OWNERSHIP(CheckWaveChannels(restartOutput) && ![manager fileExistsAtPath:directory.path]);
    }
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    REQUIRE_OWNERSHIP(failures == 1 && AKRecordingRecoveryJobsAtRoot(root).count == 0);
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 4 && strcmp(argv[1], "--abandon-job") == 0) {
            NSURL *job = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]] isDirectory:YES];
            AKRecordingJobOwnership *owner = AKClaimRecordingJob(job, nil);
            AKRecordingJobPhase phase = strcmp(argv[3], "capturing") == 0 ? AKRecordingJobPhaseCapturing : AKRecordingJobPhaseFinalising;
            if (!owner || !AKPersistOwnedRecordingRecoveryJob(owner, [job URLByAppendingPathComponent:@"local.wav"],
                [job URLByAppendingPathComponent:@"remote.wav"], [job.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"child.wav"], phase, nil)) return 41;
            if (![@"ready" writeToURL:[job URLByAppendingPathComponent:@"ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil]) return 42;
            while (YES) { pause(); (void)owner.directoryURL; }
        }
        NSFileManager *manager = NSFileManager.defaultManager;
        NSURL *directory = [manager.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString
                                                                        isDirectory:YES];
        if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil]) return 2;

        NSError *error = nil;
        NSURL *first = AKReserveRecordingURL(directory, @"same call", @"ogg", &error);
        NSURL *second = AKReserveRecordingURL(directory, @"same call", @"ogg", &error);
        if (first == nil || second == nil || [first isEqual:second] || ![manager fileExistsAtPath:first.path]) return 3;

        NSURL *local = [directory URLByAppendingPathComponent:@"local.wav"];
        NSURL *remote = [directory URLByAppendingPathComponent:@"remote.wav"];
        if (!WriteTrack(local, 16000, YES) || !WriteTrack(remote, 16000, NO)) return 4;
        NSURL *wave = [directory URLByAppendingPathComponent:@"stereo.wav"];
        if (!AKMergeMonoRecordingsIntoStereo(local, remote, wave) || !CheckWaveChannels(wave)) return 5;

        NSURL *mp3 = [directory URLByAppendingPathComponent:@"stereo.mp3"];
        NSURL *ogg = [directory URLByAppendingPathComponent:@"stereo.ogg"];
        if (!AKMergeMonoRecordingsIntoStereo(local, remote, mp3) || !HasPrefix(mp3, "\xff", 1)) return 6;
        if (!AKMergeMonoRecordingsIntoStereo(local, remote, ogg) || !HasPrefix(ogg, "OggS", 4)) return 7;

        NSURL *wrongRate = [directory URLByAppendingPathComponent:@"wrong-rate.wav"];
        NSURL *rejected = [directory URLByAppendingPathComponent:@"rejected.wav"];
        if (!WriteTrack(wrongRate, 8000, NO) || AKMergeMonoRecordingsIntoStereo(local, wrongRate, rejected) ||
            [manager fileExistsAtPath:rejected.path]) return 8;

        NSURL *delayedLocal = [directory URLByAppendingPathComponent:@"delayed-local.wav"];
        NSURL *delayedSource = [directory URLByAppendingPathComponent:@"delayed-source.wav"];
        NSURL *delayedOutput = [directory URLByAppendingPathComponent:@"delayed-output.mp3"];
        if (![@"incomplete WAV header" writeToURL:delayedLocal
                                       atomically:YES
                                         encoding:NSUTF8StringEncoding
                                            error:nil] ||
            !WriteTrack(delayedSource, 16000, YES)) return 9;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [manager replaceItemAtURL:delayedLocal
                        withItemAtURL:delayedSource
                       backupItemName:nil
                              options:0
                     resultingItemURL:nil
                                error:nil];
        });
        if (!AKMergeMonoRecordingsIntoStereo(delayedLocal, remote, delayedOutput) ||
            !HasPrefix(delayedOutput, "\xff", 1)) return 10;

        __block BOOL finished = NO;
        __block BOOL callbackOnMainThread = NO;
        NSURL *asynchronous = [directory URLByAppendingPathComponent:@"async.ogg"];
        AKMergeMonoRecordingsIntoStereoAsync(local, remote, asynchronous, ^(BOOL succeeded) {
            finished = succeeded;
            callbackOnMainThread = NSThread.isMainThread;
        });
        if (finished) return 11;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!finished && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        if (!finished || !callbackOnMainThread) return 12;

        // Termination must wait for every queued conversion AND its main-queue
        // cleanup, including conversion failure. An empty barrier is also async.
        __block NSUInteger completions = 0;
        __block BOOL successfulConversion = NO;
        __block BOOL failedConversion = NO;
        __block BOOL drained = NO;
        AKMergeMonoRecordingsIntoStereoAsync(local, remote,
            [directory URLByAppendingPathComponent:@"pending.wav"], ^(BOOL succeeded) {
                successfulConversion = succeeded && NSThread.isMainThread;
                completions++;
            });
        AKMergeMonoRecordingsIntoStereoAsync(local, remote,
            [directory URLByAppendingPathComponent:@"unsupported.invalid"], ^(BOOL succeeded) {
                failedConversion = !succeeded && NSThread.isMainThread;
                completions++;
            });
        AKWaitForPendingRecordingFinalizations(^{
            drained = completions == 2 && successfulConversion && failedConversion && NSThread.isMainThread;
        });
        if (drained) return 13;
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!drained && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        if (!drained) return 14;
        __block BOOL emptyDrain = NO;
        AKWaitForPendingRecordingFinalizations(^{ emptyDrain = NSThread.isMainThread; });
        if (emptyDrain) return 15;
        deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!emptyDrain && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        if (!emptyDrain) return 16;

        // Recovery stays durable across a reload and can be exported elsewhere
        // after a real conversion failure. Every path is in this scratch root.
        NSURL *recoveryRoot = [directory URLByAppendingPathComponent:@"Recovery" isDirectory:YES];
        NSURL *jobDirectory = AKCreateRecordingRecoveryDirectoryAtRoot(recoveryRoot, &error);
        NSURL *jobLocal = [jobDirectory URLByAppendingPathComponent:@"local.wav"];
        NSURL *jobRemote = [jobDirectory URLByAppendingPathComponent:@"remote.wav"];
        NSURL *failedDirectory = [directory URLByAppendingPathComponent:@"denied-destination" isDirectory:YES];
        if (![manager createDirectoryAtURL:failedDirectory withIntermediateDirectories:NO attributes:nil error:nil]) return 17;
        NSURL *failedOutput = AKReserveRecordingURL(failedDirectory, @"failed", @"wav", &error);
        if (!failedOutput || ![manager setAttributes:@{NSFilePosixPermissions: @0400} ofItemAtPath:failedOutput.path error:nil] ||
            ![manager setAttributes:@{NSFilePosixPermissions: @0500} ofItemAtPath:failedDirectory.path error:nil]) return 17;
        if (!jobDirectory || !WriteTrack(jobLocal, 16000, YES) || !WriteTrack(jobRemote, 16000, NO) ||
            !AKPersistRecordingRecoveryJob(jobDirectory, jobLocal, jobRemote, failedOutput, &error)) return 17;
        NSNumber *permissions = [manager attributesOfItemAtPath:jobDirectory.path error:nil][NSFilePosixPermissions];
        NSNumber *manifestPermissions = [manager attributesOfItemAtPath:
            [jobDirectory URLByAppendingPathComponent:@"recovery.plist"].path error:nil][NSFilePosixPermissions];
        if (permissions.unsignedIntegerValue != 0700 || manifestPermissions.unsignedIntegerValue != 0600) return 18;
        __block BOOL failedExport = NO;
        AKMergeMonoRecordingsIntoStereoAsync(jobLocal, jobRemote, failedOutput, ^(BOOL succeeded) {
            failedExport = !succeeded;
            if (!succeeded) AKReportRecordingExportFailure(jobDirectory, failedOutput, nil);
        });
        __block BOOL visibleFailure = NO;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKRecordingExportDidFailNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                visibleFailure = NSThread.isMainThread && [note.userInfo[@"recoveryDirectoryURL"] isEqual:jobDirectory];
            }];
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ((!failedExport || !visibleFailure) && [deadline timeIntervalSinceNow] > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [manager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:failedDirectory.path error:nil];
        NSArray *reloadedJobs = AKRecordingRecoveryJobsAtRoot(recoveryRoot);
        if (!failedExport || !visibleFailure || reloadedJobs.count != 1 ||
            ![manager fileExistsAtPath:jobLocal.path] || ![manager fileExistsAtPath:jobRemote.path]) return 19;
        __block BOOL recovered = NO;
        NSURL *recoveredOutput = [directory URLByAppendingPathComponent:@"recovered.wav"];
        AKRetryRecordingRecoveryJob(reloadedJobs.firstObject, recoveredOutput, ^(BOOL succeeded) {
            recovered = succeeded && NSThread.isMainThread;
        });
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!recovered && [deadline timeIntervalSinceNow] > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        if (!recovered || !CheckWaveChannels(recoveredOutput) || [manager fileExistsAtPath:jobDirectory.path] ||
            AKRecordingRecoveryJobsAtRoot(recoveryRoot).count != 0) return 20;

        // An absent, malformed or unsafe destination must require a new filename.
        // Never export into the raw folder that successful cleanup removes.
        NSURL *orphan = AKCreateRecordingRecoveryDirectoryAtRoot(recoveryRoot, &error);
        NSURL *orphanLocal = [orphan URLByAppendingPathComponent:@"local.wav"];
        NSURL *orphanRemote = [orphan URLByAppendingPathComponent:@"remote.wav"];
        if (!orphan || !WriteTrack(orphanLocal, 16000, YES) || !WriteTrack(orphanRemote, 16000, NO)) return 21;
        NSDictionary *orphanJob = AKRecordingRecoveryJobsAtRoot(recoveryRoot).firstObject;
        if (![orphanJob[@"needsNewDestination"] boolValue] ||
            [[orphanJob[@"destinationURL"] path] hasPrefix:[orphan.path stringByAppendingString:@"/"]]) return 22;
        NSURL *unsafeOutput = [orphan URLByAppendingPathComponent:@"would-be-deleted.wav"];
        if (AKPersistRecordingRecoveryJob(orphan, orphanLocal, orphanRemote, unsafeOutput, &error) ||
            ![manager fileExistsAtPath:orphanLocal.path] || ![manager fileExistsAtPath:orphanRemote.path]) return 23;
        for (NSString *badDestination in @[@"relative.wav", unsafeOutput.path]) {
            NSDictionary *badManifest = @{@"local": @"local.wav", @"remote": @"remote.wav", @"destination": badDestination};
            NSData *manifestData = [NSPropertyListSerialization dataWithPropertyList:badManifest
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            BOOL wrote = [manifestData writeToURL:[orphan URLByAppendingPathComponent:@"recovery.plist"] atomically:YES];
            if (!wrote || ![AKRecordingRecoveryJobsAtRoot(recoveryRoot).firstObject[@"needsNewDestination"] boolValue]) {
                NSLog(@"Recovery manifest guard failed: wrote=%d relative=%d", wrote, [badDestination isEqual:@"relative.wav"]);
                return 24;
            }
        }

        Method scopeStart = class_getInstanceMethod(NSURL.class, @selector(startAccessingSecurityScopedResource));
        Method scopeStop = class_getInstanceMethod(NSURL.class, @selector(stopAccessingSecurityScopedResource));
        IMP originalStart = method_setImplementation(scopeStart, (IMP)ScopeStart);
        IMP originalStop = method_setImplementation(scopeStop, (IMP)ScopeStop);
        // Existing-output failure must release a granted scope before completion.
        ScopeGrant = YES; ScopeStarts = ScopeStops = 0;
        __block BOOL scopeFinished = NO;
        __block BOOL scopeBalanced = NO;
        AKRetryRecordingRecoveryJob(orphanJob, recoveredOutput, ^(BOOL succeeded) {
            scopeFinished = YES; scopeBalanced = !succeeded && ScopeStarts == 1 && ScopeStops == 1;
        });
        deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!scopeFinished && [deadline timeIntervalSinceNow] > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        if (!scopeBalanced) return 25;
        // An actual asynchronous converter failure also releases its grant,
        // while keeping both raw tracks available for another destination.
        ScopeStarts = ScopeStops = 0; scopeFinished = scopeBalanced = NO;
        [manager setAttributes:@{NSFilePosixPermissions: @0500} ofItemAtPath:failedDirectory.path error:nil];
        NSURL *deniedScopeOutput = [failedDirectory URLByAppendingPathComponent:@"denied-scope-output.wav"];
        AKRetryRecordingRecoveryJob(orphanJob, deniedScopeOutput, ^(BOOL succeeded) {
            scopeFinished = YES; scopeBalanced = !succeeded && ScopeStarts == 1 && ScopeStops == 1;
        });
        if (ScopeStops != 0) return 30;
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!scopeFinished && [deadline timeIntervalSinceNow] > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        [manager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:failedDirectory.path error:nil];
        if (!scopeBalanced || ![manager fileExistsAtPath:orphanLocal.path] || ![manager fileExistsAtPath:orphanRemote.path]) return 31;
        // A refused scope is never stopped and does not prevent ordinary file IO.
        ScopeGrant = NO; ScopeStarts = ScopeStops = 0; scopeFinished = scopeBalanced = NO;
        NSURL *unscopedOutput = [directory URLByAppendingPathComponent:@"ordinary-recovered.wav"];
        AKRetryRecordingRecoveryJob(orphanJob, unscopedOutput, ^(BOOL succeeded) {
            scopeFinished = YES; scopeBalanced = succeeded && ScopeStarts == 1 && ScopeStops == 0;
        });
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!scopeFinished && [deadline timeIntervalSinceNow] > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        if (!scopeBalanced || !CheckWaveChannels(unscopedOutput)) return 26;
        NSURL *scopedJob = AKCreateRecordingRecoveryDirectoryAtRoot(recoveryRoot, &error);
        NSURL *scopedLocal = [scopedJob URLByAppendingPathComponent:@"local.wav"];
        NSURL *scopedRemote = [scopedJob URLByAppendingPathComponent:@"remote.wav"];
        NSURL *scopedOutput = [directory URLByAppendingPathComponent:@"scoped-recovered.wav"];
        if (!WriteTrack(scopedLocal, 16000, YES) || !WriteTrack(scopedRemote, 16000, NO) ||
            !AKPersistRecordingRecoveryJob(scopedJob, scopedLocal, scopedRemote, scopedOutput, &error)) return 27;
        ScopeGrant = YES; ScopeStarts = ScopeStops = 0; scopeFinished = scopeBalanced = NO;
        AKRetryRecordingRecoveryJob(AKRecordingRecoveryJobsAtRoot(recoveryRoot).firstObject, scopedOutput, ^(BOOL succeeded) {
            scopeFinished = YES; scopeBalanced = succeeded && ScopeStarts == 1 && ScopeStops == 1;
        });
        if (ScopeStops != 0) return 28; // token must survive the async conversion
        deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!scopeFinished && [deadline timeIntervalSinceNow] > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        method_setImplementation(scopeStart, originalStart);
        method_setImplementation(scopeStop, originalStop);
        if (!scopeBalanced || !CheckWaveChannels(scopedOutput) || [manager fileExistsAtPath:scopedJob.path]) return 29;

        NSURL *executable = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]];
        if (!RunOwnershipCases(directory, executable)) return 40;
        [manager removeItemAtURL:directory error:nil];
        printf("recording hardening harness passed (%lu ownership assertions)\n", (unsigned long)OwnershipChecks);
    }
    return 0;
}
