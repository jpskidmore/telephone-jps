#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "AppController.h"

@interface AppController (AudioRecoveryWatchdogPresentationTests)
- (void)installAudioRecoveryMenuItem;
- (void)updateAudioRecoveryMenuItem;
- (void)SIPUserAgentAudioStateDidChange:(NSNotification *)notification;
- (void)retryAudio:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (NSTimeInterval)monotonicAudioRecoveryTime;
- (id)scheduleAudioRecoveryWatchdogAfter:(NSTimeInterval)delay action:(dispatch_block_t)action;
@end

// Inert synthetic boundary: no AKSIPUserAgent initializer, worker, device,
// defaults, CompositionRoot, credentials, provider, or permission dialog.
@interface ARPresentationAgent : NSObject
@property(nonatomic, getter=isStarted) BOOL started;
@property(nonatomic) BOOL hasAudioFailure, audioCommandPending;
@property(nonatomic) NSUInteger audioGeneration, audioSelectionRevision, retries;
@end
@implementation ARPresentationAgent
- (BOOL)retrySoundAfterFailure {
    self.retries++;
    self.audioSelectionRevision++;
    self.audioCommandPending = YES;
    return YES;
}
@end

// A pre-launch/termination collaborator intentionally has no audio API.
@interface ARMinimalTerminationAgent : NSObject
@property(nonatomic) NSUInteger queries;
@end
@implementation ARMinimalTerminationAgent
- (BOOL)isStarted { self.queries++; return NO; }
- (AKSIPUserAgentState)state { self.queries++; return AKSIPUserAgentStateStopped; }
@end

@interface ARPresentationTimer : NSObject
@property(nonatomic) NSTimeInterval delay;
@property(nonatomic) BOOL invalidated;
@property(nonatomic, copy) dispatch_block_t action;
@end
@implementation ARPresentationTimer
- (void)invalidate { self.invalidated = YES; }
// Also fire cancelled tokens: a callback already queued must still be harmless.
- (void)fire { self.action(); }
@end

@interface ARPresentationController : AppController
@property(nonatomic) ARPresentationAgent *syntheticAgent;
@property(nonatomic) NSMenu *syntheticMenu;
@property(nonatomic) NSMutableArray<ARPresentationTimer *> *timers;
@property(nonatomic) NSTimeInterval now;
@end
@implementation ARPresentationController
- (AKSIPUserAgent *)userAgent { return (id)self.syntheticAgent; }
- (NSTimeInterval)monotonicAudioRecoveryTime { return self.now; }
- (id)scheduleAudioRecoveryWatchdogAfter:(NSTimeInterval)delay action:(dispatch_block_t)action {
    ARPresentationTimer *timer = [ARPresentationTimer new];
    timer.delay = delay; timer.action = action;
    [self.timers addObject:timer];
    return timer;
}
@end

@interface AudioRecoveryWatchdogPresentationTests : XCTestCase @end
@implementation AudioRecoveryWatchdogPresentationTests

- (ARPresentationController *)controller {
    // Deliberately bypass AppController.init, which constructs the normal app.
    ARPresentationController *controller = class_createInstance(ARPresentationController.class, 0);
    controller.syntheticAgent = [ARPresentationAgent new];
    controller.syntheticAgent.started = YES;
    controller.syntheticAgent.audioGeneration = 7;
    controller.syntheticAgent.audioSelectionRevision = 11;
    controller.timers = [NSMutableArray new];
    controller.syntheticMenu = [[NSMenu alloc] initWithTitle:@"Synthetic application menu"];
    controller.syntheticMenu.autoenablesItems = NO;
    NSMenuItem *preferences = [[NSMenuItem alloc] initWithTitle:@"Settings…" action:NULL keyEquivalent:@""];
    [controller.syntheticMenu addItem:preferences];
    [controller setValue:preferences forKey:@"preferencesMenuItem"];
    [controller installAudioRecoveryMenuItem];
    return controller;
}

