#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <sys/resource.h>
#import <time.h>
#import "AKLiquidGlass.h"
#import "AKSIPCall.h"
#import "AKSIPUserAgent.h"
#import "ActiveCallViewController.h"
#import "ActiveCallTransferViewController.h"
#import "CallController.h"

// Category declarations also let the bounded measurement compile against the
// original source. Its selector below uses only APIs present at 7e412da.
@interface ActiveCallViewController (CC67Presentation)
- (void)refreshVisibleCallControls;
- (void)refreshControlPresentation;
- (void)invalidateCallTimer;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
@end
@interface CallController (CC67Presentation)
@property(nonatomic, readonly) BOOL callControlsEnabled, holdChangePending, muteChangePending;
@property(nonatomic, readonly, copy) NSString *presentationTransferStatus;
- (void)unsubscribeFromWindowFloatingChanges;
- (void)setIntermediateStatus:(NSString *)status;
- (void)intermediateStatusTimerTick:(NSTimer *)timer;
- (void)SIPUserAgentAudioStateDidChange:(NSNotification *)notification;
- (void)windowWillClose:(NSNotification *)notification;
@end

// These calls have no account, URI, SIP thread, native media, recorder or file.
// Requests remain under test control so completion ordering is deterministic.
@interface CC67Call : AKSIPCall
@property(nonatomic) BOOL syntheticIncoming, syntheticMuted, syntheticLocalHold, syntheticRemoteHold;
@property(nonatomic) NSMutableArray *holdCompletions, *muteCompletions;
@property(nonatomic) NSUInteger hangups;
@property(nonatomic, copy) void (^hangupCompletion)(BOOL);
@end
@implementation CC67Call
- (instancetype)init {
    if ((self = [super init])) {
        self.state = kAKSIPCallConfirmedState;
        _holdCompletions = [NSMutableArray new]; _muteCompletions = [NSMutableArray new];
    }
    return self;
}
- (BOOL)isIncoming { return self.syntheticIncoming; }
- (BOOL)isActive { return self.state != kAKSIPCallNullState && self.state != kAKSIPCallDisconnectedState; }
- (BOOL)isMicrophoneMuted { return self.syntheticMuted; }
- (BOOL)syntheticLocalHold { return self.localHold; }
- (void)setSyntheticLocalHold:(BOOL)held { self.localHold = held; }
- (BOOL)syntheticRemoteHold { return self.remoteHold; }
- (void)setSyntheticRemoteHold:(BOOL)held { self.remoteHold = held; }
- (BOOL)isRecording { return NO; }
- (NSURL *)recordingURL { return nil; }
- (void)stopRecording {}
- (void)refreshRecordingConnections {}
- (void)requestToggleHoldWithCompletion:(void (^)(BOOL))completion { [self.holdCompletions addObject:[completion copy]]; }
- (void)requestToggleMicrophoneMuteWithCompletion:(void (^)(BOOL))completion { [self.muteCompletions addObject:[completion copy]]; }
- (void)requestHangUpWithCompletion:(void (^)(BOOL))completion { self.hangups++; self.hangupCompletion = completion; }
@end

@interface CC67Agent : NSObject
@property(nonatomic) BOOL hasAudioFailure;
@property(nonatomic, getter=isStarted) BOOL started;
@end
@implementation CC67Agent @end

static char CC67ButtonCounters;
static void CC67CountButton(id button, NSString *key) {
    NSMutableDictionary *counts = objc_getAssociatedObject(button, &CC67ButtonCounters);
    if (counts) counts[key] = @([counts[key] unsignedIntegerValue] + 1);
}
// No ivars are added: only the four fixture-created AKCallActionButton objects
// receive this class, after nib setup. Other application buttons are untouched.
@interface CC67CountingButton : AKCallActionButton @end
@implementation CC67CountingButton
- (void)setImage:(NSImage *)image { CC67CountButton(self, @"imageAssignments"); [super setImage:image]; }
- (void)setAccessibilityLabel:(NSString *)label { CC67CountButton(self, @"accessibilityLabelAssignments"); [super setAccessibilityLabel:label]; }
- (void)setAccessibilityValue:(id)value { CC67CountButton(self, @"accessibilityValueAssignments"); [super setAccessibilityValue:value]; }
- (void)setState:(NSControlStateValue)state { CC67CountButton(self, @"stateAssignments"); [super setState:state]; }
- (void)setEnabled:(BOOL)enabled { CC67CountButton(self, @"enabledAssignments"); [super setEnabled:enabled]; }
@end

