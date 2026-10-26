#import <XCTest/XCTest.h>
#import "RecordingRecoveryController.h"

// Every boundary is inert and synthetic: no native panel, Finder, default
// recovery root, recording worker, profile, microphone or sandbox grant.
@interface RR68Fixture : NSObject
@property(nonatomic) RecordingRecoveryController *controller;
@property(nonatomic, copy) NSArray<NSDictionary *> *jobs;
@property(nonatomic, nullable) NSError *loadError;
@property(nonatomic) NSUInteger loads;
@property(nonatomic) NSMutableArray *retryJobs, *retryURLs, *retryCompletions;
@property(nonatomic) NSMutableArray *discardJobs, *discardCompletions;
@property(nonatomic) NSMutableArray *panelJobs, *panelCompletions;
@property(nonatomic) NSMutableArray *confirmationJobs, *confirmationCompletions;
@property(nonatomic) NSMutableArray *revealed;
@end
@implementation RR68Fixture @end

@interface RecordingRecoveryPresentationTests : XCTestCase
@property(nonatomic) NSMutableArray<RR68Fixture *> *fixtures;
@end

@implementation RecordingRecoveryPresentationTests
- (void)setUp { [super setUp]; self.fixtures = [NSMutableArray new]; }
- (void)tearDown {
    for (RR68Fixture *fixture in self.fixtures) {
        fixture.controller.stateDidChange = nil;
        if (fixture.controller.isWindowLoaded) [fixture.controller close];
        [fixture.controller.index invalidate];
    }
    [super tearDown];
}

- (NSDictionary *)job:(NSString *)identity {
    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey:@"The synthetic destination is read-only."}];
    return @{@"directoryIdentity":identity,
             @"title":[NSString stringWithFormat:@"Training call %@.wav", identity],
             @"directoryURL":[NSURL fileURLWithPath:[@"/synthetic/recovery/" stringByAppendingString:identity]],
             @"destinationURL":[NSURL fileURLWithPath:[NSString stringWithFormat:@"/synthetic/exports/%@.wav", identity]],
             @"created":[NSDate dateWithTimeIntervalSince1970:1793000000],
             @"retainedRawBytes":@5432100, @"phase":@"failed", @"needsNewDestination":@NO,
             @"lastErrorDescription":error.localizedDescription, @"lastError":error};
}

- (RR68Fixture *)fixture {
    RR68Fixture *fixture = [RR68Fixture new];
    fixture.jobs = @[[self job:@"one"], [self job:@"two"]];
    fixture.retryJobs = [NSMutableArray new]; fixture.retryURLs = [NSMutableArray new]; fixture.retryCompletions = [NSMutableArray new];
    fixture.discardJobs = [NSMutableArray new]; fixture.discardCompletions = [NSMutableArray new];
    fixture.panelJobs = [NSMutableArray new]; fixture.panelCompletions = [NSMutableArray new];
    fixture.confirmationJobs = [NSMutableArray new]; fixture.confirmationCompletions = [NSMutableArray new];
    fixture.revealed = [NSMutableArray new];
    __weak RR68Fixture *weakFixture = fixture;
    fixture.controller = [[RecordingRecoveryController alloc] initWithLoader:^NSArray *(NSError **error) {
        XCTAssertFalse(NSThread.isMainThread);
        RR68Fixture *owner = weakFixture;
        @synchronized(owner) {
            owner.loads++;
            if (owner.loadError) { *error = owner.loadError; return nil; }
            return [owner.jobs copy];
        }
    }];
    fixture.controller.retryHandler = ^(NSDictionary *job, NSURL *url, void (^completion)(BOOL)) {
        XCTAssertTrue(NSThread.isMainThread);
        [weakFixture.retryJobs addObject:job]; [weakFixture.retryURLs addObject:url]; [weakFixture.retryCompletions addObject:[completion copy]];
    };
    fixture.controller.discardHandler = ^(NSDictionary *job, void (^completion)(BOOL, NSError *)) {
        XCTAssertTrue(NSThread.isMainThread);
        [weakFixture.discardJobs addObject:job]; [weakFixture.discardCompletions addObject:[completion copy]];
    };
    fixture.controller.savePanelHandler = ^(NSWindow *window, NSDictionary *job, void (^completion)(NSURL *)) {
        [weakFixture.panelJobs addObject:job]; [weakFixture.panelCompletions addObject:[completion copy]];
    };
    fixture.controller.discardConfirmationHandler = ^(NSWindow *window, NSDictionary *job, void (^completion)(BOOL)) {
        [weakFixture.confirmationJobs addObject:job]; [weakFixture.confirmationCompletions addObject:[completion copy]];
    };
    fixture.controller.revealHandler = ^(NSURL *url) { [weakFixture.revealed addObject:url]; };
    [self.fixtures addObject:fixture];
    return fixture;
}

