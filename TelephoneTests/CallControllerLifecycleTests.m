//
//  CallControllerLifecycleTests.m
//  TelephoneTests
//

#import <XCTest/XCTest.h>

#import "AKSIPCall.h"
#import "CallController.h"

@interface AKStoppedRecordingCallStub : AKSIPCall
@end

@implementation AKStoppedRecordingCallStub

- (BOOL)isRecording {
    return NO;
}

@end

@interface CallController (LifecycleTests)
- (void)subscribeToWindowFloatingChanges;
@end

@interface CallControllerLifecycleTests : XCTestCase
@end

@implementation CallControllerLifecycleTests

- (void)testControllerCanDeallocateAfterItsCallHasStoppedRecording {
    __weak CallController *weakController = nil;

    @autoreleasepool {
        CallController *controller =
            [[CallController alloc] initWithWindowNibName:@"Call"
                                       accountController:nil
                                               userAgent:nil
                                                delegate:nil];
        [controller subscribeToWindowFloatingChanges];
        controller.call = [[AKStoppedRecordingCallStub alloc] init];
        weakController = controller;
    }

    // The 2.0.1 implementation aborted in objc_initWeak while releasing the
    // controller, before this assertion could run.
    XCTAssertNil(weakController);
}

@end

// The following tests run the real call ownership/stop path, replacing only
// PJSIP recorder operations and the encoder. No SIP account or audio is needed.
@interface AKSIPCall (RecordingLifecycleTests)
- (BOOL)stopNativeRecorders;
- (void)finalizeRecordingFromLocalURL:(NSURL *)localURL remoteURL:(NSURL *)remoteURL
                     destinationURL:(NSURL *)destinationURL completion:(void (^)(BOOL))completion;
@end

@interface AKScopeReleaseSpy : NSObject
@property(nonatomic) NSUInteger releases;
@property(nonatomic, strong) NSURL *reservedURL;
@property(nonatomic) BOOL reservationRemovedBeforeRelease;
- (void)stopAccessingSecurityScopedResource;
@end
@implementation AKScopeReleaseSpy
- (void)stopAccessingSecurityScopedResource {
    self.releases++;
    if (self.reservedURL) {
        self.reservationRemovedBeforeRelease = ![NSFileManager.defaultManager fileExistsAtPath:self.reservedURL.path];
    }
}
@end

@interface AKDeferredRecordingCall : AKSIPCall
@property(nonatomic) BOOL recordingActive;
@property(nonatomic) BOOL setupFails;
@property(nonatomic) BOOL nativeStopFails;
@property(nonatomic) NSUInteger nativeStops;
@property(nonatomic, copy) void (^pendingCompletion)(BOOL);
@property(nonatomic, strong) NSURL *testDirectory;
- (void)complete:(BOOL)succeeded;
@end
@implementation AKDeferredRecordingCall
- (BOOL)isRecording { return self.recordingActive; }
- (BOOL)startRecordingToURL:(NSURL *)URL {
    if (self.setupFails) return NO;
    self.recordingActive = YES;
    self.testDirectory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                                    isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [self setValue:URL forKey:@"recordingURL"];
    [self setValue:[self.testDirectory URLByAppendingPathComponent:@"local.wav"] forKey:@"localRecordingURL"];
    [self setValue:[self.testDirectory URLByAppendingPathComponent:@"remote.wav"] forKey:@"remoteRecordingURL"];
    [self setValue:self.testDirectory forKey:@"recordingTemporaryDirectoryURL"];
    return YES;
}
- (BOOL)stopNativeRecorders {
    self.nativeStops++;
    if (self.nativeStopFails) return NO;
    self.recordingActive = NO;
    return YES;
}
- (void)finalizeRecordingFromLocalURL:(NSURL *)localURL remoteURL:(NSURL *)remoteURL
                     destinationURL:(NSURL *)destinationURL completion:(void (^)(BOOL))completion {
    self.pendingCompletion = completion;
}
- (void)complete:(BOOL)succeeded {
    void (^completion)(BOOL) = self.pendingCompletion;
    self.pendingCompletion = nil;
    if (completion) completion(succeeded);
    [NSFileManager.defaultManager removeItemAtURL:self.testDirectory error:nil];
}
@end