static NSUInteger CC67ControlRefreshDepth, CC67MenuInitializations;
static IMP CC67OriginalMenuInitializer;
static id CC67MenuInitializer(id item, SEL selector, NSString *title, SEL action, NSString *key) {
    if (CC67ControlRefreshDepth) CC67MenuInitializations++;
    return ((id (*)(id, SEL, NSString *, SEL, NSString *))CC67OriginalMenuInitializer)(item, selector, title, action, key);
}

@interface CC67View : ActiveCallViewController
@property(nonatomic) NSUInteger durationTicks, durationNotifications, legacyControlRefreshes, controlRefreshes, menuValidations, presentationRefreshes;
@end
@implementation CC67View
- (void)refreshVisibleCallControls {
    self.legacyControlRefreshes++; CC67ControlRefreshDepth++;
    @try { [super refreshVisibleCallControls]; } @finally { CC67ControlRefreshDepth--; }
}
- (void)refreshControlPresentation {
    self.controlRefreshes++; CC67ControlRefreshDepth++;
    @try { [super refreshControlPresentation]; } @finally { CC67ControlRefreshDepth--; }
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { self.menuValidations++; return [super validateMenuItem:item]; }
- (void)callTimerTick:(NSTimer *)timer { self.durationTicks++; [super callTimerTick:timer]; }
- (void)refreshPresentation { self.presentationRefreshes++; [super refreshPresentation]; }
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([path isEqualToString:@"presentationDuration"]) self.durationNotifications++;
    else [super observeValueForKeyPath:path ofObject:object change:change context:context];
}
@end

@interface CC67Controller : CallController
@property(nonatomic) NSWindow *syntheticWindow;
@property(nonatomic) NSUInteger statusAssignments;
- (void)installSyntheticView;
@end
@implementation CC67Controller
- (NSWindow *)window { return self.syntheticWindow; }
- (BOOL)isWindowLoaded { return self.syntheticWindow != nil; }
- (void)unsubscribeFromWindowFloatingChanges {}
- (void)setStatus:(NSString *)status { self.statusAssignments++; [super setStatus:status]; }
- (void)installSyntheticView {
    _activeCallViewController = [[CC67View alloc] initWithNibName:@"ActiveCallView" callController:self];
    _activeCallViewController.representedObject = self.call;
    self.syntheticWindow.contentViewController = _activeCallViewController;
}
- (void)showActiveCallView { self.syntheticWindow.contentViewController = self.activeCallViewController; }
- (void)showEndedCallView {} // No unrelated ended-pane timers in this fixture.
- (void)removeUserNotification {}
- (void)removeOrShowUserNotificationOnDisconnectIfNeeded {}
@end

static NSTimeInterval CC67MonotonicTime(void) {
    struct timespec value; clock_gettime(CLOCK_MONOTONIC, &value);
    return value.tv_sec + value.tv_nsec / 1e9;
}
static NSTimeInterval CC67CPUTime(struct rusage value) {
    return value.ru_utime.tv_sec + value.ru_utime.tv_usec / 1e6 + value.ru_stime.tv_sec + value.ru_stime.tv_usec / 1e6;
}