- (void)refresh:(RR68Fixture *)fixture {
    XCTestExpectation *done = [self expectationWithDescription:@"Synthetic discovery"];
    [fixture.controller.index refreshWithCompletion:^(BOOL published) { XCTAssertTrue(published); [done fulfill]; }];
    [self waitForExpectations:@[done] timeout:3];
}

- (void)show:(RR68Fixture *)fixture { [self refresh:fixture]; [fixture.controller showRecovery]; }
- (NSTableView *)table:(RR68Fixture *)fixture { return [fixture.controller valueForKey:@"tableView"]; }
- (NSButton *)button:(NSString *)name fixture:(RR68Fixture *)fixture { return [fixture.controller valueForKey:name]; }
- (NSString *)details:(RR68Fixture *)fixture { return [[fixture.controller valueForKey:@"errorView"] string]; }
- (NSArray *)displayed:(RR68Fixture *)fixture { return [fixture.controller valueForKey:@"displayJobs"]; }
- (void)select:(NSString *)identity fixture:(RR68Fixture *)fixture {
    NSArray *jobs = [self displayed:fixture];
    for (NSUInteger row = 0; row < jobs.count; row++) {
        if ([jobs[row][@"directoryIdentity"] isEqual:identity]) {
            [[self table:fixture] selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            return;
        }
    }
    XCTFail(@"Synthetic selection must exist");
}

- (void)completeAndWait:(dispatch_block_t)completion fixture:(RR68Fixture *)fixture {
    XCTestExpectation *done = [self expectationWithDescription:@"Operation result refresh"];
    fixture.controller.stateDidChange = ^{
        if (!fixture.controller.index.isRefreshing) [done fulfill];
    };
    completion();
    [self waitForExpectations:@[done] timeout:3];
    fixture.controller.stateDidChange = nil;
}

- (void)testConstructionDoesNotLoadWindowOrDiscoverFiles {
    RR68Fixture *fixture = [self fixture];
    XCTAssertFalse(fixture.controller.isWindowLoaded);
    XCTAssertFalse(fixture.controller.index.hasLoaded);
    XCTAssertEqual(fixture.loads, 0u);
    XCTAssertEqual(fixture.controller.managedJobCount, 0u);
    XCTAssertTrue(fixture.controller.actionsEnabled);
    [fixture.controller refreshPresentation];
    XCTAssertFalse(fixture.controller.isWindowLoaded);
    XCTAssertEqual(fixture.loads, 0u);
}

- (void)testListDetailsAndRevealUseOnlyTheSelectedStableIdentity {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    XCTAssertEqual([self table:fixture].numberOfRows, 2);
    [self select:@"two" fixture:fixture];
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"two");
    XCTAssertTrue([[[fixture.controller valueForKey:@"destinationLabel"] stringValue] hasSuffix:@"/two.wav"]);
    XCTAssertTrue([[self details:fixture] containsString:@"The synthetic destination is read-only."]);
    XCTAssertTrue([[self details:fixture] containsString:@"NSPOSIXErrorDomain: 13"]);
    [fixture.controller revealSelected:nil];
    XCTAssertEqualObjects(fixture.revealed, @[[self job:@"two"][@"directoryURL"]]);
    NSArray *columns = [self table:fixture].tableColumns;
    XCTAssertEqualObjects([columns valueForKey:@"identifier"], (@[@"title", @"created", @"size", @"state"]));
    for (NSTableColumn *column in columns) {
        NSTextField *cell = (id)[fixture.controller tableView:[self table:fixture] viewForTableColumn:column row:1];
        XCTAssertGreaterThan(cell.stringValue.length, 0u);
        XCTAssertEqualObjects(cell.accessibilityLabel, cell.stringValue);
    }
}

- (void)testReorderingKeepsSelectionAndAnActuallyRemovedJobFallsBack {
    RR68Fixture *fixture = [self fixture]; [self show:fixture]; [self select:@"two" fixture:fixture];
    fixture.jobs = @[[self job:@"two"], [self job:@"one"]]; [self refresh:fixture];
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"two");
    XCTAssertEqual([self table:fixture].selectedRow, 0);
    fixture.jobs = @[[self job:@"one"]]; [self refresh:fixture];
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"one");
}

