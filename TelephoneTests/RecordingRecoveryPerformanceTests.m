#import <XCTest/XCTest.h>
#import "AppController.h"
#import "AKRecordingRecoveryIndex.h"
#import "AKStereoRecording.h"
#import "RecordingRecoveryController.h"
#include <stdio.h>
#include <sys/resource.h>
#include <unistd.h>

@interface AppController (RecoveryPerformanceInterface)
- (RecordingRecoveryController *)recordingRecoveryController;
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
- (IBAction)recoverRecordings:(id)sender;
@end

// Bypass AppController.init, which constructs the real defaults/accounts/SDK.
// This fixture only exercises production menu validation over an isolated cache.
@interface PerformanceRecoveryAppController : AppController
@property(nonatomic) RecordingRecoveryController *syntheticRecoveryController;
@end
@implementation PerformanceRecoveryAppController
- (RecordingRecoveryController *)recordingRecoveryController { return self.syntheticRecoveryController; }
@end

static double RecoveryCPUSeconds(struct timeval value) {
    return value.tv_sec + value.tv_usec / 1e6;
}

@interface RecordingRecoveryPerformanceTests : XCTestCase
@property(nonatomic) NSURL *scratch;
@end
@implementation RecordingRecoveryPerformanceTests
- (void)setUp {
    [super setUp];
    self.scratch = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"jps-recovery68-performance-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.scratch
        withIntermediateDirectories:YES attributes:nil error:nil]);
}
- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:self.scratch error:nil];
    [super tearDown];
}
- (void)measureSyntheticCollectionWithJobCount:(NSUInteger)jobCount {
    NSURL *root = [self.scratch URLByAppendingPathComponent:@"Recovery" isDirectory:YES];
    NSData *raw = [NSMutableData dataWithLength:64];
    for (NSUInteger i = 0; i < jobCount; i++) {
        @autoreleasepool {
            NSError *error = nil;
            NSURL *directory = AKCreateRecordingRecoveryDirectoryAtRoot(root, &error);
            XCTAssertNotNil(directory); XCTAssertNil(error);
            NSURL *local = [directory URLByAppendingPathComponent:@"local.wav"];
            NSURL *remote = [directory URLByAppendingPathComponent:@"remote.wav"];
            XCTAssertTrue([raw writeToURL:local atomically:YES]);
            XCTAssertTrue([raw writeToURL:remote atomically:YES]);
            NSURL *destination = [self.scratch URLByAppendingPathComponent:
                [NSString stringWithFormat:@"Synthetic recording %04lu.wav", (unsigned long)i]];
            XCTAssertTrue(AKPersistRecordingRecoveryJob(directory, local, remote, destination, &error));
            XCTAssertNil(error);
        }
    }

    NSObject *probeState = [NSObject new];
    __block NSUInteger loaderCalls = 0, mainCallbacksDuringScan = 0;
    __block BOOL loaderActive = NO;
    __block NSTimeInterval scanElapsed = 0;
    __block double scanUserCPU = 0, scanSystemCPU = 0;
    RecordingRecoveryController *recovery = [[RecordingRecoveryController alloc] initWithLoader:^NSArray *(NSError **error) {
        XCTAssertFalse(NSThread.isMainThread);
        @synchronized (probeState) { loaderCalls++; loaderActive = YES; }
        struct rusage before, after;
        getrusage(RUSAGE_SELF, &before);
        NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        NSArray *jobs = AKRecordingRecoveryJobsAtRootWithError(root, error);
        scanElapsed = NSProcessInfo.processInfo.systemUptime - started;
        getrusage(RUSAGE_SELF, &after);
        scanUserCPU = RecoveryCPUSeconds(after.ru_utime) - RecoveryCPUSeconds(before.ru_utime);
        scanSystemCPU = RecoveryCPUSeconds(after.ru_stime) - RecoveryCPUSeconds(before.ru_stime);
        @synchronized (probeState) { loaderActive = NO; }
        return jobs;
    }];
    dispatch_source_t probe = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(probe, DISPATCH_TIME_NOW, NSEC_PER_MSEC, NSEC_PER_MSEC / 10);
    dispatch_source_set_event_handler(probe, ^{
        @synchronized (probeState) { if (loaderActive) mainCallbacksDuringScan++; }
    });
    dispatch_resume(probe);
    XCTestExpectation *loaded = [self expectationWithDescription:@"Synthetic utility scan publishes"];
    [recovery.index refreshWithCompletion:^(BOOL published) {
        XCTAssertTrue(NSThread.isMainThread); XCTAssertTrue(published);
        XCTAssertNil(recovery.index.error); XCTAssertEqual(recovery.index.jobs.count, jobCount);
        [loaded fulfill];
    }];
    [self waitForExpectations:@[loaded] timeout:30];
    dispatch_source_cancel(probe);
    unsigned long long retainedRawBytes = 0;
    for (NSDictionary *job in recovery.index.jobs) retainedRawBytes += [job[@"retainedRawBytes"] unsignedLongLongValue];
    XCTAssertEqual(retainedRawBytes, jobCount * raw.length * 2);

    PerformanceRecoveryAppController *app = [PerformanceRecoveryAppController alloc];
    app.syntheticRecoveryController = recovery;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Recover Recordings…"
        action:@selector(recoverRecordings:) keyEquivalent:@""];
    const NSUInteger validations = 1000;
    NSUInteger callsBeforeValidation;
    @synchronized (probeState) { callsBeforeValidation = loaderCalls; }
    struct rusage before, after;
    getrusage(RUSAGE_SELF, &before);
    NSTimeInterval validationStarted = NSProcessInfo.processInfo.systemUptime;
    NSUInteger enabledValidations = 0;
    for (NSUInteger i = 0; i < validations; i++) if ([app validateMenuItem:item]) enabledValidations++;
    NSTimeInterval validationElapsed = NSProcessInfo.processInfo.systemUptime - validationStarted;
    getrusage(RUSAGE_SELF, &after);
    NSUInteger callsAfterValidation;
    @synchronized (probeState) { callsAfterValidation = loaderCalls; }
    XCTAssertEqual(callsBeforeValidation, 1u);
    XCTAssertEqual(enabledValidations, validations);
    XCTAssertEqual(callsAfterValidation, callsBeforeValidation, @"Cached menu validation must not launch a file scan");

    NSDictionary *metrics = @{
        @"scope": @"synthetic_first_utility_read_and_cached_menu_validation",
        @"filesystemCacheEvicted": @NO,
        @"pid": @(getpid()), @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
        @"jobCount": @(recovery.index.jobs.count), @"retainedRawBytes": @(retainedRawBytes),
        @"scanLoaderCalls": @(callsBeforeValidation), @"scanElapsedSeconds": @(scanElapsed),
        @"scanProcessUserCPUSeconds": @(scanUserCPU), @"scanProcessSystemCPUSeconds": @(scanSystemCPU),
        @"mainQueueProbeIntervalSeconds": @0.001, @"mainQueueCallbacksWhileScanActive": @(mainCallbacksDuringScan),
        @"cachedMenuValidationCount": @(validations), @"cachedMenuValidationElapsedSeconds": @(validationElapsed),
        @"cachedMenuValidationProcessUserCPUSeconds": @(RecoveryCPUSeconds(after.ru_utime) - RecoveryCPUSeconds(before.ru_utime)),
        @"cachedMenuValidationProcessSystemCPUSeconds": @(RecoveryCPUSeconds(after.ru_stime) - RecoveryCPUSeconds(before.ru_stime)),
        @"scanLoaderCallsAfterMenuValidation": @(callsAfterValidation)
    };
    NSData *JSON = [NSJSONSerialization dataWithJSONObject:metrics options:NSJSONWritingSortedKeys error:nil];
    printf("JPS_RECOVERY68_PERFORMANCE %s\n", [[NSString alloc] initWithData:JSON encoding:NSUTF8StringEncoding].UTF8String);
    fflush(stdout);
    [recovery.index invalidate];
    app.syntheticRecoveryController = nil;
}
- (void)testSynthetic100JobScanAndCachedMenuValidationMeasurements {
    [self measureSyntheticCollectionWithJobCount:100];
}
- (void)testSynthetic500JobScanAndCachedMenuValidationMeasurements {
    [self measureSyntheticCollectionWithJobCount:500];
}
@end
