#import <XCTest/XCTest.h>
#import "AppController.h"
#import "AKRecordingCatalogue.h"
#import "AKStereoRecording.h"
#import "RecordingRecoveryController.h"
#import "Telephone-Swift.h"

@interface AppController (AttachmentIntegrationInterface)
- (void)configureRecordingAttachmentsWithCatalogue:(AKRecordingCatalogue *)catalogue;
- (void)refreshRecordingAttachmentsWithCompletion:(void (^)(NSError *))completion;
- (void)reconcileRecordingAttachmentsWithCompletion:(void (^)(BOOL, NSError *))completion;
- (void)refreshRecordingRecoveryJobsWithCompletion:(void (^)(BOOL, NSArray *, NSError *))completion;
- (RecordingRecoveryController *)recordingRecoveryController;
- (void)waitForRecordingFinalizations:(dispatch_block_t)completion;
@end

// Bypass AppController.init and application startup. Every directory reader and
// reconciliation boundary below is injected; no real profile is constructed.
@interface AttachmentIntegrationApp : AppController
@property(nonatomic) RecordingRecoveryController *syntheticRecovery;
@property(nonatomic, copy) void (^reconciliation)(BOOL, NSError *);
@property(nonatomic) NSUInteger reconciliationCount;
@end
@implementation AttachmentIntegrationApp
- (RecordingRecoveryController *)recordingRecoveryController { return self.syntheticRecovery; }
- (void)reconcileRecordingAttachmentsWithCompletion:(void (^)(BOOL, NSError *))completion {
    self.reconciliationCount++; self.reconciliation = completion;
}
@end

@interface RecordingAttachmentIntegrationTests : XCTestCase @end
@implementation RecordingAttachmentIntegrationTests
- (void)tearDown {
    AKSetRecordingAttachmentPublisher(nil);
    [super tearDown];
}
- (AKRecordingCatalogue *)catalogueWithReader:(AKRecordingCatalogueReader)reader {
    NSURL *URL = [NSURL fileURLWithPath:[@"/private/tmp" stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    return [[AKRecordingCatalogue alloc] initWithStoreURL:URL reader:reader writer:^BOOL(NSURL *URL, NSData *data, NSError **error) {
        XCTFail(@"A read-only integration check must not write"); return NO;
    }];
}
- (void)testConfigurationDoesNoDiskWorkAndQuitClosesHistoryActionAdmission {
    __block NSUInteger reads = 0;
    AKRecordingCatalogue *catalogue = [self catalogueWithReader:^NSData *(NSURL *URL, NSError **error) { reads++; return nil; }];
    AttachmentIntegrationApp *app = [AttachmentIntegrationApp alloc];
    [app configureRecordingAttachmentsWithCatalogue:catalogue];
    XCTAssertEqual(reads, 0u); XCTAssertTrue(AKRecordingAttachmentPublicationEnabled());
    RecordingHistoryActions *actions = [app valueForKey:@"recordingHistoryActions"];
    XCTAssertTrue(actions.actionsEnabled);
    [app setValue:@YES forKey:@"terminating"]; XCTAssertFalse(actions.actionsEnabled);
    [app setValue:@NO forKey:@"terminating"]; XCTAssertTrue(actions.actionsEnabled);
}
- (void)testReconciliationFinishesBeforeCatalogueAndRecoverySnapshotReads {
    __block NSUInteger catalogueReads = 0, recoveryReads = 0;
    AKRecordingCatalogue *catalogue = [self catalogueWithReader:^NSData *(NSURL *URL, NSError **error) {
        XCTAssertFalse(NSThread.isMainThread); catalogueReads++; return nil;
    }];
    AttachmentIntegrationApp *app = [AttachmentIntegrationApp alloc];
    app.syntheticRecovery = [[RecordingRecoveryController alloc] initWithLoader:^NSArray *(NSError **error) {
        XCTAssertFalse(NSThread.isMainThread); recoveryReads++; return @[];
    }];
    [app configureRecordingAttachmentsWithCatalogue:catalogue];
    XCTestExpectation *finished = [self expectationWithDescription:@"reconciled snapshots"];
    [app refreshRecordingRecoveryJobsWithCompletion:^(BOOL current, NSArray *jobs, NSError *error) {
        XCTAssertTrue(current); XCTAssertTrue(NSThread.isMainThread); XCTAssertNil(error);
        XCTAssertEqual(jobs.count, 0u); [finished fulfill];
    }];
    XCTAssertEqual(app.reconciliationCount, 1u); XCTAssertEqual(catalogueReads, 0u); XCTAssertEqual(recoveryReads, 0u);
    app.reconciliation(YES, nil);
    [self waitForExpectations:@[finished] timeout:4];
    XCTAssertEqual(catalogueReads, 1u); XCTAssertEqual(recoveryReads, 1u);
}
- (void)testReconciliationFailureCannotBeReportedAsAnEmptySuccess {
    AKRecordingCatalogue *catalogue = [self catalogueWithReader:^NSData *(NSURL *URL, NSError **error) { return nil; }];
    AttachmentIntegrationApp *app = [AttachmentIntegrationApp alloc];
    app.syntheticRecovery = [[RecordingRecoveryController alloc] initWithLoader:^NSArray *(NSError **error) { return @[]; }];
    [app configureRecordingAttachmentsWithCatalogue:catalogue];
    NSError *failure = [NSError errorWithDomain:@"synthetic.catalogue" code:9 userInfo:nil];
    XCTestExpectation *finished = [self expectationWithDescription:@"failure retained"];
    [app refreshRecordingRecoveryJobsWithCompletion:^(BOOL current, NSArray *jobs, NSError *error) {
        XCTAssertTrue(current); XCTAssertEqualObjects(error, failure); [finished fulfill];
    }];
    app.reconciliation(NO, failure); [self waitForExpectations:@[finished] timeout:4];
}
- (void)testUnconfiguredIsolatedControllerSkipsDefaultCatalogueAndReconciliation {
    AttachmentIntegrationApp *app = [AttachmentIntegrationApp alloc];
    __block BOOL completed = NO;
    [app refreshRecordingAttachmentsWithCompletion:^(NSError *error) { completed = YES; XCTAssertNil(error); }];
    XCTAssertTrue(completed); XCTAssertEqual(app.reconciliationCount, 0u);
    XCTAssertNil([app valueForKey:@"recordingCatalogue"]);
}
- (void)testQuitWaitCompletionRemainsAsynchronousForUnconfiguredAndConfiguredControllers {
    for (NSNumber *configured in @[@NO, @YES]) {
        AttachmentIntegrationApp *app = [AttachmentIntegrationApp alloc];
        if (configured.boolValue) [app configureRecordingAttachmentsWithCatalogue:[self catalogueWithReader:^NSData *(NSURL *URL, NSError **error) { return nil; }]];
        [app setValue:@YES forKey:@"terminating"];
        XCTestExpectation *finished = [self expectationWithDescription:@"grants and recording drain"];
        __block BOOL returned = NO;
        [app waitForRecordingFinalizations:^{ XCTAssertTrue(returned); XCTAssertTrue(NSThread.isMainThread); [finished fulfill]; }];
        returned = YES; [self waitForExpectations:@[finished] timeout:4];
    }
}
@end