- (void)testRetryIsIndeterminateAndDuplicateAdmissionIsRejected {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller retrySelected:nil]; [fixture.controller retrySelected:nil];
    [fixture.controller saveSelectedElsewhere:nil]; [fixture.controller discardSelected:nil];
    XCTAssertEqual(fixture.retryJobs.count, 1u);
    XCTAssertEqual(fixture.panelJobs.count, 0u); XCTAssertEqual(fixture.confirmationJobs.count, 0u);
    XCTAssertEqualObjects(fixture.retryJobs.firstObject[@"directoryIdentity"], @"one");
    XCTAssertFalse([self button:@"retryButton" fixture:fixture].enabled);
    NSProgressIndicator *indicator = [fixture.controller valueForKey:@"progressIndicator"];
    XCTAssertEqual(indicator.style, NSProgressIndicatorStyleSpinning);
    XCTAssertTrue(indicator.indeterminate); XCTAssertFalse(indicator.displayedWhenStopped);
    XCTAssertTrue([[self details:fixture] containsString:@"continues if you close this window"]);
    fixture.jobs = @[[self job:@"two"]]; [self refresh:fixture];
    XCTAssertEqual([self displayed:fixture].count, 2u, @"Owned job needs a placeholder while hidden from discovery");
    XCTAssertEqual(fixture.controller.managedJobCount, 2u);
    [fixture.controller close];
    XCTAssertEqual(fixture.controller.managedJobCount, 2u, @"Closed pending progress remains reachable from the menu cache");
    [fixture.controller showRecovery];
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"one");
    XCTAssertEqual([self table:fixture].selectedRow, 1);
    [fixture.controller retrySelected:nil]; XCTAssertEqual(fixture.retryJobs.count, 1u);
}

- (void)testRetryFailureKeepsSelectionAndShowsTheRealRefreshedError {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller retrySelected:nil];
    fixture.jobs = @[[self job:@"two"]]; [self refresh:fixture];
    NSMutableDictionary *failed = [[self job:@"one"] mutableCopy];
    NSError *error = [NSError errorWithDomain:@"SyntheticEncoder" code:42 userInfo:@{NSLocalizedDescriptionKey:@"Synthetic encoder could not finish."}];
    failed[@"lastError"] = error; failed[@"lastErrorDescription"] = error.localizedDescription;
    fixture.jobs = @[failed, [self job:@"two"]];
    void (^completion)(BOOL) = fixture.retryCompletions.firstObject;
    [self completeAndWait:^{ completion(NO); } fixture:fixture];
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"one");
    XCTAssertTrue([[self details:fixture] containsString:@"Synthetic encoder could not finish."]);
    XCTAssertTrue([[self details:fixture] containsString:@"SyntheticEncoder: 42"]);
    XCTAssertTrue([self button:@"retryButton" fixture:fixture].enabled);
    XCTAssertEqual(fixture.retryJobs.count, 1u, @"Failure must not automatically retry");
}

- (void)testResultScanFailureRetainsTheOwnedPlaceholderUntilSuccessfulRefresh {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller retrySelected:nil];
    fixture.jobs = @[[self job:@"two"]]; [self refresh:fixture];
    fixture.loadError = [NSError errorWithDomain:NSPOSIXErrorDomain code:5 userInfo:@{NSLocalizedDescriptionKey:@"Synthetic scan failed."}];
    void (^completion)(BOOL) = fixture.retryCompletions.firstObject;
    [self completeAndWait:^{ completion(NO); } fixture:fixture];
    XCTAssertEqual([self displayed:fixture].count, 2u);
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"one");
    XCTAssertFalse([self button:@"retryButton" fixture:fixture].enabled);
    XCTAssertTrue([[[fixture.controller valueForKey:@"statusLabel"] stringValue] containsString:@"Synthetic scan failed."]);
    fixture.loadError = nil; fixture.jobs = @[[self job:@"one"], [self job:@"two"]]; [self refresh:fixture];
    XCTAssertTrue([self button:@"retryButton" fixture:fixture].enabled);
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"one");
}

- (void)testSavePanelCancellationIsANoopAndRepeatedClickOpensOnePanel {
    RR68Fixture *fixture = [self fixture]; [self show:fixture]; [self select:@"two" fixture:fixture];
    NSUInteger loads = fixture.loads;
    [fixture.controller saveSelectedElsewhere:nil]; [fixture.controller saveSelectedElsewhere:nil];
    XCTAssertEqual(fixture.panelJobs.count, 1u);
    XCTAssertEqualObjects(fixture.panelJobs.firstObject[@"directoryIdentity"], @"two");
    void (^completion)(NSURL *) = fixture.panelCompletions.firstObject; completion(nil);
    XCTAssertEqual(fixture.retryJobs.count, 0u); XCTAssertEqual(fixture.loads, loads);
    XCTAssertTrue([self button:@"saveElsewhereButton" fixture:fixture].enabled);
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"two");
}

