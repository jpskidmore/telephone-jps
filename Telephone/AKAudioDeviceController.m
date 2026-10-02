//
//  AKAudioDeviceController.m
//  Telephone
//

#import "AKAudioDeviceController.h"

#include <stdint.h>

// Keep this Foundation-only module independent of PJSUA/CoreAudio initialization.
// These values come from ThirdParty/PJSIP/include/pjmedia-audiodev/errno.h:
// PJMEDIA_AUDIODEV_ERRNO_START/END and PJMEDIA_AUDIODEV_COREAUDIO_ERRNO_START.
static const int AKAudioErrorStart = 420000;
static const int AKAudioErrorEnd = 469999;
static const int AKCoreAudioErrorStart = 440000;
static const int AKCoreAudioErrorEnd = 459999;
// CoreAudio's kAudioHardwareNotRunningError = 'stop' = 0x73746f70.
static const int64_t AKCoreAudioNotRunning = 1937010544;

static BOOL AKIsEncodedCoreAudioStop(int status) {
    return status < 0 && (int64_t)AKCoreAudioErrorStart - (int64_t)status == AKCoreAudioNotRunning;
}

static BOOL AKIsAudioFailure(int status) {
    // Conference connects can fail for stale ports/PJ_EINVAL. Do not let those
    // poison working hardware. Nor is an arbitrary negative number enough to
    // prove CoreAudio provenance: recognize the verified 'stop' encoding only.
    // Add other negative codes only with an audited mapping and a regression test.
    return (status >= AKAudioErrorStart && status <= AKAudioErrorEnd) || AKIsEncodedCoreAudioStop(status);
}

static NSString *AKStatusDetails(int status) {
    if (status == 0) return @"class=success";
    if (AKIsEncodedCoreAudioStop(status)) {
        // Use wide arithmetic: negating a 32-bit raw status may overflow.
        int64_t audioStatus = (int64_t)AKCoreAudioErrorStart - (int64_t)status;
        return [NSString stringWithFormat:@"class=coreaudio-stop coreaudio_osstatus=%lld coreaudio_fourcc='stop' coreaudio_symbol=kAudioHardwareNotRunningError",
                                          (long long)audioStatus];
    }
    if (status >= AKAudioErrorStart && status <= AKAudioErrorEnd) {
        if (status >= AKCoreAudioErrorStart && status <= AKCoreAudioErrorEnd) {
            // The vendored header's platform-specific ranges overlap. Report
            // this inverse as a candidate, not a claim about an arbitrary code.
            return [NSString stringWithFormat:@"class=pjmedia-audio coreaudio_candidate_osstatus=%lld",
                                              (long long)((int64_t)AKCoreAudioErrorStart - (int64_t)status)];
        }
        return @"class=pjmedia-audio";
    }
    return @"class=unclassified";
}

@interface AKAudioDeviceController ()
@property(nonatomic, strong) id<AKAudioDeviceBackend> backend;
@property(nonatomic, copy) AKAudioDeviceLogger logger;
@property(nonatomic, readwrite) BOOL hasFailed;
@property(nonatomic, readwrite) int lastFailureStatus;
@property(nonatomic, readwrite) BOOL outgoingCallPending;
@property(nonatomic) BOOL selectionKnown;
@property(nonatomic) int input;
@property(nonatomic) int output;
@end

@implementation AKAudioDeviceController

+ (BOOL)isAudioDeviceFailure:(int)status {
    return AKIsAudioFailure(status);
}

- (instancetype)initWithBackend:(id<AKAudioDeviceBackend>)backend
                         logger:(AKAudioDeviceLogger)logger {
    NSParameterAssert(backend != nil);
    self = [super init];
    if (self) {
        _backend = backend;
        _logger = logger ? [logger copy] : [^(NSString *message) { NSLog(@"%@", message); } copy];
    }
    return self;
}

- (void)logOperation:(NSString *)operation
              phase:(NSString *)phase
             source:(int)source
        destination:(int)destination
             status:(int)status
           duration:(NSTimeInterval)duration {
    // Only fixed labels and numeric device/port IDs. Never pass device names,
    // SIP addresses, filesystem paths, backend descriptions, or thread names.
    NSString *message = [NSString stringWithFormat:
        @"audio-device operation=%@ phase=%@ thread=%@ selection_known=%d input=%d output=%d source=%d destination=%d status=%d duration_ms=%.3f %@",
        operation, phase, [NSThread isMainThread] ? @"main" : @"background",
        self.selectionKnown ? 1 : 0, self.input, self.output, source, destination,
        status, MAX(0.0, duration * 1000.0), AKStatusDetails(status)];
    self.logger(message);
}

- (BOOL)latchFailure:(int)status {
    if (status == 0 || self.hasFailed) return NO;
    self.hasFailed = YES;
    self.lastFailureStatus = status;
    return YES;
}