@interface AKHeadlessCallController : CallController
@end
@implementation AKHeadlessCallController
- (NSWindow *)window { return nil; }
- (ActiveCallViewController *)activeCallViewController { return nil; }
- (void)unsubscribeFromWindowFloatingChanges {}
@end

@interface RecordingOwnershipTests : XCTestCase
@end
@implementation RecordingOwnershipTests
- (void)checkReplacementCompletingFirstCallFirst:(BOOL)firstCallFirst {
    AKHeadlessCallController *controller = [[AKHeadlessCallController alloc] initWithWindowNibName:@"Call"
        accountController:nil userAgent:nil delegate:nil];
    AKDeferredRecordingCall *a = [[AKDeferredRecordingCall alloc] init];
    AKDeferredRecordingCall *b = [[AKDeferredRecordingCall alloc] init];
    // Both sessions use the same token object to expose URL-equality based bugs.
    AKScopeReleaseSpy *scope = [[AKScopeReleaseSpy alloc] init];
    NSURL *destination = [NSURL fileURLWithPath:@"/unused/test.ogg"];
    controller.call = a;
    XCTAssertTrue([a startRecordingToURL:destination accessedDirectoryURL:(NSURL *)scope]);
    [controller stopRecording];
    XCTAssertEqual(a.nativeStops, 1u);
    XCTAssertEqual(scope.releases, 0u);
    controller.call = b; // The same assignment performed by redial's completion.
    XCTAssertTrue([b startRecordingToURL:destination accessedDirectoryURL:(NSURL *)scope]);
    [controller stopRecording];
    [controller stopRecording];
    XCTAssertEqual(b.nativeStops, 1u);
    XCTAssertFalse(b.isRecording);
    XCTAssertEqual(scope.releases, 0u);
    [(firstCallFirst ? a : b) complete:YES];
    XCTAssertEqual(scope.releases, 1u);
    [(firstCallFirst ? b : a) complete:NO]; // Failed conversion must also release.
    XCTAssertEqual(scope.releases, 2u);
}
- (void)testRedialStopsSecondRecordingWhileFirstConversionIsPending {
    [self checkReplacementCompletingFirstCallFirst:YES];
}
- (void)testReverseCompletionOrderKeepsAccessLifetimesSeparate {
    [self checkReplacementCompletingFirstCallFirst:NO];
}
- (void)testSetupFailureReleasesConsumedAccess {
    AKDeferredRecordingCall *call = [[AKDeferredRecordingCall alloc] init];
    AKScopeReleaseSpy *scope = [[AKScopeReleaseSpy alloc] init];
    call.setupFails = YES;
    NSURL *reservation = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    XCTAssertTrue([NSData.data writeToURL:reservation atomically:YES]);
    scope.reservedURL = reservation;
    XCTAssertFalse([call startRecordingToURL:reservation accessedDirectoryURL:(NSURL *)scope]);
    XCTAssertEqual(scope.releases, 1u);
    XCTAssertTrue(scope.reservationRemovedBeforeRelease);
}
- (void)testFailedNativeStopRetainsAccessForRetry {
    AKDeferredRecordingCall *call = [[AKDeferredRecordingCall alloc] init];
    AKScopeReleaseSpy *scope = [[AKScopeReleaseSpy alloc] init];
    XCTAssertTrue([call startRecordingToURL:[NSURL fileURLWithPath:@"/unused/test.ogg"] accessedDirectoryURL:(NSURL *)scope]);
    call.nativeStopFails = YES;
    __block BOOL reportedFailure = NO;
    [call stopRecordingWithCompletion:^(BOOL succeeded) { reportedFailure = !succeeded; }];
    XCTAssertTrue(reportedFailure);
    XCTAssertTrue(call.isRecording);
    XCTAssertEqual(scope.releases, 0u);
    XCTAssertNil(call.pendingCompletion);
    call.nativeStopFails = NO;
    [call stopRecording];
    [call complete:YES];
    XCTAssertEqual(scope.releases, 1u);
}
- (void)testControllerDeallocationStopsCurrentCallDuringEarlierConversion {
    AKDeferredRecordingCall *a = [[AKDeferredRecordingCall alloc] init];
    AKDeferredRecordingCall *b = [[AKDeferredRecordingCall alloc] init];
    AKScopeReleaseSpy *scope = [[AKScopeReleaseSpy alloc] init];
    __weak CallController *weakController;
    @autoreleasepool {
        AKHeadlessCallController *controller = [[AKHeadlessCallController alloc] initWithWindowNibName:@"Call"
            accountController:nil userAgent:nil delegate:nil];
        weakController = controller;
        controller.call = a;
        [a startRecordingToURL:[NSURL fileURLWithPath:@"/unused/a.ogg"] accessedDirectoryURL:(NSURL *)scope];
        controller.call = b;
        [b startRecordingToURL:[NSURL fileURLWithPath:@"/unused/b.ogg"] accessedDirectoryURL:(NSURL *)scope];
    }
    XCTAssertNil(weakController);
    XCTAssertEqual(a.nativeStops, 1u);
    XCTAssertEqual(b.nativeStops, 1u);
    [a complete:YES];
    [b complete:YES];
    XCTAssertEqual(scope.releases, 2u);
}
@end

