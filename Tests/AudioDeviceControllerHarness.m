// Tests the production Foundation-only gate with an injected fake backend.
// This executable never starts PJSUA or CoreAudio and never opens audio hardware.
#import <Foundation/Foundation.h>
#import "AKAudioDeviceController.h"

#include <limits.h>
#include <stdio.h>

static NSUInteger checks = 0;
static NSUInteger failures = 0;
static const int stopStatus = -1936570544;

static void Check(BOOL condition, const char *description, int line) {
    checks++;
    if (!condition) {
        failures++;
        fprintf(stderr, "FAIL line %d: %s\n", line, description);
    }
}
#define CHECK(condition, description) Check((condition), (description), __LINE__)

@interface FakeAudioBackend : NSObject <AKAudioDeviceBackend>
@property(nonatomic) int selectStatus;
@property(nonatomic) int nullStatus;
@property(nonatomic) int connectStatus;
@property(nonatomic) NSUInteger selectCount;
@property(nonatomic) NSUInteger nullCount;
@property(nonatomic) NSUInteger connectCount;
@property(nonatomic, strong) NSMutableArray<NSString *> *calls;
@end

@implementation FakeAudioBackend
- (instancetype)init {
    self = [super init];
    if (self) _calls = [NSMutableArray array];
    return self;
}
- (int)selectInput:(int)input output:(int)output {
    self.selectCount++;
    [self.calls addObject:[NSString stringWithFormat:@"select:%d:%d", input, output]];
    return self.selectStatus;
}
- (int)useNullSoundDevice {
    self.nullCount++;
    [self.calls addObject:@"null"];
    return self.nullStatus;
}
- (int)connectSource:(int)source destination:(int)destination {
    self.connectCount++;
    [self.calls addObject:[NSString stringWithFormat:@"connect:%d:%d", source, destination]];
    return self.connectStatus;
}
- (NSString *)description {
    return @"PRIVATE_BACKEND sip:private@example.invalid /Users/private/Microphone";
}
@end

static AKAudioDeviceController *MakeController(FakeAudioBackend *backend, NSMutableArray<NSString *> *logs) {
    return [[AKAudioDeviceController alloc] initWithBackend:backend logger:^(NSString *message) {
        [logs addObject:message];
    }];
}

static NSUInteger CountLogs(NSArray<NSString *> *logs, NSString *fragment) {
    NSUInteger count = 0;
    for (NSString *entry in logs) {
        if ([entry containsString:fragment]) count++;
    }
    return count;
}

static void TestSelectionFailureAndExplicitRetry(void) {
    FakeAudioBackend *backend = [FakeAudioBackend new];
    backend.selectStatus = stopStatus;
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    AKAudioDeviceController *controller = MakeController(backend, logs);
    __block NSUInteger notifications = 0;
    __weak AKAudioDeviceController *weakController = controller;
    controller.failureHandler = ^(int status) {
        notifications++;
        CHECK(status == stopStatus, "notification preserves raw error");
        CHECK(weakController.hasFailed, "failure is latched before notification");
        CHECK(backend.nullCount == notifications, "fallback completes before notification");
        CHECK([weakController connectSource:0 destination:8] == stopStatus,
              "a synchronous notification cannot trigger another audio open");
    };

    CHECK(!controller.hasFailed && controller.lastFailureStatus == 0, "initial state is clear");
    CHECK([controller selectInput:3 output:7] == stopStatus, "first select reports raw failure");
    CHECK(controller.hasFailed && controller.lastFailureStatus == stopStatus, "first error is latched");
    CHECK(backend.selectCount == 1 && backend.nullCount == 1, "failed select has one null fallback");
    CHECK([controller connectSource:0 destination:8] == stopStatus, "first bidirectional connect is gated");
    CHECK([controller connectSource:8 destination:0] == stopStatus, "second bidirectional connect is gated");
    CHECK(backend.connectCount == 0, "no connect reaches hardware after failure");
    CHECK([controller selectInput:30 output:70] == stopStatus, "changing devices does not reset the latch");
    CHECK([controller useNullSoundDevice] == stopStatus, "repeated cleanup is also bounded");
    CHECK(backend.selectCount == 1 && backend.nullCount == 1, "gated operations do not call backend");
    CHECK(notifications == 1, "only one notification per failure episode");
    CHECK(CountLogs(logs, @"input=3 output=7") == logs.count, "skipped selection preserves attempted IDs");

    [controller resetFailure];
    CHECK(!controller.hasFailed && controller.lastFailureStatus == 0, "explicit retry clears failure state");
    CHECK(backend.calls.count == 2, "reset performs no hardware operation");
    CHECK([logs.lastObject containsString:@"input=3 output=7"], "reset retains IDs for diagnostics");
    [controller resetFailure];
    CHECK(backend.calls.count == 2, "reset is idempotent even when clear");
    backend.selectStatus = 0;
    CHECK([controller selectInput:30 output:70] == 0, "explicit retry permits new device IDs");
    CHECK([controller connectSource:0 destination:8] == 0, "retry permits output route");
    CHECK([controller connectSource:8 destination:0] == 0, "retry permits input route");
    CHECK(backend.selectCount == 2 && backend.connectCount == 2, "successful retry calls backend exactly once each");
    CHECK(!controller.hasFailed && notifications == 1, "successful retry does not notify failure");

    backend.selectStatus = stopStatus;
    CHECK([controller selectInput:30 output:70] == stopStatus, "a later failure starts a new episode");
    CHECK(notifications == 2 && backend.nullCount == 2, "new episode gets exactly one fallback and notification");
}