@interface CallControlPresentationTests : XCTestCase
@property(nonatomic) CC67Controller *controller;
@property(nonatomic) CC67Call *call;
@property(nonatomic) CC67Agent *agent;
@property(nonatomic) NSUserDefaults *defaults;
@property(nonatomic) NSString *suite;
@property(nonatomic) NSMutableArray<CC67Controller *> *fixtures;
@end
@implementation CallControlPresentationTests
- (CC67View *)view { return (CC67View *)self.controller.activeCallViewController; }
- (NSArray<NSButton *> *)buttons:(CC67Controller *)controller { return [controller.activeCallViewController valueForKey:@"visibleCallControls"]; }
- (NSButton *)button:(SEL)action {
    for (NSButton *button in [self buttons:self.controller]) if (button.action == action) return button;
    XCTFail(@"Missing native compact call action %@", NSStringFromSelector(action)); return nil;
}
- (CC67Controller *)makeFixture {
    CC67Controller *controller = [[CC67Controller alloc] initWithWindowNibName:@"Call" accountController:nil userAgent:(id)self.agent delegate:nil];
    [controller setValue:self.defaults forKey:@"defaults"];
    controller.syntheticWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(80 + self.fixtures.count * 320, 100, 300, 112)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    controller.syntheticWindow.releasedWhenClosed = NO;
    controller.title = @"020 7946 0123"; controller.displayedName = @"Synthetic call controls";
    controller.call = [CC67Call new]; controller.callActive = YES;
    controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 12.25;
    controller.status = @"Connected";
    [controller installSyntheticView];
    CC67View *view = (CC67View *)controller.activeCallViewController;
    XCTAssertEqual([self buttons:controller].count, 4u);
    for (NSButton *button in [self buttons:controller]) {
        XCTAssertEqual(object_getClass(button), AKCallActionButton.class);
        object_setClass(button, CC67CountingButton.class);
        objc_setAssociatedObject(button, &CC67ButtonCounters, [NSMutableDictionary new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [controller addObserver:view forKeyPath:@"presentationDuration" options:0 context:NULL];
    [self.fixtures addObject:controller];
    return controller;
}
- (void)setUp {
    [super setUp];
    self.suite = [@"test.telephone.controls67." stringByAppendingString:NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suite];
    [self.defaults setBool:NO forKey:@"AutomaticallyRecordCalls"];
    self.agent = [CC67Agent new]; self.agent.started = YES;
    self.fixtures = [NSMutableArray new];
    CC67ControlRefreshDepth = CC67MenuInitializations = 0;
    CC67OriginalMenuInitializer = method_setImplementation(class_getInstanceMethod(NSMenuItem.class, @selector(initWithTitle:action:keyEquivalent:)), (IMP)CC67MenuInitializer);
    self.controller = [self makeFixture]; self.call = (CC67Call *)self.controller.call;
}
- (void)tearDown {
    for (CC67Controller *controller in self.fixtures) {
        CC67View *view = (CC67View *)controller.activeCallViewController;
        [controller removeObserver:view forKeyPath:@"presentationDuration"];
        controller.callActive = NO;
        [view stopCallTimer]; [view removeObservations];
        [controller.intermediateStatusTimer invalidate]; controller.intermediateStatusTimer = nil;
        [NSObject cancelPreviousPerformRequestsWithTarget:controller];
        CC67Call *call = (CC67Call *)controller.call;
        [call.holdCompletions removeAllObjects]; [call.muteCompletions removeAllObjects];
        call.hangupCompletion = nil;
        [controller.syntheticWindow orderOut:nil]; controller.syntheticWindow.contentViewController = nil;
        [controller.syntheticWindow close]; controller.syntheticWindow = nil;
    }
    method_setImplementation(class_getInstanceMethod(NSMenuItem.class, @selector(initWithTitle:action:keyEquivalent:)), CC67OriginalMenuInitializer);
    self.controller = nil; self.call = nil; self.fixtures = nil;
    [self.defaults removePersistentDomainForName:self.suite];
    [super tearDown];
}
- (void)resetCounts {
    CC67MenuInitializations = 0;
    for (CC67Controller *controller in self.fixtures) {
        CC67View *view = (CC67View *)controller.activeCallViewController;
        view.durationTicks = view.durationNotifications = view.legacyControlRefreshes = view.controlRefreshes = view.menuValidations = view.presentationRefreshes = 0;
        controller.statusAssignments = 0;
        for (NSButton *button in [self buttons:controller]) [objc_getAssociatedObject(button, &CC67ButtonCounters) removeAllObjects];
    }
}
- (NSDictionary *)counts {
    NSMutableDictionary *result = [@{@"timerFirings":@0, @"durationNotifications":@0, @"legacyControlRefreshCalls":@0,
        @"controlRefreshCalls":@0, @"menuValidations":@0, @"menuItemInitializations":@(CC67MenuInitializations),
        @"statusAssignments":@0, @"presentationRefreshes":@0, @"imageAssignments":@0,
        @"accessibilityLabelAssignments":@0, @"accessibilityValueAssignments":@0, @"stateAssignments":@0, @"enabledAssignments":@0} mutableCopy];
    for (CC67Controller *controller in self.fixtures) {
        CC67View *view = (CC67View *)controller.activeCallViewController;
        NSDictionary *values = @{@"timerFirings":@(view.durationTicks), @"durationNotifications":@(view.durationNotifications),
            @"legacyControlRefreshCalls":@(view.legacyControlRefreshes), @"controlRefreshCalls":@(view.controlRefreshes),
            @"menuValidations":@(view.menuValidations), @"statusAssignments":@(controller.statusAssignments),
            @"presentationRefreshes":@(view.presentationRefreshes)};
        for (NSString *key in values) result[key] = @([result[key] unsignedIntegerValue] + [values[key] unsignedIntegerValue]);
        for (NSButton *button in [self buttons:controller]) {
            NSDictionary *counts = objc_getAssociatedObject(button, &CC67ButtonCounters);
            for (NSString *key in counts) result[key] = @([result[key] unsignedIntegerValue] + [counts[key] unsignedIntegerValue]);
        }
    }
    return result;
}
- (void)runMainLoopFor:(NSTimeInterval)seconds {
    NSTimeInterval deadline = CC67MonotonicTime() + seconds;
    while (CC67MonotonicTime() < deadline) {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:MIN(.05, deadline - CC67MonotonicTime())]];
    }
}
- (NSInteger)durationSeconds:(NSString *)duration {
    NSInteger seconds = 0;
    for (NSString *component in [duration componentsSeparatedByString:@":"]) seconds = seconds * 60 + component.integerValue;
    return seconds;
}

- (void)testDurationTimerUsesOneSecondAndToleranceAndHasNoDuplicateStart {
    [self.view startCallTimer]; NSTimer *timer = self.view.callTimer;
    XCTAssertNotNil(timer); XCTAssertTrue(timer.isValid);
    XCTAssertEqualWithAccuracy(timer.timeInterval, 1.0, .0001);
    XCTAssertGreaterThanOrEqual(timer.tolerance, .1); XCTAssertLessThanOrEqual(timer.tolerance, .5);
    [self.view startCallTimer]; XCTAssertEqual(self.view.callTimer, timer);
}
- (void)testDelayedTickUsesWallClockAndUpdatesBoundDurationWithoutStatusMutation {
    [self.view startCallTimer]; self.controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 3671.25;
    [self resetCounts]; [self.view callTimerTick:self.view.callTimer];
    NSInteger seconds = [self durationSeconds:self.controller.presentationDuration];
    XCTAssertGreaterThanOrEqual(seconds, 3671); XCTAssertLessThanOrEqual(seconds, 3672);
    XCTAssertEqualObjects([[self.view valueForKey:@"durationField"] stringValue], self.controller.presentationDuration);
    XCTAssertEqual(self.controller.statusAssignments, 0u); XCTAssertEqual(self.view.presentationRefreshes, 0u);
    XCTAssertEqual(self.view.durationNotifications, 1u);
}
- (void)testStableTicksAndRepeatedRefreshesDoNotRebuildOrRewriteControls {
    [self.view startCallTimer]; [self.view refreshControlPresentation]; [self resetCounts];
    for (NSUInteger index = 0; index < 20; index++) { [self.view callTimerTick:self.view.callTimer]; [self.view refreshControlPresentation]; }
    NSDictionary *counts = [self counts];
    for (NSString *key in @[@"menuValidations", @"menuItemInitializations", @"imageAssignments", @"accessibilityLabelAssignments",
                            @"accessibilityValueAssignments", @"stateAssignments", @"enabledAssignments", @"statusAssignments", @"presentationRefreshes"])
        XCTAssertEqual([counts[key] unsignedIntegerValue], 0u, @"%@ must remain unchanged: %@", key, counts);
    XCTAssertEqual(self.view.durationNotifications, 20u);
}
- (void)testLocalHoldAndMutedStatusKeepTheSameWallClockTimer {
    [self.view startCallTimer]; NSTimer *timer = self.view.callTimer;
    self.call.syntheticLocalHold = YES;
    [self.controller SIPCallDidLocalHold:[NSNotification notificationWithName:AKSIPCallDidLocalHoldNotification object:self.call]];
    XCTAssertEqual(self.view.callTimer, timer); XCTAssertTrue(timer.isValid);
    NSString *hold = self.controller.status;
    self.controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 95.25;
    [self.view callTimerTick:timer];
    XCTAssertEqualObjects(self.controller.status, hold); XCTAssertGreaterThanOrEqual([self durationSeconds:self.controller.presentationDuration], 95);
    self.call.syntheticLocalHold = NO; self.controller.callOnHold = NO; self.call.syntheticMuted = YES;
    self.controller.status = @"mic muted"; [self.view stopCallTimer]; [self.view callTimerTick:timer];
    XCTAssertEqual(self.view.callTimer, timer); XCTAssertTrue(timer.isValid); XCTAssertEqualObjects(self.controller.status, @"mic muted");
}
- (void)testMutePendingSuccessAndFailureImmediatelyReconcileNativeButton {
    NSButton *mute = [self button:@selector(toggleMicrophoneMute:)];
    mute.state = NSControlStateValueOn; [self.view toggleMicrophoneMute:mute];
    XCTAssertTrue(self.controller.muteChangePending); XCTAssertFalse(mute.enabled); XCTAssertEqual(mute.state, NSControlStateValueOff);
    [self.controller toggleMicrophoneMute]; XCTAssertEqual(self.call.muteCompletions.count, 1u);
    self.call.syntheticMuted = YES; void (^complete)(BOOL) = self.call.muteCompletions.firstObject; complete(YES);
    XCTAssertFalse(self.controller.muteChangePending); XCTAssertTrue(mute.enabled); XCTAssertEqual(mute.state, NSControlStateValueOn);
    XCTAssertEqualObjects(mute.accessibilityValue, @YES); XCTAssertEqualObjects(mute.accessibilityLabel, NSLocalizedString(@"Unmute", nil));
    [self.controller toggleMicrophoneMute]; XCTAssertFalse(mute.enabled);
    void (^fail)(BOOL) = self.call.muteCompletions.lastObject; fail(NO);
    XCTAssertTrue(mute.enabled); XCTAssertEqual(mute.state, NSControlStateValueOn); XCTAssertTrue([self.controller.status containsString:@"Could not change mute"]);
}
- (void)testHoldPendingSuccessAndFailureUpdateHoldAndTransferWithoutATimerTick {
    NSButton *hold = [self button:@selector(toggleCallHold:)], *transfer = [self button:@selector(showCallTransferSheet:)];
    [self.view toggleCallHold:hold]; XCTAssertTrue(self.controller.holdChangePending); XCTAssertFalse(hold.enabled); XCTAssertFalse(transfer.enabled);
    [self.controller toggleCallHold]; XCTAssertEqual(self.call.holdCompletions.count, 1u);
    self.call.syntheticLocalHold = YES; void (^complete)(BOOL) = self.call.holdCompletions.firstObject; complete(YES);
    [self.controller SIPCallDidLocalHold:[NSNotification notificationWithName:AKSIPCallDidLocalHoldNotification object:self.call]];
    XCTAssertFalse(self.controller.holdChangePending); XCTAssertTrue(hold.enabled); XCTAssertTrue(transfer.enabled);
    XCTAssertEqual(hold.state, NSControlStateValueOn); XCTAssertEqualObjects(hold.accessibilityLabel, NSLocalizedString(@"Resume", nil));
    [self.controller toggleCallHold]; void (^fail)(BOOL) = self.call.holdCompletions.lastObject; fail(NO);
    XCTAssertTrue(hold.enabled); XCTAssertTrue(transfer.enabled); XCTAssertEqual(hold.state, NSControlStateValueOn);
    XCTAssertTrue([self.controller.status containsString:@"Could not change hold"]);
}
- (void)testAcceptedHoldRequestWaitsForNativeMediaBeforeSelectingResume {
    NSButton *hold = [self button:@selector(toggleCallHold:)];
    hold.state = NSControlStateValueOn; [self.view toggleCallHold:hold];
    XCTAssertEqual(hold.state, NSControlStateValueOff); XCTAssertFalse(hold.enabled);
    void (^complete)(BOOL) = self.call.holdCompletions.firstObject; complete(YES);
    XCTAssertFalse(self.controller.holdChangePending); XCTAssertTrue(hold.enabled);
    XCTAssertEqual(hold.state, NSControlStateValueOff); XCTAssertEqualObjects(hold.accessibilityLabel, NSLocalizedString(@"Hold", nil));
    self.call.localHold = YES;
    [self.controller SIPCallDidLocalHold:[NSNotification notificationWithName:AKSIPCallDidLocalHoldNotification object:self.call]];
    XCTAssertEqual(hold.state, NSControlStateValueOn); XCTAssertEqualObjects(hold.accessibilityLabel, NSLocalizedString(@"Resume", nil));
}
- (void)testReplacementRejectsBothOldCompletionsAndRetainsNewPendingAttempt {
    CC67Call *old = self.call;
    [self.controller toggleMicrophoneMute]; [self.controller toggleCallHold];
    CC67Call *replacement = [CC67Call new]; self.controller.call = replacement; self.call = replacement;
    [self.controller toggleMicrophoneMute]; [self.controller toggleCallHold];
    void (^oldMute)(BOOL) = old.muteCompletions.firstObject; void (^oldHold)(BOOL) = old.holdCompletions.firstObject;
    NSString *status = self.controller.status; oldMute(NO); oldHold(NO);
    XCTAssertTrue(self.controller.muteChangePending); XCTAssertTrue(self.controller.holdChangePending);
    XCTAssertFalse([self button:@selector(toggleMicrophoneMute:)].enabled); XCTAssertFalse([self button:@selector(toggleCallHold:)].enabled);
    XCTAssertEqualObjects(self.controller.status, status);
    replacement.syntheticMuted = YES; void (^newMute)(BOOL) = replacement.muteCompletions.firstObject; newMute(YES);
    void (^newHold)(BOOL) = replacement.holdCompletions.firstObject; newHold(NO);
    XCTAssertFalse(self.controller.muteChangePending); XCTAssertFalse(self.controller.holdChangePending);
    XCTAssertEqual([self button:@selector(toggleMicrophoneMute:)].state, NSControlStateValueOn);
    [old.holdCompletions removeAllObjects]; [old.muteCompletions removeAllObjects];
}
- (void)testIncomingAndOutgoingConfirmationRefreshBeforeTheFirstTimerTick {
    for (NSNumber *incoming in @[@NO, @YES]) {
        self.call.syntheticIncoming = incoming.boolValue;
        self.call.state = incoming.boolValue ? kAKSIPCallIncomingState : kAKSIPCallCallingState;
        [self.view refreshControlPresentation];
        for (NSButton *button in [self buttons:self.controller]) XCTAssertFalse(button.enabled);
        self.call.state = kAKSIPCallConfirmedState;
        [self.controller SIPCallDidConfirm:[NSNotification notificationWithName:AKSIPCallDidConfirmNotification object:self.call]];
        for (NSButton *button in [self buttons:self.controller]) XCTAssertTrue(button.enabled);
        XCTAssertTrue(self.view.callTimer.isValid);
    }
}
- (void)testRemoteHoldAndAudioFailureRefreshControlsWithoutDurationPolling {
    [self.view startCallTimer]; NSTimer *timer = self.view.callTimer;
    self.call.syntheticRemoteHold = YES;
    [self.controller SIPCallDidRemoteHold:[NSNotification notificationWithName:AKSIPCallDidRemoteHoldNotification object:self.call]];
    XCTAssertFalse([self button:@selector(toggleCallHold:)].enabled); XCTAssertFalse([self button:@selector(showCallTransferSheet:)].enabled);
    XCTAssertTrue([self button:@selector(toggleMicrophoneMute:)].enabled); XCTAssertTrue([self button:@selector(showKeypad:)].enabled);
    self.agent.hasAudioFailure = YES;
    [self.controller SIPUserAgentAudioStateDidChange:[NSNotification notificationWithName:AKSIPUserAgentAudioStateDidChangeNotification object:self.agent]];
    XCTAssertEqualObjects(self.controller.status, NSLocalizedString(@"Audio unavailable", nil));
    [self.view callTimerTick:timer]; XCTAssertEqualObjects(self.controller.status, NSLocalizedString(@"Audio unavailable", nil));
    XCTAssertEqual(self.view.callTimer, timer);
    self.call.syntheticRemoteHold = NO;
    [self.controller SIPCallMediaDidBecomeActive:[NSNotification notificationWithName:AKSIPCallMediaDidBecomeActiveNotification object:self.call]];
    XCTAssertTrue([self button:@selector(toggleCallHold:)].enabled); XCTAssertTrue([self button:@selector(showCallTransferSheet:)].enabled);
    self.agent.hasAudioFailure = NO;
    [self.controller SIPUserAgentAudioStateDidChange:[NSNotification notificationWithName:AKSIPUserAgentAudioStateDidChangeNotification object:self.agent]];
    XCTAssertNotEqualObjects(self.controller.status, NSLocalizedString(@"Audio unavailable", nil));
}
- (void)testSilentMediaCacheClearRefreshesLocalAndRemoteHoldWithoutNamedNotification {
    NSButton *hold = [self button:@selector(toggleCallHold:)], *transfer = [self button:@selector(showCallTransferSheet:)];
    self.call.localHold = YES;
    XCTAssertEqual(hold.state, NSControlStateValueOn);
    self.call.localHold = NO; // PJSUA NONE/ERROR cache update has no active-media callback.
    XCTAssertEqual(hold.state, NSControlStateValueOff);
    XCTAssertEqualObjects(hold.accessibilityLabel, NSLocalizedString(@"Hold", nil));
    self.call.remoteHold = YES; XCTAssertFalse(hold.enabled); XCTAssertFalse(transfer.enabled);
    self.call.remoteHold = NO;
    XCTAssertTrue(hold.enabled); XCTAssertTrue(transfer.enabled);
    CC67Call *old = self.call; self.controller.call = [CC67Call new]; self.call = (CC67Call *)self.controller.call;
    old.remoteHold = YES; old.localHold = YES;
    XCTAssertTrue(hold.enabled); XCTAssertEqual(hold.state, NSControlStateValueOff);
}
- (void)testInactiveReplacementRemovalAndViewDisappearanceInvalidateTimers {
    [self.view startCallTimer]; NSTimer *first = self.view.callTimer;
    self.controller.callActive = NO; XCTAssertFalse(first.isValid); XCTAssertNil(self.view.callTimer);
    self.controller.callActive = YES; [self.view startCallTimer]; NSTimer *second = self.view.callTimer;
    self.controller.call = [CC67Call new]; self.call = (CC67Call *)self.controller.call;
    XCTAssertFalse(second.isValid); XCTAssertNil(self.view.callTimer);
    [self.view startCallTimer]; NSTimer *third = self.view.callTimer;
    [self.view viewWillDisappear]; XCTAssertFalse(third.isValid); XCTAssertNil(self.view.callTimer);
    [self.view startCallTimer]; NSTimer *fourth = self.view.callTimer;
    self.controller.call = nil; XCTAssertFalse(fourth.isValid); XCTAssertNil(self.view.callTimer);
    [self.view startCallTimer]; XCTAssertNil(self.view.callTimer);
}
- (void)testReplacedTimerCannotNotifyOrOverwriteReusedCall {
    [self.view startCallTimer]; NSTimer *oldTimer = self.view.callTimer;
    self.controller.call = [CC67Call new]; self.call = (CC67Call *)self.controller.call;
    [self.view startCallTimer]; NSTimer *newTimer = self.view.callTimer;
    self.controller.status = @"Current call status"; [self resetCounts];
    [self.view callTimerTick:oldTimer];
    XCTAssertEqual(self.view.callTimer, newTimer); XCTAssertTrue(newTimer.isValid);
    XCTAssertEqual(self.view.durationNotifications, 0u); XCTAssertEqualObjects(self.controller.status, @"Current call status");
}
- (void)testHangupPendingFailureAndAcceptedEndRefreshWithoutPolling {
    [self.view startCallTimer]; NSTimer *timer = self.view.callTimer;
    [self.controller hangUpCall];
    for (NSButton *button in [self buttons:self.controller]) XCTAssertFalse(button.enabled);
    XCTAssertEqual(self.call.hangups, 1u); [self.controller hangUpCall]; XCTAssertEqual(self.call.hangups, 1u);
    self.call.hangupCompletion(NO);
    for (NSButton *button in [self buttons:self.controller]) XCTAssertTrue(button.enabled);
    XCTAssertTrue(timer.isValid);
    [self.controller hangUpCall]; self.call.hangupCompletion(YES);
    for (NSButton *button in [self buttons:self.controller]) XCTAssertFalse(button.enabled);
    XCTAssertFalse(timer.isValid); XCTAssertNil(self.view.callTimer); XCTAssertFalse(self.controller.isCallActive);
}
- (void)testClosingViewRejectsLateCompletionAndDetachesHoldObservation {
    [self.view startCallTimer]; NSTimer *timer = self.view.callTimer;
    [self.controller toggleMicrophoneMute]; [self.controller toggleCallHold];
    void (^mute)(BOOL) = self.call.muteCompletions.firstObject, (^hold)(BOOL) = self.call.holdCompletions.firstObject;
    [self.controller windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:self.controller.syntheticWindow]];
    NSString *status = self.controller.status;
    mute(NO); hold(NO); self.call.remoteHold = YES;
    XCTAssertEqualObjects(self.controller.status, status); XCTAssertFalse(timer.isValid); XCTAssertNil(self.view.callTimer);
    XCTAssertFalse(self.controller.muteChangePending); XCTAssertFalse(self.controller.holdChangePending);
    for (NSButton *button in [self buttons:self.controller]) XCTAssertFalse(button.enabled);
}
- (void)testRemovedObservationsPermitViewReuseWithFreshControlsAndTimer {
    [self.view startCallTimer]; NSTimer *timer = self.view.callTimer;
    [self.view removeObservations]; XCTAssertFalse(timer.isValid); XCTAssertNil(self.view.callTimer);
    self.controller.call = [CC67Call new]; self.call = (CC67Call *)self.controller.call;
    self.call.syntheticMuted = YES; [self.view refreshControlPresentation];
    XCTAssertEqual([self button:@selector(toggleMicrophoneMute:)].state, NSControlStateValueOn);
    [self.view startCallTimer]; XCTAssertTrue(self.view.callTimer.isValid); XCTAssertNotEqual(self.view.callTimer, timer);
    self.controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 183.25;
    [self.view callTimerTick:self.view.callTimer];
    XCTAssertEqualObjects([[self.view valueForKey:@"durationField"] stringValue], self.controller.presentationDuration);
    XCTAssertGreaterThanOrEqual([self durationSeconds:self.controller.presentationDuration], 183);
}
- (void)testCompiledTransferNibUsesWallClockBindingAndPreservesHoldStatus {
    ActiveCallTransferViewController *transfer = [[ActiveCallTransferViewController alloc] initWithNibName:@"ActiveCallTransferView" callController:self.controller];
    transfer.representedObject = self.call; (void)transfer.view;
    NSTextField *status = [transfer valueForKey:@"statusField"];
    XCTAssertNotNil(status); XCTAssertNotNil([status infoForBinding:NSValueBinding]);
    [transfer startCallTimer];
    self.controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 125.25;
    [self resetCounts]; [transfer callTimerTick:transfer.callTimer];
    XCTAssertEqualObjects(status.stringValue, self.controller.presentationDuration);
    XCTAssertEqualObjects(self.controller.presentationTransferStatus, self.controller.presentationDuration);
    XCTAssertEqual(self.controller.statusAssignments, 0u);
    self.call.localHold = YES; self.controller.status = @"on hold";
    [transfer stopCallTimer]; NSTimer *timer = transfer.callTimer;
    [transfer callTimerTick:timer]; XCTAssertTrue(timer.isValid); XCTAssertEqualObjects(status.stringValue, @"on hold");
    [transfer removeObservations]; XCTAssertFalse(timer.isValid); XCTAssertNil(transfer.callTimer);
}