- (NSMenuItem *)item:(ARPresentationController *)controller { return [controller valueForKey:@"retryAudioMenuItem"]; }

- (ARPresentationTimer *)beginFailedOperation:(ARPresentationController *)controller {
    controller.syntheticAgent.hasAudioFailure = YES;
    controller.syntheticAgent.audioCommandPending = YES;
    [controller updateAudioRecoveryMenuItem];
    return controller.timers.lastObject;
}

- (void)testInitialItemRemainsNativeAndUnavailableWithoutFailure {
    ARPresentationController *controller = [self controller];
    NSMenuItem *item = [self item:controller];
    XCTAssertEqualObjects(item.title, @"Retry Audio");
    XCTAssertFalse(item.enabled);
    XCTAssertNil(item.view);
    XCTAssertEqual(item.target, controller);
    XCTAssertEqual(item.action, @selector(retryAudio:));
    XCTAssertEqual(controller.syntheticMenu.numberOfItems, 2);
    XCTAssertEqual(controller.timers.count, 0);
    XCTAssertFalse([item.toolTip containsString:@"online"]);
}

- (void)testFailureOffersExplicitRetryWithPrivateMicrophoneGuidance {
    ARPresentationController *controller = [self controller];
    controller.syntheticAgent.hasAudioFailure = YES;
    [controller updateAudioRecoveryMenuItem];
    NSMenuItem *item = [self item:controller];
    XCTAssertEqualObjects(item.title, @"Audio unavailable: Retry Audio");
    XCTAssertTrue(item.enabled);
    XCTAssertNil(item.view);
    XCTAssertEqualObjects(item.accessibilityLabel, item.title);
    XCTAssertTrue([item.accessibilityHelp containsString:@"Privacy & Security > Microphone"]);
    XCTAssertTrue([item.accessibilityHelp containsString:@"will not retry automatically"]);
    XCTAssertEqual(controller.syntheticAgent.retries, 0);
}

- (void)testPendingUsesNativeIndeterminateProgressAndDisablesRetry {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    NSMenuItem *item = [self item:controller];
    NSProgressIndicator *indicator = [controller valueForKey:@"audioRecoveryProgressIndicator"];
    XCTAssertEqualObjects(item.title, @"Trying audio…");
    XCTAssertFalse(item.enabled);
    XCTAssertFalse([controller validateMenuItem:item]);
    XCTAssertEqualObjects(item.accessibilityLabel, item.title);
    XCTAssertEqualObjects(item.view.identifier, @"AudioRecoveryProgress");
    XCTAssertEqual(indicator.style, NSProgressIndicatorStyleSpinning);
    XCTAssertTrue(indicator.indeterminate);
    XCTAssertFalse(indicator.displayedWhenStopped);
    XCTAssertEqualObjects(indicator.accessibilityLabel, @"Audio operation in progress");
    XCTAssertEqualWithAccuracy(timer.delay, 5, 0.0001);
    XCTAssertTrue(controller.syntheticAgent.audioCommandPending);
    XCTAssertTrue(controller.syntheticAgent.hasAudioFailure);
}

- (void)testEarlyTimerRechecksMonotonicTimeWithoutPaintingSlow {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.now = 3.5;
    [timer fire];
    XCTAssertEqualObjects([self item:controller].title, @"Trying audio…");
    XCTAssertEqual(controller.timers.count, 2);
    XCTAssertEqualWithAccuracy(controller.timers.lastObject.delay, 1.5, 0.0001);
    XCTAssertTrue(controller.syntheticAgent.audioCommandPending);
}