static void TestFailedFallbackAndNullStop(void) {
    FakeAudioBackend *backend = [FakeAudioBackend new];
    backend.selectStatus = 420007;
    backend.nullStatus = 420002;
    AKAudioDeviceController *controller = MakeController(backend, [NSMutableArray array]);
    __block NSUInteger notifications = 0;
    controller.failureHandler = ^(int status) {
        notifications++;
        CHECK(status == 420007, "fallback failure cannot replace the original failure");
        CHECK(backend.nullCount == 1, "failed fallback returns before notification");
    };
    CHECK([controller selectInput:-1 output:-2] == 420007, "select returns first failure when fallback fails");
    CHECK(controller.hasFailed && controller.lastFailureStatus == 420007, "failed fallback leaves latch set");
    CHECK([controller connectSource:4 destination:0] == 420007, "failed fallback still blocks connections");
    CHECK([controller useNullSoundDevice] == 420007, "failed fallback is not retried by cleanup");
    CHECK(backend.nullCount == 1 && notifications == 1, "fallback cannot recurse or notify twice");

    [controller resetFailure];
    CHECK(backend.calls.count == 2, "reset while failed does not touch hardware");
    controller.failureHandler = ^(int status) {
        notifications++;
        CHECK(status == 420002, "direct stop failure is reported");
    };
    CHECK([controller useNullSoundDevice] == 420002, "direct null failure is returned");
    CHECK(controller.hasFailed && controller.lastFailureStatus == 420002, "direct stop failure latches");
    CHECK(backend.nullCount == 2 && notifications == 2, "direct stop failure never attempts fallback recursively");
    CHECK([controller selectInput:1 output:2] == 420002, "stop failure blocks new hardware selection");
    CHECK(backend.selectCount == 1, "latched stop prevents selection call");
}

static void TestSuccessfulFlows(void) {
    FakeAudioBackend *backend = [FakeAudioBackend new];
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    AKAudioDeviceController *controller = MakeController(backend, logs);
    __block NSUInteger notifications = 0;
    controller.failureHandler = ^(int status) { (void)status; notifications++; };
    CHECK([controller selectInput:-1 output:-2] == 0, "default device IDs are passed unchanged");
    CHECK([controller connectSource:0 destination:12] == 0, "successful output route");
    CHECK([controller connectSource:12 destination:0] == 0, "successful input route");
    CHECK([controller useNullSoundDevice] == 0, "successful stop");
    CHECK([controller selectInput:5 output:6] == 0, "successful stop does not block later selection");
    CHECK(!controller.hasFailed && notifications == 0, "successful operations never latch or notify");
    NSArray<NSString *> *expected = @[@"select:-1:-2", @"connect:0:12", @"connect:12:0", @"null", @"select:5:6"];
    CHECK([backend.calls isEqualToArray:expected], "successful backend call order and numeric arguments preserved");
    CHECK(CountLogs(logs, @"phase=begin") == 5, "every actual operation logs a begin");
    CHECK(CountLogs(logs, @"phase=end") == 5, "every actual operation logs an end");
    CHECK(CountLogs(logs, @"thread=main") == logs.count, "logs report main thread without its name");
}