// These tests exercise actual controller transitions with no PJSUA operations.
// Run the hosted suite only in the documented disposable test account; the
// standalone audio policy harness is safe in an ordinary isolated workspace.
@interface AKAudioStateAgentStub : NSObject
@property(nonatomic) BOOL hasAudioFailure;
@property(nonatomic, getter=isStarted) BOOL started;
@end
@implementation AKAudioStateAgentStub
@end

@interface AKAudioStateCallStub : AKSIPCall
@property(nonatomic) NSUInteger stops;
@property(nonatomic) NSUInteger refreshes;
@end
@implementation AKAudioStateCallStub
- (BOOL)isRecording { return NO; }
- (void)stopRecording { self.stops++; }
- (void)refreshRecordingConnections { self.refreshes++; }
- (BOOL)isOnLocalHold { return NO; }
- (BOOL)isOnRemoteHold { return NO; }
@end

@interface CallController (AudioRecoveryTests)
- (void)SIPCallMediaDidBecomeActive:(NSNotification *)notification;
- (void)SIPUserAgentAudioStateDidChange:(NSNotification *)notification;
@end

@interface AudioRecoveryPresentationTests : XCTestCase
@end
@implementation AudioRecoveryPresentationTests
- (void)testFailedAudioPreservesWarningAndStillProcessesOffHold {
    AKAudioStateAgentStub *agent = [AKAudioStateAgentStub new];
    agent.hasAudioFailure = YES;
    agent.started = YES;
    AKHeadlessCallController *controller = [[AKHeadlessCallController alloc]
        initWithWindowNibName:@"Call" accountController:nil
        userAgent:(AKSIPUserAgent *)agent delegate:nil];
    AKAudioStateCallStub *call = [AKAudioStateCallStub new];
    call.state = kAKSIPCallConfirmedState;
    controller.call = call;
    controller.callActive = YES;
    controller.callOnHold = YES;
    controller.status = @"00:12";
    XCTAssertEqualObjects(controller.status, NSLocalizedString(@"Audio unavailable", nil));
    [controller SIPCallMediaDidBecomeActive:[NSNotification notificationWithName:@"test" object:call]];
    XCTAssertFalse(controller.isCallOnHold);
    XCTAssertEqual(call.refreshes, 0u);
    XCTAssertEqualObjects(controller.status, NSLocalizedString(@"Audio unavailable", nil));
    controller.callActive = NO;
    controller.status = @"call ended";
    XCTAssertEqualObjects(controller.status, @"call ended");
    XCTAssertNil(controller.intermediateStatusTimer);
}

