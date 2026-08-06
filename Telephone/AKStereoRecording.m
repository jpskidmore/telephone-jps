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
#include <unistd.h>

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

void AKMergeMonoRecordingsIntoStereoAsync(NSURL *localURL,
                                          NSURL *remoteURL,
                                          NSURL *destinationURL,
                                          void (^completion)(BOOL succeeded)) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.tlphn.Telephone.recording-encoder", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(queue, ^{
        BOOL succeeded = AKMergeMonoRecordingsIntoStereo(localURL, remoteURL, destinationURL);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(succeeded);
            }
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