static void TestConnectClassification(void) {
    const int ordinaryFailures[] = {22, 70004, 70006, 220001, 419999, 470000, -1,
                                   -1633397924, 1937010544, INT_MIN, INT_MAX};
    for (NSUInteger index = 0; index < sizeof(ordinaryFailures) / sizeof(ordinaryFailures[0]); index++) {
        FakeAudioBackend *backend = [FakeAudioBackend new];
        backend.connectStatus = ordinaryFailures[index];
        NSMutableArray<NSString *> *logs = [NSMutableArray array];
        AKAudioDeviceController *controller = MakeController(backend, logs);
        CHECK([controller connectSource:88 destination:0] == ordinaryFailures[index], "non-audio connect preserves raw error");
        CHECK(!controller.hasFailed && controller.lastFailureStatus == 0, "non-audio connect does not poison audio state");
        CHECK(backend.nullCount == 0, "non-audio connect never triggers null fallback");
        CHECK(CountLogs(logs, @"coreaudio_") == 0, "ordinary PJ errors are not falsely decoded as CoreAudio");
        backend.connectStatus = 0;
        CHECK([controller connectSource:89 destination:0] == 0, "valid route remains usable after stale-port error");
        CHECK(backend.connectCount == 2, "non-audio failure allows later connect");
    }

    const int audioFailures[] = {420000, 420001, 420007, 440050, 469999, stopStatus};
    for (NSUInteger index = 0; index < sizeof(audioFailures) / sizeof(audioFailures[0]); index++) {
        int expectedStatus = audioFailures[index];
        FakeAudioBackend *backend = [FakeAudioBackend new];
        backend.connectStatus = expectedStatus;
        NSMutableArray<NSString *> *logs = [NSMutableArray array];
        AKAudioDeviceController *controller = MakeController(backend, logs);
        __block NSUInteger notifications = 0;
        controller.failureHandler = ^(int status) {
            notifications++;
            CHECK(status == expectedStatus, "connect notification preserves audio status");
        };
        CHECK([controller connectSource:0 destination:21] == audioFailures[index], "audio connect returns first raw failure");
        CHECK([controller connectSource:21 destination:0] == audioFailures[index], "audio error skips second route attempt");
        CHECK(controller.hasFailed && backend.connectCount == 1, "audio connect failure latches before another attempt");
        CHECK(backend.nullCount == 1 && notifications == 1, "audio connect has one fallback and notification");
        CHECK(CountLogs(logs, @"operation=connect phase=begin") == 1, "only the actual connect logs a begin");
        CHECK(CountLogs(logs, @"operation=null-fallback phase=end") == 1, "fallback logs its result");
    }
}

static void TestExternalReporting(void) {
    FakeAudioBackend *backend = [FakeAudioBackend new];
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    AKAudioDeviceController *controller = MakeController(backend, logs);
    __block NSUInteger notifications = 0;
    controller.failureHandler = ^(int status) { (void)status; notifications++; };
    [controller reportAudioFailure:0 operation:@"make-call"];
    [controller reportAudioFailure:70004 operation:@"make-call"];
    CHECK(!controller.hasFailed && backend.calls.count == 0, "external success and SIP errors do not touch audio");
    [controller reportAudioFailure:stopStatus operation:@"make-call"];
    CHECK(controller.hasFailed && controller.lastFailureStatus == stopStatus, "SDK bypass audio error latches");
    CHECK(backend.nullCount == 1 && notifications == 1, "SDK bypass failure triggers one fallback and notification");
    [controller reportAudioFailure:420007 operation:@"answer-call"];
    [controller reportAudioFailure:stopStatus operation:@"media-state"];
    CHECK(controller.lastFailureStatus == stopStatus, "repeated reports preserve first failure");
    CHECK(backend.nullCount == 1 && notifications == 1, "repeated SDK reports do not retry or notify again");
    [controller reportAudioFailure:stopStatus operation:@"sip:PRIVATE@example.invalid /Users/private/secret"];
    CHECK([logs.lastObject containsString:@"operation=external"], "unknown diagnostic label is sanitized");
    CHECK(CountLogs(logs, @"PRIVATE") == 0 && CountLogs(logs, @"/Users/") == 0,
          "reporting API cannot inject private diagnostic strings");
    CHECK([AKAudioDeviceController isAudioDeviceFailure:stopStatus], "classifier exposes known negative audio error");
    CHECK([AKAudioDeviceController isAudioDeviceFailure:420007], "classifier exposes PJMEDIA audio error");
    CHECK(![AKAudioDeviceController isAudioDeviceFailure:70004], "classifier rejects PJ_EINVAL");
    CHECK(![AKAudioDeviceController isAudioDeviceFailure:-1], "classifier does not guess arbitrary negative errors");
}

