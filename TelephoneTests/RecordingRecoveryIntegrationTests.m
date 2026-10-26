#import <XCTest/XCTest.h>
#import "AppController.h"
#import "RecordingRecoveryController.h"

@interface AppController (RecoveryIntegrationInterface)
- (RecordingRecoveryController *)recordingRecoveryController;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (IBAction)recoverRecordings:(id)sender;
- (void)recordingExportDidFail:(NSNotification *)notification;
@end
@interface RecoveryIntegrationPresentation : RecordingRecoveryController
@property(nonatomic) NSUInteger presentations;
@end
@implementation RecoveryIntegrationPresentation
- (void)showRecovery { self.presentations++; }
@end
// Never call AppController.init, awakeFromNib or the actual application startup.
@interface RecoveryIntegrationApp : AppController
@property(nonatomic) RecoveryIntegrationPresentation *syntheticRecovery;
@end
@implementation RecoveryIntegrationApp
- (RecordingRecoveryController *)recordingRecoveryController { return self.syntheticRecovery; }
@end
@interface RecordingRecoveryIntegrationTests : XCTestCase @end
@implementation RecordingRecoveryIntegrationTests
- (NSMenuItem *)menuItem {
    return [[NSMenuItem alloc] initWithTitle:@"Recover Recordings…" action:@selector(recoverRecordings:) keyEquivalent:@""];
}
- (void)testUnknownAndLoadingMenuValidationNeverAdmitsFileWork {
    __block NSUInteger reads = 0;
    RecoveryIntegrationPresentation *recovery = [[RecoveryIntegrationPresentation alloc] initWithLoader:^NSArray *(NSError **error) { reads++; return @[]; }];
    RecoveryIntegrationApp *app = [RecoveryIntegrationApp alloc]; app.syntheticRecovery = recovery;
    NSMenuItem *item = self.menuItem;
    for (NSUInteger i = 0; i < 1000; i++) XCTAssertTrue([app validateMenuItem:item]);
    XCTAssertEqual(reads, 0u); XCTAssertFalse(recovery.isWindowLoaded);
    XCTestExpectation *loaded = [self expectationWithDescription:@"empty result"];
    [recovery.index refreshWithCompletion:^(BOOL current) { [loaded fulfill]; }];
    [self waitForExpectations:@[loaded] timeout:3];
    for (NSUInteger i = 0; i < 1000; i++) XCTAssertFalse([app validateMenuItem:item]);
    XCTAssertEqual(reads, 1u); XCTAssertFalse(recovery.isWindowLoaded);
    [recovery.index invalidate];
}
- (void)testFailedScanKeepsRecoveryDiscoverableAndTerminationDisablesMenu {
    RecoveryIntegrationPresentation *recovery = [[RecoveryIntegrationPresentation alloc] initWithLoader:^NSArray *(NSError **error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:5 userInfo:nil]; return nil;
    }];
    RecoveryIntegrationApp *app = [RecoveryIntegrationApp alloc]; app.syntheticRecovery = recovery;
    XCTestExpectation *loaded = [self expectationWithDescription:@"failure"];
    [recovery.index refreshWithCompletion:^(BOOL current) { [loaded fulfill]; }];
    [self waitForExpectations:@[loaded] timeout:3]; XCTAssertNotNil(recovery.index.error);
    XCTAssertTrue([app validateMenuItem:self.menuItem]);
    [app setValue:@YES forKey:@"terminating"]; XCTAssertFalse([app validateMenuItem:self.menuItem]);
    [app recoverRecordings:nil]; XCTAssertEqual(recovery.presentations, 0u);
    [recovery.index invalidate];
}
- (void)testMenuCanReopenAnOwnedJobHiddenFromEligibleScan {
    NSDictionary *job = @{@"directoryIdentity":@"synthetic:pending", @"title":@"Synthetic.wav",
        @"directoryURL":[NSURL fileURLWithPath:@"/synthetic/recovery/pending"],
        @"destinationURL":[NSURL fileURLWithPath:@"/synthetic/exports/pending.wav"], @"needsNewDestination":@NO};
    __block NSArray *jobs = @[job];
    RecoveryIntegrationPresentation *recovery = [[RecoveryIntegrationPresentation alloc] initWithLoader:^NSArray *(NSError **error) { return jobs; }];
    recovery.retryHandler = ^(NSDictionary *selected, NSURL *destination, void (^completion)(BOOL)) {};
    RecoveryIntegrationApp *app = [RecoveryIntegrationApp alloc]; app.syntheticRecovery = recovery;
    XCTestExpectation *first = [self expectationWithDescription:@"initial eligible job"];
    [recovery.index refreshWithCompletion:^(BOOL current) { [first fulfill]; }]; [self waitForExpectations:@[first] timeout:3];
    [recovery retrySelected:nil]; jobs = @[];
    XCTestExpectation *owned = [self expectationWithDescription:@"owned job excluded"];
    [recovery.index refreshWithCompletion:^(BOOL current) { [owned fulfill]; }]; [self waitForExpectations:@[owned] timeout:3];
    XCTAssertEqual(recovery.index.jobs.count, 0u); XCTAssertEqual(recovery.managedJobCount, 1u);
    XCTAssertTrue([app validateMenuItem:self.menuItem]); XCTAssertFalse(recovery.isWindowLoaded);
    [recovery.index invalidate];
}
- (void)testExplicitRecoveryAdmitsOneScanBeforePresentation {
    __block NSUInteger reads = 0;
    RecoveryIntegrationPresentation *recovery = [[RecoveryIntegrationPresentation alloc] initWithLoader:^NSArray *(NSError **error) {
        reads++; return @[@{@"directoryIdentity":@"synthetic:one", @"title":@"Synthetic.wav"}];
    }];
    RecoveryIntegrationApp *app = [RecoveryIntegrationApp alloc]; app.syntheticRecovery = recovery;
    XCTestExpectation *loaded = [self expectationWithDescription:@"one current snapshot"];
    recovery.stateDidChange = ^{ if (recovery.index.hasLoaded && !recovery.index.isRefreshing) [loaded fulfill]; };
    [app recoverRecordings:nil]; XCTAssertEqual(recovery.presentations, 1u);
    [self waitForExpectations:@[loaded] timeout:3];
    XCTAssertEqual(reads, 1u); XCTAssertEqual(recovery.index.jobs.count, 1u);
    recovery.stateDidChange = nil; [recovery.index invalidate];
}
@end