// This is an actual AppKit run-loop measurement, not a source-derived count.
// Build/run ONLY this selector against the archived baseline and the candidate.
// It intentionally has no CPU threshold: a short process sample cannot establish
// energy/battery savings, SIP readiness or real-world calling performance.
- (void)testBoundedStableCallMeasurement {
    // Optional attachment window for xctrace; absent in normal measurements.
    NSString *profileDelay = NSProcessInfo.processInfo.environment[@"CC67_PROFILE_DELAY"];
    if (profileDelay.length) {
        NSTimeInterval delay = MIN(30, MAX(0, profileDelay.doubleValue));
        NSLog(@"CC67_PROFILE_READY pid=%d delay=%.1f", NSProcessInfo.processInfo.processIdentifier, delay);
        [self runMainLoopFor:delay];
    }
    for (NSNumber *cardCount in @[@1, @4]) {
        while (self.fixtures.count < cardCount.unsignedIntegerValue) [self makeFixture];
        for (NSNumber *visible in @[@YES, @NO]) {
            for (CC67Controller *controller in self.fixtures) {
                if (visible.boolValue) [controller.syntheticWindow orderFront:nil]; else [controller.syntheticWindow orderOut:nil];
                [controller.activeCallViewController startCallTimer];
            }
            [self runMainLoopFor:.15]; [self resetCounts];
            struct rusage before, after; XCTAssertEqual(getrusage(RUSAGE_SELF, &before), 0);
            NSTimeInterval start = CC67MonotonicTime(); [self runMainLoopFor:2.2];
            NSTimeInterval wall = CC67MonotonicTime() - start; XCTAssertEqual(getrusage(RUSAGE_SELF, &after), 0);
            NSMutableDictionary *record = [[self counts] mutableCopy];
            record[@"cards"] = cardCount; record[@"visible"] = visible; record[@"wallSeconds"] = @(wall);
            record[@"processCPUSeconds"] = @(CC67CPUTime(after) - CC67CPUTime(before));
            record[@"processCPUPercent"] = @(100 * [record[@"processCPUSeconds"] doubleValue] / wall);
            record[@"scope"] = @"synthetic real-nib AppKit cards; no SIP, audio, Contacts, Keychain or real defaults";
            NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
            NSLog(@"CC67_MEASUREMENT %@", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
            XCTAssertGreaterThan([record[@"timerFirings"] unsignedIntegerValue], 0u);
            for (CC67Controller *controller in self.fixtures) { controller.callActive = NO; [controller.activeCallViewController stopCallTimer]; controller.callActive = YES; }
        }
    }
}
@end