static void TestDiagnostics(void) {
    FakeAudioBackend *backend = [FakeAudioBackend new];
    backend.selectStatus = stopStatus;
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    AKAudioDeviceController *controller = MakeController(backend, logs);
    [controller selectInput:13 output:17];
    CHECK(CountLogs(logs, @"status=-1936570544") == 1, "diagnostic retains exact observed raw error");
    CHECK(CountLogs(logs, @"coreaudio_osstatus=1937010544") == 1, "CoreAudio inverse uses 440000 minus raw status");
    CHECK(CountLogs(logs, @"coreaudio_fourcc='stop'") == 1, "known CoreAudio four-character code decoded exactly");
    CHECK(CountLogs(logs, @"coreaudio_symbol=kAudioHardwareNotRunningError") == 1, "stop uses correct CoreAudio symbol");
    CHECK(CountLogs(logs, @"operation=null-fallback phase=begin") == 1, "fallback begin is logged");
    CHECK(CountLogs(logs, @"operation=null-fallback phase=end") == 1, "fallback end is logged");
    CHECK(CountLogs(logs, @"input=13 output=17") == logs.count, "operation diagnostics use numeric selection IDs");
    for (NSString *entry in logs) {
        NSRange durationRange = [entry rangeOfString:@"duration_ms="];
        CHECK(durationRange.location != NSNotFound, "each diagnostic has duration field");
        if (durationRange.location != NSNotFound) {
            NSString *suffix = [entry substringFromIndex:NSMaxRange(durationRange)];
            double duration = suffix.doubleValue;
            CHECK(duration >= 0.0, "monotonic operation duration is non-negative");
        }
        CHECK(![entry containsString:@"PRIVATE_BACKEND"] && ![entry containsString:@"sip:"] &&
              ![entry containsString:@"/Users/"] && ![entry containsString:@"Microphone"],
              "diagnostics never format backend description or private names and paths");
    }
    [controller resetFailure];
    backend.selectStatus = 440050;
    [controller selectInput:13 output:17];
    CHECK(CountLogs(logs, @"coreaudio_candidate_osstatus=-50") == 1, "numeric audio inverse is an explicitly labeled candidate");

    [controller resetFailure];
    backend.selectStatus = 70004;
    [controller selectInput:13 output:17];
    CHECK(controller.hasFailed, "explicit selection failure latches even for generic PJ status");
    CHECK(CountLogs(logs, @"status=70004 duration_ms=") == 1, "generic selection failure is logged raw");
    NSString *genericEntry = logs[logs.count - 3];
    CHECK([genericEntry containsString:@"class=unclassified"], "generic selection error is not misidentified as CoreAudio");
}

static void TestKnownDeviceOperationReporting(void) {
    FakeAudioBackend *backend = [FakeAudioBackend new];
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    AKAudioDeviceController *controller = MakeController(backend, logs);
    __block NSUInteger notifications = 0;
    controller.failureHandler = ^(int status) {
        notifications++;
        CHECK(status == 70004, "known device operation reports generic raw error");
    };
    [controller reportDeviceFailure:0 operation:@"device-refresh"];
    CHECK(!controller.hasFailed && backend.calls.count == 0, "known device success is a no-op");
    [controller reportAudioFailure:70004 operation:@"make-call"];
    CHECK(!controller.hasFailed, "generic SDK failure remains unclassified");
    [controller reportDeviceFailure:70004 operation:@"device-refresh"];
    CHECK(controller.hasFailed && controller.lastFailureStatus == 70004,
          "failure from a known device operation latches even outside audio range");
    CHECK(backend.nullCount == 1 && notifications == 1, "known device operation has bounded fallback");
    [controller reportDeviceFailure:70006 operation:@"retry-selection"];
    CHECK(controller.lastFailureStatus == 70004 && backend.nullCount == 1 && notifications == 1,
          "additional known device reports preserve original episode");
    CHECK([controller selectInput:9 output:10] == 70004 && backend.selectCount == 0,
          "pre-selection failure prevents subsequent device open");
    [controller resetFailure];
    [controller reportDeviceFailure:70004 operation:@"retry-selection"];
    CHECK(backend.nullCount == 2 && notifications == 2, "failed explicit retry can rearm failure gate");
    CHECK(CountLogs(logs, @"operation=device-refresh phase=reported") == 2,
          "device refresh diagnostic label is accepted");
    CHECK(CountLogs(logs, @"operation=retry-selection phase=reported") == 2,
          "retry selection diagnostic label is accepted");
}