- (void)testFailureFinalizesWithoutChangingCallStateAndStoppedRecoveryUsesCache {
    AKAudioStateAgentStub *agent = [AKAudioStateAgentStub new];
    agent.started = YES;
    AKHeadlessCallController *controller = [[AKHeadlessCallController alloc]
        initWithWindowNibName:@"Call" accountController:nil
        userAgent:(AKSIPUserAgent *)agent delegate:nil];
    AKAudioStateCallStub *call = [AKAudioStateCallStub new];
    call.state = kAKSIPCallConfirmedState;
    controller.call = call;
    controller.callActive = YES;
    controller.status = @"00:12";
    NSUInteger stopsBefore = call.stops;
    agent.hasAudioFailure = YES;
    [controller SIPUserAgentAudioStateDidChange:
        [NSNotification notificationWithName:@"test" object:agent]];
    XCTAssertEqual(call.stops, stopsBefore + 1);
    XCTAssertEqual(call.state, kAKSIPCallConfirmedState);
    XCTAssertTrue(controller.isCallActive);
    agent.hasAudioFailure = NO;
    agent.started = NO;
    [controller SIPUserAgentAudioStateDidChange:
        [NSNotification notificationWithName:@"test" object:agent]];
    XCTAssertEqualObjects(controller.status, @"00:12");
    XCTAssertEqual(call.refreshes, 0u);
}
@end

// Load the production Call and state nibs and invoke their real actions. The
// fixture replaces SIP, notification delivery and defaults only; layout, native
// window chrome, bindings, controller transitions and keypad code are real.
#import "ActiveCallViewController.h"
#import "IncomingCallViewController.h"
#import "EndedCallViewController.h"
#import "AKLiquidGlass.h"

@interface AKCompactAccountFixture : NSObject
@property(nonatomic, copy) NSString *accountDescription;
@property(nonatomic) BOOL callsShouldDisplayAccountInfo;
@end
@implementation AKCompactAccountFixture
@end

@interface AKCompactCallFixture : AKSIPCall
@property(nonatomic) BOOL muted;
@property(nonatomic) BOOL localHeld;
@property(nonatomic) BOOL remoteHeld;
@property(nonatomic) NSUInteger answers;
@property(nonatomic) NSUInteger hangups;
@property(nonatomic) NSUInteger recordingStops;
@property(nonatomic, strong) NSMutableString *sentDigits;
@end
@implementation AKCompactCallFixture
- (instancetype)init { if ((self = [super init])) _sentDigits = [NSMutableString new]; return self; }
- (BOOL)isActive { return self.state == kAKSIPCallConfirmedState; }
- (BOOL)isRecording { return NO; }
- (BOOL)isMissed { return NO; }
- (BOOL)isIncoming { return self.state == kAKSIPCallIncomingState; }
- (BOOL)isMicrophoneMuted { return self.muted; }
- (BOOL)isOnLocalHold { return self.localHeld; }
- (BOOL)isOnRemoteHold { return self.remoteHeld; }
- (void)answer { self.answers++; }
- (void)hangUp { self.hangups++; }
- (void)stopRecording { self.recordingStops++; }
- (void)toggleMicrophoneMute { self.muted = !self.muted; }
- (void)toggleHold { self.localHeld = !self.localHeld; }
- (void)sendDTMFDigits:(NSString *)digits { [self.sentDigits appendString:digits]; }
@end

@interface AKCompactCallController : CallController
@end
@implementation AKCompactCallController
- (void)removeUserNotification {}
- (void)removeOrShowUserNotificationOnDisconnectIfNeeded {}
@end

@interface ActiveCallViewController (CompactCardTests)
- (void)prepareKeypad;
- (void)refreshVisibleCallControls;
@end

@interface CallController (CompactCardTests)
- (void)showActiveCallView;
@end