- (void)testSaveElsewhereCapturesDestinationAndContinuesAcrossCloseReopen {
    RR68Fixture *fixture = [self fixture]; [self show:fixture]; [self select:@"two" fixture:fixture];
    [fixture.controller saveSelectedElsewhere:nil];
    NSURL *destination = [NSURL fileURLWithPath:@"/synthetic/elsewhere/recovered.wav"];
    void (^choose)(NSURL *) = fixture.panelCompletions.firstObject; choose(destination);
    XCTAssertEqualObjects(fixture.retryURLs, @[destination]);
    [fixture.controller close]; [fixture.controller showRecovery];
    XCTAssertEqual(fixture.retryJobs.count, 1u);
    XCTAssertFalse([self button:@"retryButton" fixture:fixture].enabled);
    [self select:@"one" fixture:fixture];
    fixture.jobs = @[[self job:@"one"]];
    void (^completion)(BOOL) = fixture.retryCompletions.firstObject;
    [self completeAndWait:^{ completion(YES); } fixture:fixture];
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"one");
    XCTAssertEqual([self displayed:fixture].count, 1u);
    XCTAssertTrue([self button:@"retryButton" fixture:fixture].enabled);
    completion(NO); // Duplicate late result must neither rescan nor repaint.
    XCTAssertFalse(fixture.controller.index.isRefreshing);
}

- (void)testLateSavePanelAndConfirmationAfterCloseReopenCannotAdmitWork {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller saveSelectedElsewhere:nil];
    void (^choose)(NSURL *) = fixture.panelCompletions.firstObject;
    [fixture.controller close]; [fixture.controller showRecovery];
    choose([NSURL fileURLWithPath:@"/synthetic/late.wav"]);
    XCTAssertEqual(fixture.retryJobs.count, 0u);
    [fixture.controller discardSelected:nil];
    void (^confirm)(BOOL) = fixture.confirmationCompletions.firstObject;
    [fixture.controller close]; [fixture.controller showRecovery]; confirm(YES);
    XCTAssertEqual(fixture.discardJobs.count, 0u);
    XCTAssertTrue([self button:@"discardButton" fixture:fixture].enabled);
}

- (void)testShowingAnAlreadyVisibleWindowDoesNotRetireItsSavePanel {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller saveSelectedElsewhere:nil];
    [fixture.controller showRecovery];
    void (^choose)(NSURL *) = fixture.panelCompletions.firstObject;
    choose([NSURL fileURLWithPath:@"/synthetic/current.wav"]);
    XCTAssertEqual(fixture.retryJobs.count, 1u);
}

- (void)testDiscardRequiresConfirmationOfExactlyTheChosenJob {
    RR68Fixture *fixture = [self fixture]; [self show:fixture]; [self select:@"two" fixture:fixture];
    [fixture.controller discardSelected:nil]; [fixture.controller discardSelected:nil];
    XCTAssertEqual(fixture.confirmationJobs.count, 1u); XCTAssertEqual(fixture.discardJobs.count, 0u);
    void (^cancel)(BOOL) = fixture.confirmationCompletions.firstObject; cancel(NO);
    XCTAssertEqual(fixture.discardJobs.count, 0u);
    [fixture.controller discardSelected:nil];
    void (^confirm)(BOOL) = fixture.confirmationCompletions.lastObject; confirm(YES); confirm(YES);
    XCTAssertEqual(fixture.discardJobs.count, 1u);
    XCTAssertEqualObjects(fixture.discardJobs.firstObject[@"directoryIdentity"], @"two");
    XCTAssertFalse([self button:@"discardButton" fixture:fixture].enabled);
    [fixture.controller close]; fixture.jobs = @[[self job:@"one"]];
    void (^completion)(BOOL, NSError *) = fixture.discardCompletions.firstObject;
    [self completeAndWait:^{ completion(YES, nil); } fixture:fixture];
    XCTAssertFalse(fixture.controller.window.isVisible);
    [fixture.controller showRecovery];
    XCTAssertEqual([self displayed:fixture].count, 1u);
    XCTAssertEqualObjects(fixture.controller.index.selectedIdentity, @"one");
}