static void TestOutgoingCallAdmission(void) {
    FakeAudioBackend *backend = [FakeAudioBackend new];
    AKAudioDeviceController *controller = MakeController(backend, [NSMutableArray array]);
    CHECK(!controller.outgoingCallPending, "initial outgoing admission is clear");
    CHECK([controller beginOutgoingCall] && controller.outgoingCallPending, "first outgoing request reserves admission");
    CHECK(![controller beginOutgoingCall], "second queued outgoing request is rejected before SDK dispatch");
    CHECK(backend.calls.count == 0, "admission checks never touch hardware");
    [controller finishOutgoingCall];
    CHECK(!controller.outgoingCallPending, "matching completion releases outgoing admission");
    CHECK([controller beginOutgoingCall], "completion permits a later request");
    [controller resetFailure];
    CHECK(controller.outgoingCallPending, "explicit reset preserves in-flight outgoing work");
    CHECK(![controller beginOutgoingCall], "reset cannot admit a duplicate outgoing request");
    CHECK(backend.calls.count == 0, "finish and reset never touch hardware");

    __block NSUInteger notifications = 0;
    __weak AKAudioDeviceController *weakController = controller;
    controller.failureHandler = ^(int status) {
        notifications++;
        CHECK(status == stopStatus, "outgoing completion reports original classified failure");
        CHECK(![weakController beginOutgoingCall], "failure callback cannot admit another outgoing request");
    };
    // Models the owner's one main-thread completion: no dispatch, callback, or
    // yield is allowed between release and classification of the returned status.
    [controller finishOutgoingCall];
    [controller reportAudioFailure:stopStatus operation:@"make-call"];
    CHECK(!controller.outgoingCallPending && controller.hasFailed, "completed outgoing failure leaves a latched gate");
    CHECK(![controller beginOutgoingCall], "audio failure rejects new outgoing work after completion");
    CHECK(backend.nullCount == 1 && notifications == 1, "outgoing failure has one fallback and notification");
    [controller finishOutgoingCall];
    CHECK(controller.hasFailed, "repeated finish cannot clear an audio failure");

    [controller resetFailure];
    CHECK([controller beginOutgoingCall], "explicit retry after completion permits one request");
    [controller reportAudioFailure:stopStatus operation:@"make-call"];
    CHECK(controller.outgoingCallPending && controller.hasFailed, "failure reporting does not release pending SDK work");
    [controller resetFailure];
    CHECK(!controller.hasFailed && controller.outgoingCallPending, "reset clears failure but preserves pending barrier");
    CHECK(![controller beginOutgoingCall], "reset while failed and pending still rejects another request");
    [controller finishOutgoingCall];
    CHECK([controller beginOutgoingCall], "only matching completion releases reset pending work");
    [controller finishOutgoingCall];
    CHECK(!controller.outgoingCallPending && backend.selectCount == 0 && backend.connectCount == 0,
          "admission exercise never opens devices or connects conference ports");
    CHECK(backend.nullCount == 2 && notifications == 2, "only reported audio failures invoke the fake backend");
}

int main(void) {
    @autoreleasepool {
        TestSelectionFailureAndExplicitRetry();
        TestFailedFallbackAndNullStop();
        TestSuccessfulFlows();
        TestConnectClassification();
        TestExternalReporting();
        TestKnownDeviceOperationReporting();
        TestOutgoingCallAdmission();
        TestDiagnostics();
        if (failures != 0) {
            fprintf(stderr, "%lu of %lu audio device checks failed\n", (unsigned long)failures, (unsigned long)checks);
            return 1;
        }
        printf("PASS: %lu audio device controller checks; fake backend only, no PJSUA/CoreAudio/hardware\n",
               (unsigned long)checks);
    }
    return 0;
}
