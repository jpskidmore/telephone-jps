#import <XCTest/XCTest.h>
#import "AKStereoRecording.h"
#include <errno.h>

@interface AKRecordingJobOwnership (AttachmentJournalTests)
- (void)releaseClaim;
@end

@interface RecordingAttachmentJournalTests : XCTestCase
@property(nonatomic) NSURL *scratch, *root;
@property(nonatomic, copy) void (^reservationDidCreate)(NSURL *);
@end
@implementation RecordingAttachmentJournalTests
- (void)setUp {
    [super setUp];
    self.scratch = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    self.root = [self.scratch URLByAppendingPathComponent:@"Recovery" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.scratch withIntermediateDirectories:YES attributes:nil error:nil]);
    AKSetRecordingAttachmentPublisher(nil);
}
- (void)drain {
    XCTestExpectation *done = [self expectationWithDescription:@"recording/catalogue drain"];
    AKWaitForPendingRecordingFinalizations(^{ [done fulfill]; });
    [self waitForExpectations:@[done] timeout:8];
}
- (void)tearDown {
    [self drain]; AKSetRecordingAttachmentPublisher(nil);
    [NSFileManager.defaultManager removeItemAtURL:self.scratch error:nil];
    [super tearDown];
}
- (NSDictionary *)manifest:(NSURL *)directory {
    return [NSDictionary dictionaryWithContentsOfURL:[directory URLByAppendingPathComponent:@"recovery.plist"]];
}
- (NSDictionary *)makeJob:(NSString *)filename reserved:(BOOL)reserved {
    NSURL *directory = AKCreateRecordingRecoveryDirectoryAtRoot(self.root, nil);
    // Valid mono PCM, one synthetic frame. There is no SIP, microphone or data-store access.
    const unsigned char bytes[] = {'R','I','F','F',38,0,0,0,'W','A','V','E','f','m','t',' ',16,0,0,0,
        1,0,1,0,64,31,0,0,128,62,0,0,2,0,16,0,'d','a','t','a',2,0,0,0,16,0};
    NSData *wave = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    NSURL *local = [directory URLByAppendingPathComponent:@"local.wav"], *remote = [directory URLByAppendingPathComponent:@"remote.wav"];
    XCTAssertTrue([wave writeToURL:local atomically:YES]); XCTAssertTrue([wave writeToURL:remote atomically:YES]);
    NSURL *destination = [self.scratch URLByAppendingPathComponent:filename];
    if (reserved) {
        destination = AKReserveRecordingURL(self.scratch, filename.stringByDeletingPathExtension, filename.pathExtension, nil);
        XCTAssertNotNil(destination);
    }
    if (self.reservationDidCreate) self.reservationDidCreate(destination);
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil); XCTAssertNotNil(owner);
    XCTAssertTrue(AKSetOwnedRecordingIdentity(owner, @"call-exact", filename, nil));
    XCTAssertTrue(AKPersistOwnedRecordingRecoveryJob(owner, local, remote, destination, AKRecordingJobPhaseCapturing, nil));
    return @{@"directory": directory, @"local": local, @"remote": remote, @"destination": destination, @"owner": owner};
}
- (void)finish:(NSDictionary *)job succeeded:(BOOL)expected {
    XCTAssertTrue(AKPersistOwnedRecordingRecoveryJob(job[@"owner"], job[@"local"], job[@"remote"], job[@"destination"], AKRecordingJobPhaseFinalising, nil));
    XCTestExpectation *done = [self expectationWithDescription:@"owned export completed"];
    AKFinalizeOwnedRecordingAsync(job[@"owner"], job[@"local"], job[@"remote"], job[@"destination"], ^(BOOL success) {
        XCTAssertTrue(NSThread.isMainThread); XCTAssertEqual(success, expected); [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:8]; [self drain];
}
- (void)reconcile:(BOOL)expected {
    XCTestExpectation *done = [self expectationWithDescription:@"restart metadata repair"];
    AKReconcilePendingRecordingAttachmentsAtRoot(self.root, ^(BOOL success, NSError *error) {
        XCTAssertTrue(NSThread.isMainThread); XCTAssertEqual(success, expected);
        if (!expected) XCTAssertNotNil(error); [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:8]; [self drain];
}
- (void)testOpaqueIdentitySurvivesTransitionsAndCannotBeRebound {
    NSDictionary *job = [self makeJob:@"Identity.wav" reserved:YES];
    NSError *error = nil;
    XCTAssertFalse(AKSetOwnedRecordingIdentity(job[@"owner"], @"another-call", @"another-segment", &error));
    XCTAssertEqual(error.code, ESTALE);
    XCTAssertTrue(AKPersistOwnedRecordingRecoveryJob(job[@"owner"], job[@"local"], job[@"remote"], job[@"destination"], AKRecordingJobPhaseFinalising, nil));
    AKFinishRecordingRecoveryJob(job[@"owner"], NO);
    NSDictionary *manifest = [self manifest:job[@"directory"]];
    XCTAssertEqualObjects(manifest[@"callIdentifier"], @"call-exact");
    XCTAssertEqualObjects(manifest[@"segmentIdentifier"], @"Identity.wav");
    NSDictionary *snapshot = AKRecordingRecoveryJobsAtRoot(self.root).firstObject;
    XCTAssertEqualObjects(snapshot[@"callIdentifier"], @"call-exact");
    XCTAssertEqualObjects(snapshot[@"segmentIdentifier"], @"Identity.wav");
}
- (void)testAvailablePublicationIsDurableBeforeRawCleanupAndMainCompletion {
    NSDictionary *job = [self makeJob:@"Complete.wav" reserved:YES];
    __block NSUInteger available = 0;
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) {
        XCTAssertFalse(NSThread.isMainThread);
        if ([attachment[@"state"] isEqual:@"available"]) {
            available++;
            XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
            XCTAssertEqualObjects(attachment[@"callIdentifier"], @"call-exact");
            XCTAssertEqualObjects(attachment[@"segmentIdentifier"], @"Complete.wav");
            XCTAssertEqualObjects([NSURL fileURLWithPath:attachment[@"destination"]].URLByResolvingSymlinksInPath,
                                  [job[@"destination"] URLByResolvingSymlinksInPath]);
            XCTAssertTrue([attachment[@"outputBookmark"] isKindOfClass:NSData.class]);
            XCTAssertEqual([attachment[@"outputIdentity"][@"sha256"] length], 64u);
            XCTAssertTrue([attachment[@"outputIdentity"][@"dev"] isKindOfClass:NSString.class]);
            XCTAssertGreaterThan([attachment[@"outputIdentity"][@"size"] unsignedIntegerValue], 0u);
        }
        return YES;
    });
    [self finish:job succeeded:YES];
    XCTAssertEqual(available, 1u);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[job[@"directory"] path]]);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"destination"] path]]);
}
- (void)testCatalogueFailureRetainsExactOutputAndRestartRepairsWithoutEncodingOrOverwrite {
    NSDictionary *job = [self makeJob:@"Repair.wav" reserved:YES];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) {
        if (![attachment[@"state"] isEqual:@"available"]) return YES;
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOSPC userInfo:nil]; return NO;
    });
    [self finish:job succeeded:NO];
    NSData *exported = [NSData dataWithContentsOfURL:job[@"destination"]];
    XCTAssertGreaterThan(exported.length, 0u);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
    XCTAssertEqualObjects([self manifest:job[@"directory"]][@"exportJournal"][@"phase"], @"ready");
    // Break raw audio deliberately: metadata-only reconciliation must still succeed.
    XCTAssertTrue([[@"invalid raw" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:job[@"local"] atomically:YES]);
    __block NSUInteger available = 0;
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) {
        if ([attachment[@"state"] isEqual:@"available"]) available++; return YES;
    });
    [self reconcile:YES];
    XCTAssertEqual(available, 1u);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:job[@"destination"]], exported);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[job[@"directory"] path]]);
}
- (void)testCrashAfterOutputFsyncBeforeReadyJournalCanRepairExactPublishingProof {
    NSDictionary *job = [self makeJob:@"Crash.wav" reserved:YES];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return ![attachment[@"state"] isEqual:@"available"]; });
    [self finish:job succeeded:NO];
    NSMutableDictionary *manifest = [[self manifest:job[@"directory"]] mutableCopy];
    NSMutableDictionary *journal = [manifest[@"exportJournal"] mutableCopy]; journal[@"phase"] = @"publishing"; manifest[@"exportJournal"] = journal;
    XCTAssertTrue([manifest writeToURL:[job[@"directory"] URLByAppendingPathComponent:@"recovery.plist"] atomically:YES]);
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return YES; });
    [self reconcile:YES];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[job[@"directory"] path]]);
}
- (void)testSamePathReplacementIsNeverReconciledOrOverwritten {
    NSDictionary *job = [self makeJob:@"Replacement.wav" reserved:YES];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return ![attachment[@"state"] isEqual:@"available"]; });
    [self finish:job succeeded:NO];
    NSData *foreign = [@"different file replacing exact output" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([foreign writeToURL:job[@"destination"] atomically:YES]);
    __block NSUInteger available = 0;
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { if ([attachment[@"state"] isEqual:@"available"]) available++; return YES; });
    [self reconcile:NO];
    XCTAssertEqual(available, 0u); XCTAssertEqualObjects([NSData dataWithContentsOfURL:job[@"destination"]], foreign);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
}
- (void)testChangedContentAtSameInodeIsNotCalledAvailable {
    NSDictionary *job = [self makeJob:@"Modified.wav" reserved:YES];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return ![attachment[@"state"] isEqual:@"available"]; });
    [self finish:job succeeded:NO];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:job[@"destination"] error:nil];
    [handle seekToFileOffset:0]; [handle writeData:[@"BAD!" dataUsingEncoding:NSUTF8StringEncoding]]; [handle closeFile];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return YES; });
    [self reconcile:NO];
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
}
- (void)testReservationReplacementBeforeOrdinaryExportIsPreserved {
    NSDictionary *job = [self makeJob:@"Reserved.wav" reserved:YES];
    NSData *foreign = [@"foreign replacement" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([foreign writeToURL:job[@"destination"] atomically:YES]);
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return YES; });
    [self finish:job succeeded:NO];
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:job[@"destination"]], foreign);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
}
- (void)testQueuedPublisherWorkParticipatesInDrain {
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    XCTestExpectation *entered = [self expectationWithDescription:@"catalogue worker entered"], *done = [self expectationWithDescription:@"catalogue drained"];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) {
        if (![attachment[@"state"] isEqual:@"finalising"]) return YES;
        [entered fulfill]; dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)); return YES;
    });
    // The publisher is pinned at claim admission. Configure this fixture before
    // constructing the owner, then block only its finalising transition.
    NSDictionary *job = [self makeJob:@"Drain.wav" reserved:YES];
    XCTAssertTrue(AKPersistOwnedRecordingRecoveryJob(job[@"owner"], job[@"local"], job[@"remote"], job[@"destination"], AKRecordingJobPhaseFinalising, nil));
    __block BOOL drained = NO;
    AKWaitForPendingRecordingFinalizations(^{ drained = YES; [done fulfill]; });
    [self waitForExpectations:@[entered] timeout:3]; XCTAssertFalse(drained);
    dispatch_semaphore_signal(gate); [self waitForExpectations:@[done] timeout:5];
    AKSetRecordingAttachmentPublisher(nil); AKFinishRecordingRecoveryJob(job[@"owner"], NO);
}
- (void)testRestartMarksAbandonedCaptureFailedAndRetainsBothTracks {
    NSDictionary *job = [self makeJob:@"Abandoned.wav" reserved:YES];
    // Process death releases a claim without destroying its raw tracks.
    AKRecordingJobOwnership *owner = job[@"owner"];
    [owner releaseClaim];
    __block NSDictionary *recorded = nil;
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { recorded = attachment; return YES; });
    [self reconcile:YES];
    XCTAssertEqualObjects(recorded[@"state"], @"failed");
    XCTAssertEqualObjects(recorded[@"segmentIdentifier"], @"Abandoned.wav");
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"remote"] path]]);
}
- (void)testRetryWithExistingExactOutputRepairsLinkWithoutReencoding {
    NSDictionary *job = [self makeJob:@"Retry repair.wav" reserved:YES];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return ![attachment[@"state"] isEqual:@"available"]; });
    [self finish:job succeeded:NO];
    NSDictionary *snapshot = AKRecordingRecoveryJobsAtRoot(self.root).firstObject;
    NSData *exported = [NSData dataWithContentsOfURL:job[@"destination"]];
    XCTAssertTrue([[@"invalid raw" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:job[@"local"] atomically:YES]);
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return YES; });
    XCTestExpectation *done = [self expectationWithDescription:@"metadata-only retry"];
    AKRetryRecordingRecoveryJob(snapshot, job[@"destination"], ^(BOOL success) { XCTAssertTrue(success); [done fulfill]; });
    [self waitForExpectations:@[done] timeout:8]; [self drain];
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:job[@"destination"]], exported);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[job[@"directory"] path]]);
}
- (void)testCompleteJournalCanReconcileWhenRawTracksWereExternallyRemoved {
    NSDictionary *job = [self makeJob:@"Raw removed.wav" reserved:YES];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return ![attachment[@"state"] isEqual:@"available"]; });
    [self finish:job succeeded:NO];
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:job[@"local"] error:nil]);
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:job[@"remote"] error:nil]);
    __block NSUInteger available = 0;
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { if ([attachment[@"state"] isEqual:@"available"]) available++; return YES; });
    [self reconcile:YES];
    XCTAssertEqual(available, 1u);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"destination"] path]]);
}
- (void)testTwoSegmentsOnOneCallPublishTheirCapturedSegmentIdentifiers {
    NSDictionary *first = [self makeJob:@"First segment.wav" reserved:YES], *second = [self makeJob:@"Second segment.wav" reserved:YES];
    NSMutableArray *segments = [NSMutableArray array];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) {
        if ([attachment[@"state"] isEqual:@"available"]) {
            XCTAssertEqualObjects(attachment[@"callIdentifier"], @"call-exact");
            [segments addObject:attachment[@"segmentIdentifier"]];
        }
        return YES;
    });
    [self finish:first succeeded:YES]; [self finish:second succeeded:YES];
    XCTAssertEqualObjects(segments, (@[@"First segment.wav", @"Second segment.wav"]));
}
- (void)testEmptyForeignReplacementBeforeCaptureIsNeverAdopted {
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return YES; });
    self.reservationDidCreate = ^(NSURL *destination) { XCTAssertTrue([NSData.data writeToURL:destination atomically:YES]); };
    NSDictionary *job = [self makeJob:@"Foreign empty.wav" reserved:YES];
    self.reservationDidCreate = nil;
    [self finish:job succeeded:NO];
    XCTAssertEqual([NSData dataWithContentsOfURL:job[@"destination"]].length, 0u);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
}
- (void)testSaveElsewhereCreatesRequestedFileAndPreservesEarlierExport {
    NSDictionary *job = [self makeJob:@"Earlier.wav" reserved:YES];
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { return ![attachment[@"state"] isEqual:@"available"]; });
    [self finish:job succeeded:NO];
    NSDictionary *snapshot = AKRecordingRecoveryJobsAtRoot(self.root).firstObject;
    NSData *earlier = [NSData dataWithContentsOfURL:job[@"destination"]];
    NSURL *chosen = [self.scratch URLByAppendingPathComponent:@"Actually chosen.wav"];
    __block NSURL *published = nil;
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) {
        if ([attachment[@"state"] isEqual:@"available"]) published = [NSURL fileURLWithPath:attachment[@"destination"]]; return YES;
    });
    XCTestExpectation *done = [self expectationWithDescription:@"save elsewhere honoured"];
    AKRetryRecordingRecoveryJob(snapshot, chosen, ^(BOOL success) { XCTAssertTrue(success); [done fulfill]; });
    [self waitForExpectations:@[done] timeout:8]; [self drain];
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:chosen.path]);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:job[@"destination"]], earlier);
    XCTAssertEqualObjects(published.URLByResolvingSymlinksInPath, chosen.URLByResolvingSymlinksInPath);
}
- (void)testMalformedManifestMakesReconciliationFailWithoutChangingRaw {
    NSDictionary *job = [self makeJob:@"Damaged.wav" reserved:YES];
    [job[@"owner"] releaseClaim];
    XCTAssertTrue([[@"damaged metadata" dataUsingEncoding:NSUTF8StringEncoding]
        writeToURL:[job[@"directory"] URLByAppendingPathComponent:@"recovery.plist"] atomically:YES]);
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) { XCTFail(@"Damaged identity must not be inferred"); return YES; });
    [self reconcile:NO];
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[job[@"local"] path]]);
}
- (void)testRetryPinsPublisherBeforeWorkerAdmissionAndCannotFallBackToUnlinkedCleanup {
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    XCTestExpectation *entered = [self expectationWithDescription:@"blocked catalogue worker"], *done = [self expectationWithDescription:@"admitted publisher completed"];
    __block NSUInteger available = 0;
    AKSetRecordingAttachmentPublisher(^BOOL(NSDictionary *attachment, NSError **error) {
        if ([attachment[@"segmentIdentifier"] isEqual:@"Blocker.wav"] && [attachment[@"state"] isEqual:@"finalising"]) {
            [entered fulfill]; dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        }
        if ([attachment[@"state"] isEqual:@"available"]) available++;
        return YES;
    });
    NSDictionary *blocker = [self makeJob:@"Blocker.wav" reserved:YES];
    XCTAssertTrue(AKPersistOwnedRecordingRecoveryJob(blocker[@"owner"], blocker[@"local"], blocker[@"remote"], blocker[@"destination"], AKRecordingJobPhaseFinalising, nil));
    [self waitForExpectations:@[entered] timeout:3];
    NSDictionary *job = [self makeJob:@"Admitted.wav" reserved:NO]; [job[@"owner"] releaseClaim];
    NSDictionary *snapshot = AKRecordingRecoveryJobsAtRoot(self.root).firstObject;
    AKRetryRecordingRecoveryJob(snapshot, job[@"destination"], ^(BOOL success) { XCTAssertTrue(success); [done fulfill]; });
    AKSetRecordingAttachmentPublisher(nil);
    dispatch_semaphore_signal(gate);
    [self waitForExpectations:@[done] timeout:8]; [self drain];
    XCTAssertEqual(available, 1u);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[job[@"directory"] path]]);
    AKFinishRecordingRecoveryJob(blocker[@"owner"], NO);
}
@end
