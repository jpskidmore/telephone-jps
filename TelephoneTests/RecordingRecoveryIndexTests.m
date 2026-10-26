#import <XCTest/XCTest.h>
#import "AKRecordingRecoveryIndex.h"

@interface RecordingRecoveryIndexTests : XCTestCase @end
@implementation RecordingRecoveryIndexTests
- (NSDictionary *)job:(NSString *)identity { return @{@"directoryIdentity":identity, @"title":identity}; }
- (void)testLoaderRunsOffMainAndPublishesSelectionOnMain {
    XCTestExpectation *done = [self expectationWithDescription:@"loaded"];
    AKRecordingRecoveryIndex *index = [[AKRecordingRecoveryIndex alloc] initWithLoader:^NSArray *(NSError **error) {
        XCTAssertFalse(NSThread.isMainThread); return @[[self job:@"one"], [self job:@"two"]];
    }];
    XCTAssertFalse(index.hasLoaded); XCTAssertEqual(index.jobs.count, 0u);
    [index refreshWithCompletion:^(BOOL published) {
        XCTAssertTrue(NSThread.isMainThread); XCTAssertTrue(published); XCTAssertFalse(index.isRefreshing);
        XCTAssertTrue(index.hasLoaded); XCTAssertEqual(index.jobs.count, 2u); XCTAssertEqualObjects(index.selectedIdentity, @"one");
        [done fulfill];
    }];
    XCTAssertTrue(index.isRefreshing);
    [self waitForExpectations:@[done] timeout:3]; [index invalidate];
}
- (void)testSlowOlderScanCannotReplaceNewerSnapshot {
    dispatch_semaphore_t releaseFirst = dispatch_semaphore_create(0), firstEntered = dispatch_semaphore_create(0);
    __block NSUInteger calls = 0;
    AKRecordingRecoveryIndex *index = [[AKRecordingRecoveryIndex alloc] initWithLoader:^NSArray *(NSError **error) {
        NSUInteger call; @synchronized(self) { call = ++calls; }
        if (call == 1) { dispatch_semaphore_signal(firstEntered); dispatch_semaphore_wait(releaseFirst, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)); }
        return @[[self job:call == 1 ? @"old" : @"new"]];
    }];
    XCTestExpectation *obsolete = [self expectationWithDescription:@"obsolete"], *latest = [self expectationWithDescription:@"latest"];
    [index refreshWithCompletion:^(BOOL published) { XCTAssertFalse(published); XCTAssertEqualObjects(index.selectedIdentity, @"new"); [obsolete fulfill]; }];
    // A utility waiter prevents the test main thread from blocking admission.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        dispatch_semaphore_wait(firstEntered, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
        dispatch_async(dispatch_get_main_queue(), ^{
            [index refreshWithCompletion:^(BOOL published) {
                XCTAssertTrue(published); XCTAssertEqualObjects(index.selectedIdentity, @"new");
                dispatch_semaphore_signal(releaseFirst); [latest fulfill];
            }];
        });
    });
    [self waitForExpectations:@[latest, obsolete] timeout:5]; [index invalidate];
}
- (void)testFailedScanPreservesPreviousJobsAndSelectedIdentity {
    __block BOOL fail = NO;
    AKRecordingRecoveryIndex *index = [[AKRecordingRecoveryIndex alloc] initWithLoader:^NSArray *(NSError **error) {
        if (fail) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:5 userInfo:nil]; return nil; }
        return @[[self job:@"one"], [self job:@"two"]];
    }];
    XCTestExpectation *first = [self expectationWithDescription:@"first"];
    [index refreshWithCompletion:^(BOOL published) { [first fulfill]; }]; [self waitForExpectations:@[first] timeout:3];
    index.selectedIdentity = @"two"; fail = YES;
    XCTestExpectation *failed = [self expectationWithDescription:@"failed"];
    [index refreshWithCompletion:^(BOOL published) {
        XCTAssertTrue(published); XCTAssertNotNil(index.error); XCTAssertEqual(index.jobs.count, 2u);
        XCTAssertEqualObjects(index.selectedIdentity, @"two"); XCTAssertNotNil(index.selectedJob); [failed fulfill];
    }];
    [self waitForExpectations:@[failed] timeout:3]; [index invalidate];
}
- (void)testSelectionSurvivesReorderingAndFallsBackOnlyWhenRemoved {
    __block NSArray *jobs = @[[self job:@"one"], [self job:@"two"]];
    AKRecordingRecoveryIndex *index = [[AKRecordingRecoveryIndex alloc] initWithLoader:^NSArray *(NSError **error) { return jobs; }];
    for (NSUInteger pass = 0; pass < 3; pass++) {
        if (pass == 1) { index.selectedIdentity = @"two"; jobs = @[[self job:@"two"], [self job:@"one"]]; }
        if (pass == 2) jobs = @[[self job:@"one"]];
        XCTestExpectation *done = [self expectationWithDescription:@"refresh"];
        [index refreshWithCompletion:^(BOOL published) { [done fulfill]; }]; [self waitForExpectations:@[done] timeout:3];
        XCTAssertEqualObjects(index.selectedIdentity, pass == 1 ? @"two" : @"one");
    }
    [index invalidate];
}
- (void)testInvalidationRejectsLatePublicationAndFurtherRefresh {
    dispatch_semaphore_t release = dispatch_semaphore_create(0);
    AKRecordingRecoveryIndex *index = [[AKRecordingRecoveryIndex alloc] initWithLoader:^NSArray *(NSError **error) {
        dispatch_semaphore_wait(release, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)); return @[[self job:@"late"]];
    }];
    XCTestExpectation *done = [self expectationWithDescription:@"retired"];
    [index refreshWithCompletion:^(BOOL published) { XCTAssertFalse(published); XCTAssertEqual(index.jobs.count, 0u); [done fulfill]; }];
    [index invalidate]; dispatch_semaphore_signal(release);
    [self waitForExpectations:@[done] timeout:3]; XCTAssertFalse(index.isRefreshing);
    XCTestExpectation *again = [self expectationWithDescription:@"already invalidated"];
    [index refreshWithCompletion:^(BOOL published) { XCTAssertFalse(published); [again fulfill]; }];
    [self waitForExpectations:@[again] timeout:3];
}
@end
