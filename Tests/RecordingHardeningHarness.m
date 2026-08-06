#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#import "AKStereoRecording.h"

#include <math.h>

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

int main(void) {
    @autoreleasepool {
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

        [manager removeItemAtURL:directory error:nil];
        printf("recording hardening harness passed\n");
    }
    return 0;
}