- (void)notifyFailure {
    // Copy before invoking so a handler may replace itself safely. The latch is
    // already set and fallback already complete before any user code runs.
    AKAudioDeviceFailureHandler handler = self.failureHandler;
    if (handler) handler(self.lastFailureStatus);
}

- (void)fallBackToNullSoundDevice {
    // Called only once on the transition into failure. Never recurse on error.
    [self logOperation:@"null-fallback" phase:@"begin" source:-1 destination:-1 status:0 duration:0];
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    int status = [self.backend useNullSoundDevice];
    NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - start;
    [self logOperation:@"null-fallback" phase:@"end" source:-1 destination:-1 status:status duration:duration];
    // The original failure remains authoritative even if fallback also fails.
}

- (int)selectInput:(int)input output:(int)output {
    if (self.hasFailed) {
        // Do not overwrite the actual attempted selection with a skipped one.
        [self logOperation:@"select" phase:@"skipped-latched" source:-1 destination:-1
                    status:self.lastFailureStatus duration:0];
        return self.lastFailureStatus;
    }
    self.selectionKnown = YES;
    self.input = input;
    self.output = output;
    [self logOperation:@"select" phase:@"begin" source:-1 destination:-1 status:0 duration:0];
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    int status = [self.backend selectInput:input output:output];
    NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - start;
    BOOL firstFailure = [self latchFailure:status];
    [self logOperation:@"select" phase:@"end" source:-1 destination:-1 status:status duration:duration];
    if (firstFailure) {
        [self fallBackToNullSoundDevice];
        [self notifyFailure];
    }
    return status;
}

- (int)connectSource:(int)source destination:(int)destination {
    if (self.hasFailed) {
        [self logOperation:@"connect" phase:@"skipped-latched" source:source destination:destination
                    status:self.lastFailureStatus duration:0];
        return self.lastFailureStatus;
    }
    [self logOperation:@"connect" phase:@"begin" source:source destination:destination status:0 duration:0];
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    int status = [self.backend connectSource:source destination:destination];
    NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - start;
    BOOL firstFailure = AKIsAudioFailure(status) && [self latchFailure:status];
    [self logOperation:@"connect" phase:@"end" source:source destination:destination status:status duration:duration];
    if (firstFailure) {
        [self fallBackToNullSoundDevice];
        [self notifyFailure];
    }
    return status;
}

- (int)useNullSoundDevice {
    if (self.hasFailed) {
        [self logOperation:@"null" phase:@"skipped-latched" source:-1 destination:-1
                    status:self.lastFailureStatus duration:0];
        return self.lastFailureStatus;
    }
    [self logOperation:@"null" phase:@"begin" source:-1 destination:-1 status:0 duration:0];
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    int status = [self.backend useNullSoundDevice];
    NSTimeInterval duration = NSProcessInfo.processInfo.systemUptime - start;
    BOOL firstFailure = [self latchFailure:status];
    [self logOperation:@"null" phase:@"end" source:-1 destination:-1 status:status duration:duration];
    if (firstFailure) [self notifyFailure];
    return status;
}

- (void)resetFailure {
    int previousStatus = self.lastFailureStatus;
    self.hasFailed = NO;
    self.lastFailureStatus = 0;
    [self logOperation:@"reset" phase:@"explicit" source:-1 destination:-1 status:previousStatus duration:0];
}

- (BOOL)beginOutgoingCall {
    if (self.hasFailed || self.outgoingCallPending) return NO;
    self.outgoingCallPending = YES;
    return YES;
}

- (void)finishOutgoingCall {
    self.outgoingCallPending = NO;
}

- (void)reportStatus:(int)status operation:(NSString *)operation shouldLatch:(BOOL)shouldLatch {
    // Never log an arbitrary caller string, even from this narrow reporting API.
    NSString *safeOperation = @"external";
    if ([operation isEqualToString:@"make-call"] ||
        [operation isEqualToString:@"answer-call"] ||
        [operation isEqualToString:@"media-state"] ||
        [operation isEqualToString:@"device-refresh"] ||
        [operation isEqualToString:@"retry-selection"]) {
        safeOperation = operation;
    }
    BOOL firstFailure = shouldLatch && [self latchFailure:status];
    [self logOperation:safeOperation phase:@"reported" source:-1 destination:-1 status:status duration:0];
    if (firstFailure) {
        [self fallBackToNullSoundDevice];
        [self notifyFailure];
    }
}

- (void)reportAudioFailure:(int)status operation:(NSString *)operation {
    [self reportStatus:status operation:operation shouldLatch:AKIsAudioFailure(status)];
}

- (void)reportDeviceFailure:(int)status operation:(NSString *)operation {
    [self reportStatus:status operation:operation shouldLatch:status != 0];
}

@end