@interface CompactCallCardTests : XCTestCase
@property(nonatomic) AKCompactCallController *controller;
@property(nonatomic) AKCompactCallFixture *call;
@property(nonatomic) AKCompactAccountFixture *account;
@property(nonatomic) NSUserDefaults *defaults;
@property(nonatomic) NSString *defaultsSuite;
@end

@implementation CompactCallCardTests
- (void)setUp {
    [super setUp];
    self.defaultsSuite = [@"test.telephone.compact-call." stringByAppendingString:NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.defaultsSuite];
    self.account = [AKCompactAccountFixture new];
    self.account.accountDescription = @"Personal";
    self.account.callsShouldDisplayAccountInfo = YES;
    self.controller = [[AKCompactCallController alloc] initWithWindowNibName:@"Call"
        accountController:(AccountController *)self.account userAgent:nil delegate:nil];
    [self.controller setValue:self.defaults forKey:@"defaults"];
    self.controller.title = @"020 7946 0123";
    self.controller.displayedName = @"Alex Morgan";
    self.call = [AKCompactCallFixture new];
    self.call.state = kAKSIPCallConfirmedState;
    self.controller.call = self.call;
    self.controller.window.releasedWhenClosed = NO;
}
- (void)tearDown {
    self.controller.callActive = NO;
    [self.controller.activeCallViewController stopCallTimer];
    [self.controller.window close];
    self.controller = nil;
    self.call = nil;
    [self.defaults removePersistentDomainForName:self.defaultsSuite];
    [super tearDown];
}
- (NSButton *)buttonWithAction:(SEL)action inView:(NSView *)view {
    if ([view isKindOfClass:NSButton.class] && [(NSButton *)view action] == action) return (NSButton *)view;
    for (NSView *child in view.subviews) {
        NSButton *button = [self buttonWithAction:action inView:child];
        if (button != nil) return button;
    }
    return nil;
}
- (void)assertCompactView:(NSView *)view actionCount:(NSUInteger)count {
    [self.controller.window.contentView layoutSubtreeIfNeeded];
    XCTAssertEqualWithAccuracy(view.frame.size.width, 300, 0.1);
    XCTAssertEqualWithAccuracy(view.frame.size.height, 112, 0.1);
    XCTAssertEqualWithAccuracy(self.controller.window.contentView.frame.size.height, 112, 0.1);
    NSRect expected = [self.controller.window frameRectForContentRect:NSMakeRect(0, 0, 300, 112)];
    XCTAssertEqualWithAccuracy(self.controller.window.frame.size.height, expected.size.height, 0.1);
    XCTAssertEqualWithAccuracy([self.controller.window contentBorderThicknessForEdge:NSMinYEdge], 0, 0.1);
    XCTAssertFalse((self.controller.window.styleMask & NSWindowStyleMaskFullSizeContentView) != 0);
    XCTAssertNotNil([self.controller.window standardWindowButton:NSWindowCloseButton]);
    NSView *root = self.controller.window.contentView;
    NSUInteger paneIndex = [root.subviews indexOfObjectIdenticalTo:view];
    XCTAssertNotEqual(paneIndex, NSNotFound);
    NSUInteger backdropCount = 0;
    for (NSView *child in root.subviews) {
        if (![child isKindOfClass:AKWindowMaterialView.class]) continue;
        backdropCount++;
        XCTAssertLessThan([root.subviews indexOfObjectIdenticalTo:child], paneIndex,
                          @"Window backdrop must remain behind the current call pane");
    }
    XCTAssertEqual(backdropCount, 1u);
    AKGlassControlContainer *bar = nil;
    for (NSView *child in view.subviews) if ([child isKindOfClass:AKGlassControlContainer.class]) bar = (id)child;
    XCTAssertNotNil(bar);
    NSStackView *stack = (id)bar.contentView.subviews.firstObject;
    XCTAssertEqual(stack.arrangedSubviews.count, count);
    XCTAssertFalse(stack.detachesHiddenViews);
    CGFloat previousRight = -CGFLOAT_MAX;
    for (NSButton *button in stack.arrangedSubviews) {
        XCTAssertTrue([button isKindOfClass:AKCallActionButton.class]);
        XCTAssertFalse(button.hidden);
        XCTAssertEqualWithAccuracy(button.frame.size.width, 44, 0.1);
        XCTAssertEqualWithAccuracy(button.frame.size.height, 44, 0.1);
        XCTAssertEqual(button.imagePosition, NSImageOnly);
        XCTAssertNotNil(button.image);
        XCTAssertGreaterThan(button.toolTip.length, 0u);
        XCTAssertEqualObjects(button.toolTip, button.accessibilityLabel);
        NSRect frame = [button convertRect:button.bounds toView:view];
        XCTAssertTrue(NSContainsRect(view.bounds, frame));
        XCTAssertGreaterThanOrEqual(frame.origin.x - previousRight, 11.9);
        previousRight = NSMaxX(frame);
        // Start at the window root so an overlaid backdrop cannot pass simply
        // because the controls still exist below it in the accessibility tree.
        // Near-edge points also catch native alignment margins and frame overlap.
        NSArray<NSValue *> *points = @[
            [NSValue valueWithPoint:NSMakePoint(22, 22)],
            [NSValue valueWithPoint:NSMakePoint(1, 22)],
            [NSValue valueWithPoint:NSMakePoint(43, 22)],
            [NSValue valueWithPoint:NSMakePoint(22, 1)],
            [NSValue valueWithPoint:NSMakePoint(22, 43)]
        ];
        for (NSValue *point in points) {
            NSPoint parentPoint = [button convertPoint:point.pointValue toView:root.superview];
            NSView *hit = [root hitTest:parentPoint];
            XCTAssertTrue(hit == button || [hit isDescendantOf:button],
                          @"%@ loses its 44pt hit region at %@ (hit %@)",
                          button.accessibilityLabel, NSStringFromPoint(point.pointValue), hit);
        }
    }
}
- (void)testWindowRootHitsSurviveCallPaneChangesAndMaterialRebuilds {
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        self.controller.window.appearance = [NSAppearance appearanceNamed:appearance];
        for (NSNumber *state in @[@(kAKSIPCallCallingState), @(kAKSIPCallConfirmedState),
                                  @(kAKSIPCallIncomingState), @(kAKSIPCallDisconnectedState),
                                  @(kAKSIPCallConfirmedState)]) {
            self.call.state = state.unsignedIntegerValue;
            NSView *pane;
            NSUInteger actions;
            if (self.call.state == kAKSIPCallIncomingState) {
                [self.controller showIncomingCallView];
                pane = self.controller.incomingCallViewController.view;
                actions = 2;
            } else if (self.call.state == kAKSIPCallDisconnectedState) {
                [self.controller showEndedCallView];
                pane = self.controller.endedCallViewController.view;
                actions = 1;
            } else {
                [self.controller showActiveCallView];
                pane = self.controller.activeCallViewController.view;
                actions = 5;
            }
            [self assertCompactView:pane actionCount:actions];
            [NSWorkspace.sharedWorkspace.notificationCenter
                postNotificationName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
            [self assertCompactView:pane actionCount:actions];
        }
    }
}
- (void)testActualStateNibsKeepCompactGeometryAndAccountBinding {
    self.controller.status = @"00:12";
    [self.controller showActiveCallView];
    [self.controller.activeCallViewController showHangUp];
    [self assertCompactView:self.controller.activeCallViewController.view actionCount:5];
    XCTAssertEqualObjects(self.controller.window.title, @"Personal");
    XCTAssertEqualObjects([[self.controller.activeCallViewController valueForKey:@"numberField"] stringValue], @"020 7946 0123");
    XCTAssertEqualObjects([[self.controller.activeCallViewController valueForKey:@"statusField"] stringValue], NSLocalizedString(@"Connected", nil));
    self.account.accountDescription = @"Work";
    XCTAssertEqualObjects(self.controller.window.title, @"Work");
    self.account.callsShouldDisplayAccountInfo = NO;
    XCTAssertEqualObjects(self.controller.window.title, @"020 7946 0123");
    self.controller.status = @"incoming call";
    [self.controller showIncomingCallView];
    [self assertCompactView:self.controller.incomingCallViewController.view actionCount:2];
    self.controller.status = @"call ended";
    [self.controller showEndedCallView];
    [self assertCompactView:self.controller.endedCallViewController.view actionCount:1];
}
- (void)testLongErrorExpandsThenOrdinaryStatusRestoresSmallBody {
    [self.controller showActiveCallView];
    self.controller.status = @"The remote telephone could not be reached. Please check the number and try the call again.";
    [self.controller.window.contentView layoutSubtreeIfNeeded];
    NSView *view = self.controller.activeCallViewController.view;
    NSTextField *status = [self.controller.activeCallViewController valueForKey:@"statusField"];
    XCTAssertGreaterThan(view.frame.size.height, 112);
    XCTAssertLessThanOrEqual(view.frame.size.height, 140);
    XCTAssertEqualWithAccuracy(self.controller.window.contentView.frame.size.height, view.frame.size.height, 0.1);
    XCTAssertEqualWithAccuracy(view.frame.origin.y, 0, 0.1);
    XCTAssertTrue(NSContainsRect(view.bounds, status.frame));
    XCTAssertEqualObjects(status.toolTip, self.controller.status);
    self.controller.status = @"00:12";
    [self assertCompactView:view actionCount:5];
}
- (void)testConnectingAndConfirmedControlsUseExistingCallValidation {
    [self.controller prepareForCall];
    self.call.state = kAKSIPCallCallingState;
    [self.controller.activeCallViewController refreshVisibleCallControls];
    NSView *view = self.controller.activeCallViewController.view;
    for (NSString *action in @[@"toggleMicrophoneMute:", @"toggleCallHold:", @"showCallTransferSheet:", @"showKeypad:"]) {
        XCTAssertFalse([self buttonWithAction:NSSelectorFromString(action) inView:view].enabled);
    }
    NSButton *end = [self buttonWithAction:@selector(hangUpCall:) inView:view];
    XCTAssertFalse(end.hidden);
    XCTAssertFalse(end.enabled);
    XCTAssertFalse([[self.controller.activeCallViewController valueForKey:@"callProgressIndicator"] isHidden]);
    self.call.state = kAKSIPCallConfirmedState;
    [self.controller.activeCallViewController allowHangUp];
    [self.controller.activeCallViewController showHangUp];
    [self.controller.activeCallViewController refreshVisibleCallControls];
    XCTAssertTrue(end.enabled);
    NSButton *mute = [self buttonWithAction:@selector(toggleMicrophoneMute:) inView:view];
    [mute performClick:nil];
    XCTAssertTrue(self.call.muted);
    XCTAssertEqualObjects(mute.accessibilityLabel, NSLocalizedString(@"Unmute", nil));
    XCTAssertEqualObjects(mute.accessibilityValue, @YES);
    NSButton *hold = [self buttonWithAction:@selector(toggleCallHold:) inView:view];
    [hold performClick:nil];
    XCTAssertTrue(self.call.localHeld);
    XCTAssertEqualObjects(hold.accessibilityLabel, NSLocalizedString(@"Resume", nil));
    self.call.remoteHeld = YES;
    [self.controller.activeCallViewController refreshVisibleCallControls];
    XCTAssertFalse(hold.enabled);
    XCTAssertFalse([self buttonWithAction:@selector(showCallTransferSheet:) inView:view].enabled);
}
- (void)testKeypadAndPhysicalExtendedDTMFUseSameRealHandler {
    [self.controller showActiveCallView];
    ActiveCallViewController *active = self.controller.activeCallViewController;
    [active prepareKeypad];
    NSPopover *popover = [active valueForKey:@"keypadPopover"];
    XCTAssertEqual(popover.behavior, NSPopoverBehaviorTransient);
    XCTAssertEqualWithAccuracy(popover.contentViewController.view.frame.size.width, 180, 0.1);
    NSUInteger digits = 0;
    for (NSView *child in popover.contentViewController.view.subviews) {
        if (![child isKindOfClass:NSButton.class]) continue;
        NSButton *button = (id)child;
        XCTAssertEqualWithAccuracy(button.frame.size.width, 44, 0.1);
        XCTAssertEqualWithAccuracy(button.frame.size.height, 44, 0.1);
        [button performClick:nil];
        digits++;
    }
    XCTAssertEqual(digits, 12u);
    XCTAssertEqualObjects(self.call.sentDigits, @"123456789*0#");
    [active activeCallView:(AKActiveCallView *)active.view didReceiveText:@"ABCDRabcdr"];
    XCTAssertEqualObjects(self.call.sentDigits, @"123456789*0#ABCDRabcdr");
    XCTAssertEqualObjects(self.controller.displayedName, self.call.sentDigits);
    XCTAssertEqualObjects([[active valueForKey:@"keypadDigitsField"] stringValue], self.call.sentDigits);
    XCTAssertEqualObjects(self.controller.window.title, @"Personal");
    [active activeCallView:(AKActiveCallView *)active.view didReceiveText:@"invalid!"];
    XCTAssertEqualObjects(self.controller.displayedName, self.call.sentDigits);
    self.call.state = kAKSIPCallDisconnectedState;
    for (NSView *child in popover.contentViewController.view.subviews) {
        if ([child isKindOfClass:NSButton.class]) [(NSButton *)child performClick:nil];
    }
    XCTAssertEqualObjects(self.call.sentDigits, @"123456789*0#ABCDRabcdr");
}
- (void)testIncomingButtonsAndNativeCloseRetainSIPActions {
    self.call.state = kAKSIPCallIncomingState;
    [self.controller showIncomingCallView];
    [self.controller.incomingCallViewController.acceptCallButton performClick:nil];
    XCTAssertEqual(self.call.answers, 1u);
    [self.controller.incomingCallViewController.declineCallButton performClick:nil];
    XCTAssertEqual(self.call.hangups, 1u);
    [self assertCompactView:self.controller.endedCallViewController.view actionCount:1];
    self.call.state = kAKSIPCallConfirmedState;
    self.controller.callActive = YES;
    [self.controller showActiveCallView];
    self.controller.window.styleMask |= NSWindowStyleMaskClosable;
    [self.controller.window setFrameOrigin:NSMakePoint(-10000, -10000)];
    [self.controller.window orderFront:nil];
    [[self.controller.window standardWindowButton:NSWindowCloseButton] performClick:nil];
    XCTAssertFalse(self.controller.window.visible);
    XCTAssertFalse(self.controller.isCallActive);
    XCTAssertEqual(self.call.hangups, 2u);
    XCTAssertNil(self.call.delegate);
    XCTAssertNil(self.controller.activeCallViewController.callTimer);
}
- (void)testDisconnectRetainsOneSecondCallBackGuard {
    [self.controller showActiveCallView];
    self.controller.callActive = YES;
    self.call.state = kAKSIPCallDisconnectedState;
    self.call.lastStatus = PJSIP_SC_OK;
    [self.controller SIPCallDidDisconnect:[NSNotification notificationWithName:@"test" object:self.call]];
    XCTAssertFalse(self.controller.endedCallViewController.redialButton.enabled);
    [self assertCompactView:self.controller.endedCallViewController.view actionCount:1];
    XCTestExpectation *reenabled = [self expectationWithDescription:@"original redial delay"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertTrue(self.controller.endedCallViewController.redialButton.enabled);
        [reenabled fulfill];
    });
    [self waitForExpectations:@[reenabled] timeout:3];
}
@end