- (void)testFiveSecondsShowsSlowGuidanceWithoutTimeoutOrAutomaticRetry {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.now = 5;
    [timer fire];
    NSMenuItem *item = [self item:controller];
    XCTAssertEqualObjects(item.title, @"Audio is taking longer…");
    XCTAssertTrue([item.accessibilityHelp containsString:@"still running"]);
    XCTAssertTrue([item.accessibilityHelp containsString:@"has not cancelled"]);
    XCTAssertFalse(item.enabled);
    XCTAssertNotNil(item.view);
    XCTAssertTrue(controller.syntheticAgent.audioCommandPending);
    XCTAssertTrue(controller.syntheticAgent.hasAudioFailure);
    XCTAssertEqual(controller.syntheticAgent.retries, 0);
    XCTAssertEqual(controller.timers.count, 1);
}

- (void)testLateTimerUsesElapsedTimeWithoutClaimingBackendCancellation {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.now = 19;
    [timer fire];
    XCTAssertEqualObjects([self item:controller].title, @"Audio is taking longer…");
    XCTAssertTrue(controller.syntheticAgent.audioCommandPending);
    XCTAssertEqual(controller.syntheticAgent.retries, 0);
}

- (void)testDuplicatePendingUpdatesDoNotRestartTheSlowThreshold {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.now = 4;
    [controller updateAudioRecoveryMenuItem];
    XCTAssertEqual(controller.timers.count, 1);
    controller.now = 5;
    [timer fire];
    XCTAssertEqualObjects([self item:controller].title, @"Audio is taking longer…");
}

- (void)testOnlyMatchingFailedOperationCompletionReportsRecovered {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.syntheticAgent.audioCommandPending = NO;
    controller.syntheticAgent.hasAudioFailure = NO;
    [controller updateAudioRecoveryMenuItem];
    NSMenuItem *item = [self item:controller];
    XCTAssertEqualObjects(item.title, @"Audio recovered");
    XCTAssertFalse(item.enabled);
    XCTAssertNil(item.view);
    XCTAssertTrue(timer.invalidated);
    controller.now = 20; [timer fire];
    XCTAssertEqualObjects(item.title, @"Audio recovered");
}

- (void)testOrdinarySelectionSuccessDoesNotClaimRecovery {
    ARPresentationController *controller = [self controller];
    controller.syntheticAgent.audioCommandPending = YES;
    [controller updateAudioRecoveryMenuItem];
    controller.syntheticAgent.audioCommandPending = NO;
    [controller updateAudioRecoveryMenuItem];
    XCTAssertEqualObjects([self item:controller].title, @"Retry Audio");
    XCTAssertNil([self item:controller].view);
}

- (void)testFailureCompletionRestoresExplicitActionAndRejectsLateTimer {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.syntheticAgent.audioCommandPending = NO;
    [controller updateAudioRecoveryMenuItem];
    NSMenuItem *item = [self item:controller];
    XCTAssertTrue(timer.invalidated);
    XCTAssertTrue(item.enabled);
    XCTAssertNil(item.view);
    controller.now = 12; [timer fire];
    XCTAssertEqualObjects(item.title, @"Audio unavailable: Retry Audio");
}

- (void)testNewSelectionRevisionOwnsItsDeadlineAndRejectsOlderTimer {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *old = [self beginFailedOperation:controller];
    controller.now = 4;
    controller.syntheticAgent.audioSelectionRevision++;
    [controller updateAudioRecoveryMenuItem];
    XCTAssertTrue(old.invalidated);
    XCTAssertEqual(controller.timers.count, 2);
    controller.now = 6; [old fire];
    XCTAssertEqualObjects([self item:controller].title, @"Trying audio…");
    controller.now = 9; [controller.timers.lastObject fire];
    XCTAssertEqualObjects([self item:controller].title, @"Audio is taking longer…");
}

- (void)testNewGenerationCannotBeReportedAsOldRecovery {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.syntheticAgent.audioGeneration++;
    controller.syntheticAgent.audioCommandPending = NO;
    controller.syntheticAgent.hasAudioFailure = NO;
    [controller updateAudioRecoveryMenuItem];
    controller.now = 12; [timer fire];
    XCTAssertTrue(timer.invalidated);
    XCTAssertEqualObjects([self item:controller].title, @"Retry Audio");
    XCTAssertNil([self item:controller].view);
}

