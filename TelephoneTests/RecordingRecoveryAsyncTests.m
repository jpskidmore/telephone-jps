#import <XCTest/XCTest.h>
#import "AKStereoRecording.h"
#include <errno.h>

// A per-attempt forwarding value replaces only this synthetic destination's
// security-scope boundary. There is no process-wide method replacement.
@interface RA68ScopeURL : NSObject <NSCopying>
@property(nonatomic) NSURL *URL;
@property(nonatomic) BOOL granted, startedOffMain, stoppedOnMain;
@property(nonatomic) NSUInteger starts, stops;
@property(nonatomic) dispatch_semaphore_t releaseGate;
@property(nonatomic) XCTestExpectation *entered;
@property(nonatomic, copy) dispatch_block_t extensionRead;
@end
@implementation RA68ScopeURL
- (BOOL)isKindOfClass:(Class)class { return class == NSURL.class || [super isKindOfClass:class]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (id)forwardingTargetForSelector:(SEL)selector { return self.URL; }
- (NSString *)pathExtension { if (self.extensionRead) self.extensionRead(); return self.URL.pathExtension; }
- (BOOL)startAccessingSecurityScopedResource {
    self.starts++; self.startedOffMain = !NSThread.isMainThread;
    [self.entered fulfill];
    if (self.releaseGate) dispatch_semaphore_wait(self.releaseGate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    return self.granted;
}
- (void)stopAccessingSecurityScopedResource { self.stops++; self.stoppedOnMain = NSThread.isMainThread; }
@end

@interface RecordingRecoveryAsyncTests : XCTestCase
@property(nonatomic) NSURL *scratch, *root;
@end
@implementation RecordingRecoveryAsyncTests
- (void)setUp {
    [super setUp];
    self.scratch = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    self.root = [self.scratch URLByAppendingPathComponent:@"Recovery" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.scratch withIntermediateDirectories:YES attributes:nil error:nil]);
}
- (void)drain {
    XCTestExpectation *done = [self expectationWithDescription:@"all admitted work drained"];
    AKWaitForPendingRecordingFinalizations(^{ XCTAssertTrue(NSThread.isMainThread); [done fulfill]; });
    [self waitForExpectations:@[done] timeout:7];
}
- (void)tearDown {
    [self drain];
    [NSFileManager.defaultManager removeItemAtURL:self.scratch error:nil];
    [super tearDown];
}
- (NSURL *)makeJob:(NSString *)name {
    NSURL *directory = AKCreateRecordingRecoveryDirectoryAtRoot(self.root, nil);
    NSData *raw = [@"Synthetic retained raw audio" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *local = [directory URLByAppendingPathComponent:@"local.wav"], *remote = [directory URLByAppendingPathComponent:@"remote.wav"];
    XCTAssertTrue([raw writeToURL:local atomically:YES]); XCTAssertTrue([raw writeToURL:remote atomically:YES]);
    XCTAssertTrue(AKPersistRecordingRecoveryJob(directory, local, remote, [self.scratch URLByAppendingPathComponent:name], nil));
    return directory;
}
- (NSDictionary *)jobAt:(NSURL *)directory {
    for (NSDictionary *job in AKRecordingRecoveryJobsAtRoot(self.root))
        if ([job[@"directoryURL"] isEqual:directory.URLByResolvingSymlinksInPath.standardizedURL]) return job;
    XCTFail(@"Missing synthetic job"); return nil;
}
- (NSDictionary *)manifest:(NSURL *)directory {
    return [NSDictionary dictionaryWithContentsOfURL:[directory URLByAppendingPathComponent:@"recovery.plist"]];
}
- (RA68ScopeURL *)blockedScope:(NSString *)filename {
    RA68ScopeURL *scope = [RA68ScopeURL new]; scope.granted = YES;
    scope.URL = [self.scratch URLByAppendingPathComponent:filename];
    scope.releaseGate = dispatch_semaphore_create(0);
    scope.entered = [self expectationWithDescription:@"utility worker reached scope boundary"];
    return scope;
}
- (void)startBlocker:(RA68ScopeURL *)scope {
    NSURL *directory = [self makeJob:NSUUID.UUID.UUIDString];
    // Existing output avoids passing the forwarding value into AudioToolbox.
    XCTAssertTrue([NSData.data writeToURL:scope.URL atomically:YES]);
    AKRetryRecordingRecoveryJob([self jobAt:directory], (NSURL *)scope, ^(BOOL success) { XCTAssertFalse(success); });
    [self waitForExpectations:@[scope.entered] timeout:3];
    XCTAssertTrue(scope.startedOffMain);
}
- (void)testBlockedRetryKeepsMainResponsiveAndDrainsNotificationScopeAndCompletion {
    NSURL *directory = [self makeJob:@"Before.wav"];
    NSDictionary *job = [self jobAt:directory];
    RA68ScopeURL *scope = [self blockedScope:@"Exists.wav"];
    XCTAssertTrue([NSData.data writeToURL:scope.URL atomically:YES]);
    NSMutableArray *events = [NSMutableArray array];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKRecordingExportDidFailNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (![note.userInfo[@"recoveryDirectoryURL"] isEqual:job[@"directoryURL"]]) return;
        XCTAssertTrue(NSThread.isMainThread); XCTAssertEqual(scope.stops, 0u);
        XCTAssertEqualObjects([self manifest:directory][@"state"], @"failed");
        [events addObject:@"notification"];
    }];
    XCTestExpectation *finished = [self expectationWithDescription:@"retry completed"], *drained = [self expectationWithDescription:@"drain completed"];
    AKRetryRecordingRecoveryJob(job, (NSURL *)scope, ^(BOOL success) {
        XCTAssertFalse(success); XCTAssertTrue(NSThread.isMainThread);
        XCTAssertEqual(scope.stops, 1u); XCTAssertTrue(scope.stoppedOnMain);
        XCTAssertEqualObjects(events, (@[@"notification"])); [events addObject:@"completion"]; [finished fulfill];
    });
    AKWaitForPendingRecordingFinalizations(^{ XCTAssertEqualObjects(events, (@[@"notification", @"completion"])); [events addObject:@"drain"]; [drained fulfill]; });
    [self waitForExpectations:@[scope.entered] timeout:3];
    XCTAssertTrue(scope.startedOffMain); XCTAssertEqual(events.count, 0u);
    XCTAssertNil(AKClaimRecordingJob(directory, nil), @"Claim spans the blocked operation");
    XCTestExpectation *mainPing = [self expectationWithDescription:@"main remains responsive"], *duplicate = [self expectationWithDescription:@"duplicate rejected"];
    dispatch_async(dispatch_get_main_queue(), ^{ [mainPing fulfill]; });
    AKRetryRecordingRecoveryJob(job, scope.URL, ^(BOOL success) { XCTAssertFalse(success); XCTAssertEqual(events.count, 0u); [duplicate fulfill]; });
    [self waitForExpectations:@[mainPing, duplicate] timeout:3];
    dispatch_semaphore_signal(scope.releaseGate);
    [self waitForExpectations:@[finished, drained] timeout:5];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    NSError *remembered = [self jobAt:directory][@"lastError"];
    XCTAssertEqualObjects(remembered.domain, NSCocoaErrorDomain); XCTAssertEqual(remembered.code, NSFileWriteFileExistsError);
}
- (void)testAdmissionCopiesMutableSnapshotBeforeWorkerReadsIt {
    RA68ScopeURL *blocker = [self blockedScope:@"Blocker.wav"]; [self startBlocker:blocker];
    NSURL *chosen = [self makeJob:@"Chosen.wav"], *other = [self makeJob:@"Other.wav"];
    NSMutableDictionary *snapshot = [[self jobAt:chosen] mutableCopy];
    NSMutableString *identity = [snapshot[@"directoryIdentity"] mutableCopy]; snapshot[@"directoryIdentity"] = identity;
    NSURL *existing = [self.scratch URLByAppendingPathComponent:@"Chosen exists.wav"];
    XCTAssertTrue([NSData.data writeToURL:existing atomically:YES]);
    XCTestExpectation *done = [self expectationWithDescription:@"immutable choice completed"];
    AKRetryRecordingRecoveryJob(snapshot, existing, ^(BOOL success) { XCTAssertFalse(success); [done fulfill]; });
    snapshot[@"directoryURL"] = other; [identity setString:@"forged after admission"];
    dispatch_semaphore_signal(blocker.releaseGate); [self waitForExpectations:@[done] timeout:5];
    XCTAssertEqualObjects([self manifest:chosen][@"state"], @"failed");
    XCTAssertNil([self manifest:other][@"state"]);
}
- (void)testBusyAndStaleRejectionsAreAsynchronousWithoutFailureNotification {
    NSURL *directory = [self makeJob:@"Busy.wav"]; NSDictionary *job = [self jobAt:directory];
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil); XCTAssertNotNil(owner);
    __block NSUInteger notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKRecordingExportDidFailNotification object:nil queue:nil usingBlock:^(NSNotification *note) { notifications++; }];
    NSMutableDictionary *stale = [job mutableCopy]; stale[@"directoryIdentity"] = @"stale identity";
    __block BOOL returned = NO;
    XCTestExpectation *busyDone = [self expectationWithDescription:@"busy rejected"], *staleDone = [self expectationWithDescription:@"stale rejected"];
    AKRetryRecordingRecoveryJob(job, [self.scratch URLByAppendingPathComponent:@"Busy output.wav"], ^(BOOL success) {
        XCTAssertTrue(returned); XCTAssertTrue(NSThread.isMainThread); XCTAssertFalse(success); [busyDone fulfill];
    });
    AKRetryRecordingRecoveryJob(stale, [self.scratch URLByAppendingPathComponent:@"Stale output.wav"], ^(BOOL success) {
        XCTAssertTrue(returned); XCTAssertFalse(success); [staleDone fulfill];
    });
    returned = YES; [self waitForExpectations:@[busyDone, staleDone] timeout:3];
    XCTAssertEqual(notifications, 0u); XCTAssertNotNil(owner.directoryURL);
    [NSNotificationCenter.defaultCenter removeObserver:observer]; AKFinishRecordingRecoveryJob(owner, NO);
}
- (void)testDiscardAdmissionAndItsMainCompletionAreIncludedInDrain {
    RA68ScopeURL *blocker = [self blockedScope:@"Block discard.wav"]; [self startBlocker:blocker];
    NSURL *directory = [self makeJob:@"Discard.wav"];
    __block BOOL completed = NO;
    XCTestExpectation *done = [self expectationWithDescription:@"discard drained"];
    AKDiscardPendingRecordingRecoveryJobAsync([self jobAt:directory], ^(BOOL success, NSError *error) {
        XCTAssertTrue(success); XCTAssertNil(error); XCTAssertTrue(NSThread.isMainThread);
        XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:directory.path]); completed = YES;
    });
    AKWaitForPendingRecordingFinalizations(^{ XCTAssertTrue(completed); [done fulfill]; });
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:directory.path]); XCTAssertFalse(completed);
    dispatch_semaphore_signal(blocker.releaseGate); [self waitForExpectations:@[done] timeout:5];
}
- (void)testOwnedFailureKeepsClaimUntilWorkerAndPersistsActualErrorBeforeCompletion {
    RA68ScopeURL *blocker = [self blockedScope:@"Block finish.wav"]; [self startBlocker:blocker];
    NSURL *directory = [self makeJob:@"Owned.wav"];
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil); XCTAssertNotNil(owner);
    NSError *original = [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:@{NSLocalizedDescriptionKey:@"Synthetic owned write denial"}];
    XCTestExpectation *done = [self expectationWithDescription:@"owned failure completed"];
    AKFinishRecordingRecoveryJobAsync(owner, NO, [self.scratch URLByAppendingPathComponent:@"Owned.wav"], original, ^{
        NSDictionary *job = [self jobAt:directory]; NSError *remembered = job[@"lastError"];
        XCTAssertEqualObjects(remembered.domain, original.domain); XCTAssertEqual(remembered.code, original.code);
        XCTAssertEqualObjects(remembered.localizedDescription, original.localizedDescription); [done fulfill];
    });
    XCTAssertNil(AKClaimRecordingJob(directory, nil));
    dispatch_semaphore_signal(blocker.releaseGate); [self waitForExpectations:@[done] timeout:5];
}
- (void)testLegacyReportCannotRewriteReplacementAfterAdmission {
    RA68ScopeURL *blocker = [self blockedScope:@"Block replacement.wav"]; [self startBlocker:blocker];
    NSURL *directory = [self makeJob:@"Original.wav"];
    NSError *original = [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:nil];
    AKReportRecordingExportFailure(directory, [self.scratch URLByAppendingPathComponent:@"Original.wav"], original);
    NSURL *retired = [self.root URLByAppendingPathComponent:@"Retired" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager moveItemAtURL:directory toURL:retired error:nil]);
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:nil]);
    NSData *raw = [@"Replacement" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([raw writeToURL:[directory URLByAppendingPathComponent:@"local.wav"] atomically:YES]);
    XCTAssertTrue([raw writeToURL:[directory URLByAppendingPathComponent:@"remote.wav"] atomically:YES]);
    dispatch_semaphore_signal(blocker.releaseGate); [self drain];
    XCTAssertNil([self manifest:directory]);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"local.wav"]], raw);
}
- (void)testLegacyReportCannotRewriteNewerAttemptAtSameInode {
    RA68ScopeURL *blocker = [self blockedScope:@"Block revision.wav"]; [self startBlocker:blocker];
    NSURL *directory = [self makeJob:@"Earlier.wav"];
    AKReportRecordingExportFailure(directory, [self.scratch URLByAppendingPathComponent:@"Earlier.wav"], nil);
    AKRecordingJobOwnership *newOwner = AKClaimRecordingJob(directory, nil); XCTAssertNotNil(newOwner);
    XCTAssertTrue(AKPersistOwnedRecordingRecoveryJob(newOwner, [directory URLByAppendingPathComponent:@"local.wav"],
        [directory URLByAppendingPathComponent:@"remote.wav"], [self.scratch URLByAppendingPathComponent:@"Newer.wav"], AKRecordingJobPhaseFinalising, nil));
    AKFinishRecordingRecoveryJob(newOwner, NO);
    NSString *revision = [self manifest:directory][@"revision"];
    dispatch_semaphore_signal(blocker.releaseGate); [self drain];
    XCTAssertEqualObjects([self manifest:directory][@"revision"], revision);
    XCTAssertEqualObjects([self manifest:directory][@"destination"], [self.scratch URLByAppendingPathComponent:@"Newer.wav"].path);
}
- (void)testNestedFinishAdmissionKeepsEarlierDrainPendingThroughMainCompletion {
    NSURL *directory = [self makeJob:@"Nested.wav"];
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil);
    __block BOOL finished = NO;
    XCTestExpectation *done = [self expectationWithDescription:@"nested cleanup drained"];
    NSURL *missing = [self.scratch URLByAppendingPathComponent:@"Missing.wav"];
    AKMergeMonoRecordingsIntoStereoAsync(missing, missing, [self.scratch URLByAppendingPathComponent:@"Bad.invalid"], ^(BOOL success) {
        XCTAssertFalse(success);
        AKFinishRecordingRecoveryJobAsync(owner, NO, [self.scratch URLByAppendingPathComponent:@"Nested.wav"], nil, ^{ finished = YES; });
    });
    AKWaitForPendingRecordingFinalizations(^{ XCTAssertTrue(finished); XCTAssertEqualObjects([self manifest:directory][@"state"], @"failed"); [done fulfill]; });
    [self waitForExpectations:@[done] timeout:5];
}
- (void)testDestinationAppearingAfterPreflightIsNeverOverwrittenAndKeepsStaging {
    NSURL *directory = [self makeJob:@"Race.wav"];
    // One mono 16-bit PCM frame; conversion and exclusive publication stay real.
    const unsigned char bytes[] = {
        'R','I','F','F',38,0,0,0,'W','A','V','E','f','m','t',' ',16,0,0,0,
        1,0,1,0,64,31,0,0,128,62,0,0,2,0,16,0,'d','a','t','a',2,0,0,0,16,0
    };
    NSData *wave = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    XCTAssertTrue([wave writeToURL:[directory URLByAppendingPathComponent:@"local.wav"] atomically:YES]);
    XCTAssertTrue([wave writeToURL:[directory URLByAppendingPathComponent:@"remote.wav"] atomically:YES]);
    RA68ScopeURL *scope = [RA68ScopeURL new]; scope.URL = [self.scratch URLByAppendingPathComponent:@"Appeared.wav"];
    NSData *external = [@"External file created after preflight" dataUsingEncoding:NSUTF8StringEncoding];
    scope.extensionRead = ^{ XCTAssertTrue([external writeToURL:scope.URL atomically:YES]); };
    XCTestExpectation *done = [self expectationWithDescription:@"exclusive publication refused replacement"];
    AKRetryRecordingRecoveryJob([self jobAt:directory], (NSURL *)scope, ^(BOOL success) {
        XCTAssertFalse(success); XCTAssertEqual(scope.stops, 0u);
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:scope.URL], external);
        NSError *remembered = [self jobAt:directory][@"lastError"];
        XCTAssertEqualObjects(remembered.domain, NSPOSIXErrorDomain); XCTAssertEqual(remembered.code, EEXIST);
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"local.wav"]], wave);
        NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory.path error:nil];
        NSArray *staged = [names filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@", @".export-"]];
        XCTAssertEqual(staged.count, 1u);
        [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:5];
    scope.extensionRead = nil;
}
@end