- (void)testDiscardFailureDisplaysActualErrorAndPreservesTheJob {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller discardSelected:nil];
    void (^confirm)(BOOL) = fixture.confirmationCompletions.firstObject; confirm(YES);
    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"Synthetic deletion refused."}];
    void (^completion)(BOOL, NSError *) = fixture.discardCompletions.firstObject;
    [self completeAndWait:^{ completion(NO, error); } fixture:fixture];
    XCTAssertEqual([self displayed:fixture].count, 2u);
    XCTAssertTrue([[self details:fixture] containsString:@"Synthetic deletion refused."]);
    XCTAssertTrue([[self details:fixture] containsString:@"NSPOSIXErrorDomain: 1"]);
    XCTAssertTrue([self button:@"discardButton" fixture:fixture].enabled);
}

- (void)testDisabledAdmissionRejectsDirectActionsAndPendingPanelChoices {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller saveSelectedElsewhere:nil];
    fixture.controller.actionsEnabled = NO;
    void (^choose)(NSURL *) = fixture.panelCompletions.firstObject;
    choose([NSURL fileURLWithPath:@"/synthetic/termination.wav"]);
    [fixture.controller retrySelected:nil]; [fixture.controller saveSelectedElsewhere:nil];
    [fixture.controller discardSelected:nil]; [fixture.controller revealSelected:nil];
    XCTAssertEqual(fixture.retryJobs.count, 0u); XCTAssertEqual(fixture.confirmationJobs.count, 0u);
    XCTAssertEqual(fixture.revealed.count, 0u); XCTAssertEqual(fixture.panelJobs.count, 1u);
    fixture.controller.actionsEnabled = YES;
    [fixture.controller discardSelected:nil];
    fixture.controller.actionsEnabled = NO;
    void (^confirm)(BOOL) = fixture.confirmationCompletions.firstObject; confirm(YES);
    XCTAssertEqual(fixture.discardJobs.count, 0u);
    fixture.controller.actionsEnabled = YES;
    XCTAssertTrue([self button:@"retryButton" fixture:fixture].enabled);
}

- (void)testSelectionChangeRetiresOldDialogButAllowsIndependentPendingJobs {
    RR68Fixture *fixture = [self fixture]; [self show:fixture];
    [fixture.controller saveSelectedElsewhere:nil]; [self select:@"two" fixture:fixture];
    void (^choose)(NSURL *) = fixture.panelCompletions.firstObject;
    choose([NSURL fileURLWithPath:@"/synthetic/old-selection.wav"]);
    XCTAssertEqual(fixture.retryJobs.count, 0u);
    [fixture.controller retrySelected:nil]; [self select:@"one" fixture:fixture]; [fixture.controller retrySelected:nil];
    XCTAssertEqual(fixture.retryJobs.count, 2u);
    XCTAssertEqualObjects([fixture.retryJobs valueForKey:@"directoryIdentity"], (@[@"two", @"one"]));
}

- (void)testCompactNativeWindowFitsBothAppearancesWithPendingAndFailedDetails {
    for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        RR68Fixture *fixture = [self fixture]; [self show:fixture];
        NSWindow *window = fixture.controller.window;
        window.appearance = [NSAppearance appearanceNamed:name];
        XCTAssertTrue(NSEqualSizes(window.contentView.bounds.size, NSMakeSize(650, 460)));
        XCTAssertTrue((window.styleMask & NSWindowStyleMaskClosable) != 0);
        XCTAssertFalse((window.styleMask & NSWindowStyleMaskResizable) != 0);
        for (NSView *view in window.contentView.subviews) XCTAssertTrue(NSContainsRect(window.contentView.bounds, view.frame));
        for (NSString *key in @[@"refreshButton", @"revealButton", @"discardButton", @"saveElsewhereButton", @"retryButton"]) {
            NSButton *button = [self button:key fixture:fixture];
            NSSize text = [button.title sizeWithAttributes:@{NSFontAttributeName:button.font}];
            XCTAssertLessThan(text.width, button.bounds.size.width);
        }
        [fixture.controller retrySelected:nil];
        [window displayIfNeeded]; [window.contentView displayIfNeeded];
        NSView *view = window.contentView;
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        NSImage *cached = [[NSImage alloc] initWithData:bitmap.TIFFRepresentation];
        NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
        [image lockFocus];
        [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
            [NSColor.windowBackgroundColor setFill]; NSRectFill(view.bounds); [cached drawInRect:view.bounds];
        }];
        [image unlockFocus];
        XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
        attachment.name = [NSString stringWithFormat:@"recording-recovery-%@", [name isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light"];
        attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:attachment];
    }
}
@end