- (void)testDifferentAgentWithEqualCountersRejectsOlderTimer {
    ARPresentationController *controller = [self controller];
    ARPresentationAgent *oldAgent = controller.syntheticAgent;
    ARPresentationTimer *old = [self beginFailedOperation:controller];
    controller.syntheticAgent = [ARPresentationAgent new];
    controller.syntheticAgent.started = YES;
    controller.syntheticAgent.hasAudioFailure = YES;
    controller.syntheticAgent.audioCommandPending = YES;
    controller.syntheticAgent.audioGeneration = oldAgent.audioGeneration;
    controller.syntheticAgent.audioSelectionRevision = oldAgent.audioSelectionRevision;
    controller.now = 4; [controller updateAudioRecoveryMenuItem];
    controller.now = 10; [old fire];
    XCTAssertTrue(old.invalidated);
    XCTAssertEqualObjects([self item:controller].title, @"Trying audio…");
    XCTAssertTrue(controller.syntheticAgent.audioCommandPending);
}

- (void)testStoppingCancelsPresentationWithoutClearingPendingOrOpeningAlert {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    controller.syntheticAgent.started = NO;
    controller.syntheticAgent.audioGeneration++;
    [controller SIPUserAgentAudioStateDidChange:[NSNotification notificationWithName:AKSIPUserAgentAudioStateDidChangeNotification object:controller.syntheticAgent]];
    XCTAssertTrue(timer.invalidated);
    XCTAssertNil([self item:controller].view);
    XCTAssertFalse([self item:controller].enabled);
    XCTAssertTrue(controller.syntheticAgent.audioCommandPending);
    XCTAssertNil([controller valueForKey:@"audioFailureAlert"]);
    controller.now = 10; [timer fire];
    XCTAssertEqualObjects([self item:controller].title, @"Audio unavailable: Retry Audio");
}

- (void)testTerminationCancelsPresentationWithoutMutatingBackend {
    ARPresentationController *controller = [self controller];
    ARPresentationTimer *timer = [self beginFailedOperation:controller];
    [controller setValue:@YES forKey:@"terminating"];
    XCTAssertTrue(timer.invalidated);
    XCTAssertNil([self item:controller].view);
    XCTAssertFalse([self item:controller].enabled);
    XCTAssertTrue(controller.syntheticAgent.audioCommandPending);
    XCTAssertTrue(controller.syntheticAgent.hasAudioFailure);
    controller.now = 10; [timer fire];
    XCTAssertEqualObjects([self item:controller].title, @"Audio unavailable: Retry Audio");
}

- (void)testTerminationBeforeMenuInstallationStopsWatchdogWithoutQueryingAudio {
    ARPresentationController *controller = class_createInstance(ARPresentationController.class, 0);
    ARMinimalTerminationAgent *agent = [ARMinimalTerminationAgent new];
    controller.syntheticAgent = (id)agent;
    ARPresentationTimer *timer = [ARPresentationTimer new];
    timer.action = ^{};
    [controller setValue:timer forKey:@"audioRecoveryWatchdog"];
    [controller setValue:agent forKey:@"audioRecoveryAgent"];
    [controller setValue:@YES forKey:@"audioRecoveryOperationPending"];
    XCTAssertNoThrow([controller setValue:@YES forKey:@"terminating"]);
    XCTAssertTrue(timer.invalidated);
    XCTAssertNil([controller valueForKey:@"audioRecoveryWatchdog"]);
    XCTAssertNil([controller valueForKey:@"audioRecoveryAgent"]);
    XCTAssertFalse([[controller valueForKey:@"audioRecoveryOperationPending"] boolValue]);
    XCTAssertNil([self item:controller]);
    XCTAssertEqual(agent.queries, 0);
}

- (void)testDirectDuplicateRetryDoesNotInvokeBackendTwice {
    ARPresentationController *controller = [self controller];
    controller.syntheticAgent.hasAudioFailure = YES;
    [controller updateAudioRecoveryMenuItem];
    [controller retryAudio:nil];
    [controller retryAudio:nil];
    XCTAssertEqual(controller.syntheticAgent.retries, 1);
    XCTAssertEqualObjects([self item:controller].title, @"Trying audio…");
    XCTAssertFalse([controller validateMenuItem:[self item:controller]]);
    controller.syntheticAgent.audioCommandPending = NO;
    [controller updateAudioRecoveryMenuItem];
    XCTAssertEqual(controller.syntheticAgent.retries, 1, @"A failed result must never automatically retry");
    [controller retryAudio:nil];
    XCTAssertEqual(controller.syntheticAgent.retries, 2);
}

- (void)testForeignAudioNotificationCannotChangeCurrentPresentation {
    ARPresentationController *controller = [self controller];
    [self beginFailedOperation:controller];
    [controller SIPUserAgentAudioStateDidChange:[NSNotification notificationWithName:AKSIPUserAgentAudioStateDidChangeNotification object:[NSObject new]]];
    XCTAssertEqual(controller.timers.count, 1);
    XCTAssertEqualObjects([self item:controller].title, @"Trying audio…");
    XCTAssertNil([controller valueForKey:@"audioFailureAlert"]);
}

- (void)testCompactNativeProgressFitsBothAppearancesInTryingAndSlowStates {
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        ARPresentationController *controller = [self controller];
        ARPresentationTimer *timer = [self beginFailedOperation:controller];
        NSView *view = [self item:controller].view;
        view.appearance = [NSAppearance appearanceNamed:appearance];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:view.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.contentView = view;
        window.appearance = view.appearance;
        [window orderFront:nil];
        NSProgressIndicator *indicator = [controller valueForKey:@"audioRecoveryProgressIndicator"];
        NSTextField *label = [controller valueForKey:@"audioRecoveryProgressLabel"];
        for (NSNumber *elapsed in @[@0, @5]) {
            controller.now = elapsed.doubleValue;
            if (elapsed.doubleValue > 0) [timer fire];
            XCTAssertTrue(NSEqualSizes(view.bounds.size, NSMakeSize(300, 24)));
            XCTAssertTrue(NSContainsRect(view.bounds, indicator.frame));
            XCTAssertTrue(NSContainsRect(view.bounds, label.frame));
            XCTAssertEqualObjects(label.stringValue, [self item:controller].title);
            XCTAssertEqualObjects(label.accessibilityLabel, label.stringValue);
            XCTAssertEqualObjects(label.accessibilityHelp, [self item:controller].accessibilityHelp);
            NSSize text = [label.stringValue sizeWithAttributes:@{NSFontAttributeName:label.font}];
            XCTAssertLessThanOrEqual(text.width, label.bounds.size.width);
            XCTAssertLessThanOrEqual(text.height, label.bounds.size.height);
            [window displayIfNeeded];
            [view displayIfNeeded];
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            NSImage *cached = [[NSImage alloc] initWithData:bitmap.TIFFRepresentation];
            NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
            // Preserve the actual native control pixels. An opaque appearance
            // background makes composited AppKit text visible in exported PNGs.
            [image lockFocus];
            [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
                [NSColor.windowBackgroundColor setFill];
                NSRectFill(view.bounds);
                [cached drawInRect:view.bounds];
            }];
            [image unlockFocus];
            XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
            attachment.name = [NSString stringWithFormat:@"audio-recovery-%@-%@", elapsed.doubleValue > 0 ? @"slow" : @"trying",
                               [appearance isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light"];
            attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
            [self addAttachment:attachment];
        }
        [window orderOut:nil];
    }
}
@end
