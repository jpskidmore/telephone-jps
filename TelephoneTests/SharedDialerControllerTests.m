#import <XCTest/XCTest.h>
#import "SharedDialerController.h"
#import "AccountController.h"
#import "AccountControllers.h"
#import "AKSIPURI.h"
#import "ActiveAccountViewController.h"
#import "Telephone-Swift.h"
#import <objc/runtime.h>

@interface SharedDialerController (NativeRegression)
- (void)toggleHistory:(id)sender;
- (void)rebuildAvailability;
- (NSMenu *)moreActionsMenu;
- (void)showGuidedRoutes:(id)sender;
- (void)refreshPendingCalls;
- (void)rebuildPendingPopover;
- (void)showPendingCalls:(id)sender;
- (void)cancelWaitingCall:(id)sender;
- (void)cancelPendingCalls:(id)sender;
@end

@interface JPSSharedGuidedRoutesPreferences : NSObject
@property(nonatomic) NSUInteger shows;
@property(nonatomic) NSUInteger dialPlanShows;
- (void)showWindowCentered;
- (void)showDialPlan;
@end
@implementation JPSSharedGuidedRoutesPreferences
- (void)showWindowCentered { self.shows++; }
- (void)showDialPlan { self.dialPlanShows++; }
@end

@interface JPSSharedGuidedRoutesDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic) NSUInteger deliveries;
@property(nonatomic) id lastSender;
@property(nonatomic) JPSSharedGuidedRoutesPreferences *preferences;
- (void)showGuidedRoutes:(id)sender;
@end
@implementation JPSSharedGuidedRoutesDelegate
- (void)showGuidedRoutes:(id)sender {
    self.deliveries++;
    self.lastSender = sender;
    [self.preferences showWindowCentered];
    [self.preferences showDialPlan];
}
@end

@interface JPSSharedGuidedRoutesDispatchBoundary : SharedDialerController
@property(nonatomic) NSUInteger actionEntries;
@property(nonatomic) BOOL interceptedLoop;
@end
@implementation JPSSharedGuidedRoutesDispatchBoundary
- (void)showGuidedRoutes:(id)sender {
    self.actionEntries++;
    if (self.actionEntries > 1) { self.interceptedLoop = YES; return; }
    [super showGuidedRoutes:sender];
}
@end

// Observe the target boundary while preserving AppKit's actual lookup and
// dispatch. The host need not acquire desktop focus to detect a nil-target
// regression; the bounded controller also prevents a stack overflow if it does.
static IMP JPSOriginalApplicationSendAction;
static NSMutableArray *JPSGuidedRouteDispatchTargets;
static BOOL JPSObserveApplicationSendAction(id application, SEL command, SEL action, id target, id sender) {
    if (action == @selector(showGuidedRoutes:))
        [JPSGuidedRouteDispatchTargets addObject:target ?: NSNull.null];
    return ((BOOL (*)(id, SEL, SEL, id, id))JPSOriginalApplicationSendAction)(application,command,action,target,sender);
}

// Only menu/display data is supplied; no native SIP account, defaults or
// production AccountController initializer is used by the status fixture.
@interface JPSSharedDiallerAccountInfo : NSObject
@property(nonatomic, copy) NSString *uuid;
@property(nonatomic, copy) NSString *domain;
@end
@implementation JPSSharedDiallerAccountInfo @end

@interface JPSSharedDiallerAccountFixture : NSObject
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, getter=isAccountRegistered) BOOL accountRegistered;
@property(nonatomic, copy) NSString *accountDescription;
@property(nonatomic, copy) NSString *routingAvailability;
@property(nonatomic) JPSSharedDiallerAccountInfo *account;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *pendingRoutedCallSummaries;
@property(nonatomic, readonly) NSString *accountUUID;
@property(nonatomic, readonly) BOOL hasPendingRoutedCalls;
@property(nonatomic) NSUInteger individualCancellations;
@property(nonatomic) NSUInteger bulkCancellations;
- (BOOL)cancelPendingRoutedCallWithIdentifier:(NSString *)identifier;
- (void)cancelPendingRoutedCalls;
@end
@implementation JPSSharedDiallerAccountFixture
- (instancetype)init {
    if ((self = [super init])) _pendingRoutedCallSummaries = @[];
    return self;
}
- (NSString *)accountUUID { return self.account.uuid; }
- (BOOL)hasPendingRoutedCalls { return self.pendingRoutedCallSummaries.count > 0; }
- (void)setPendingRoutedCallSummaries:(NSArray<NSDictionary<NSString *, NSString *> *> *)summaries {
    _pendingRoutedCallSummaries = [[NSArray alloc] initWithArray:summaries copyItems:YES];
    [NSNotificationCenter.defaultCenter postNotificationName:JPSPendingRoutedCallsDidChangeNotification object:nil];
}
- (BOOL)cancelPendingRoutedCallWithIdentifier:(NSString *)identifier {
    NSMutableArray *remaining = [self.pendingRoutedCallSummaries mutableCopy];
    NSUInteger index = [remaining indexOfObjectPassingTest:^BOOL(NSDictionary *summary, NSUInteger index, BOOL *stop) {
        return [summary[@"id"] isEqualToString:identifier];
    }];
    if (index == NSNotFound) return NO;
    [remaining removeObjectAtIndex:index];
    self.individualCancellations++;
    self.pendingRoutedCallSummaries = remaining;
    return YES;
}
- (void)cancelPendingRoutedCalls {
    if (!self.hasPendingRoutedCalls) return;
    self.bulkCancellations++;
    self.pendingRoutedCallSummaries = @[];
}
@end

@interface JPSSharedDiallerAccountsFixture : NSObject
@property(nonatomic) NSArray<JPSSharedDiallerAccountFixture *> *all;
@end
@implementation JPSSharedDiallerAccountsFixture
- (NSArray *)enabled {
    NSMutableArray *enabled = [NSMutableArray array];
    for (JPSSharedDiallerAccountFixture *account in self.all) if (account.isEnabled) [enabled addObject:account];
    return enabled;
}
@end
@interface SharedDialerControllerTests : XCTestCase
@end
@implementation SharedDialerControllerTests
- (NSArray<NSView *> *)descendants:(NSView *)view {
    NSMutableArray *result = [NSMutableArray arrayWithObject:view];
    for (NSView *child in view.subviews) [result addObjectsFromArray:[self descendants:child]];
    return result;
}
- (JPSSharedDiallerAccountFixture *)accountWithUUID:(NSString *)uuid name:(NSString *)name availability:(NSString *)availability {
    JPSSharedDiallerAccountFixture *account = [JPSSharedDiallerAccountFixture new];
    account.enabled = YES;
    account.accountRegistered = [availability isEqualToString:@"online"];
    account.accountDescription = name;
    account.routingAvailability = availability;
    account.account = [JPSSharedDiallerAccountInfo new];
    account.account.uuid = uuid;
    account.account.domain = @"example.invalid";
    return account;
}
- (NSArray<DialPlanAccount *> *)routeSnapshots:(JPSSharedDiallerAccountsFixture *)accounts {
    NSMutableArray *snapshots = [NSMutableArray array];
    for (JPSSharedDiallerAccountFixture *account in accounts.all) {
        [snapshots addObject:[[DialPlanAccount alloc] initWithUUID:account.account.uuid name:account.accountDescription
                                                         enabled:account.isEnabled availability:account.routingAvailability]];
    }
    return snapshots;
}
- (void)assertNoPermanentRouteStatusInController:(SharedDialerController *)controller {
    for (NSView *view in [self descendants:controller.window.contentView]) {
        XCTAssertNotEqualObjects(view.identifier,@"CompactOutgoingRouteStatus");
        if ([view isKindOfClass:NSTextField.class] && ![view isKindOfClass:NSTokenField.class]) {
            NSString *text = ((NSTextField *)view).stringValue;
            XCTAssertFalse([text isEqualToString:@"Enter a number"] || [text hasPrefix:@"Ready · "] ||
                           [text hasPrefix:@"Offline · "] || [text hasPrefix:@"Waiting · "],
                           @"Route details must remain in Call help, without a permanent status row.");
        }
    }
}
- (NSDictionary<NSString *, NSString *> *)pendingSummaryForAccount:(JPSSharedDiallerAccountFixture *)account destination:(NSString *)destination {
    return @{@"id":NSUUID.UUID.UUIDString, @"accountUUID":account.accountUUID,
             @"providerName":account.accountDescription, @"destination":destination};
}
- (void)writePendingSnapshotIfRequested:(NSView *)view name:(NSString *)name {
    NSString *directory = NSProcessInfo.processInfo.environment[@"JPS_PENDING_CALL_CAPTURE_DIR"];
    if (directory.length == 0) return;
    NSError *error = nil;
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    XCTAssertTrue([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                  writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]);
}
- (void)testWaitingCountAndNativePopoverRetainTwoProvidersAndCancelOnlySelectedUUID {
    JPSSharedDiallerAccountFixture *first = [self accountWithUUID:@"first" name:@"Synthetic first provider" availability:@"registering"];
    JPSSharedDiallerAccountFixture *second = [self accountWithUUID:@"second" name:@"Synthetic second provider" availability:@"registering"];
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new]; accounts.all = @[first,second];
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        XCTAssertTrue(dialler.pendingCallsButton.hidden);
        NSDictionary *firstSummary = [self pendingSummaryForAccount:first destination:@"+447700900123"];
        NSDictionary *secondSummary = [self pendingSummaryForAccount:second destination:@"+442079460958"];
        first.pendingRoutedCallSummaries = @[firstSummary];
        second.pendingRoutedCallSummaries = @[secondSummary];
        XCTAssertFalse(dialler.pendingCallsButton.hidden);
        XCTAssertEqualObjects(dialler.pendingCallsButton.title,@"Waiting 2");
        XCTAssertEqual(dialler.pendingCallsButton.target,controller);
        XCTAssertEqual(dialler.pendingCallsButton.action,@selector(showPendingCalls:));
        XCTAssertTrue([dialler.pendingCallsButton.accessibilityLabel containsString:@"2"]);
        XCTAssertEqualObjects([controller valueForKey:@"pendingRequests"],(@[firstSummary,secondSummary]));
        [controller rebuildPendingPopover];
        NSPopover *popover = [controller valueForKey:@"pendingPopover"];
        NSArray<NSButton *> *buttons = [controller valueForKey:@"pendingCancelButtons"];
        XCTAssertNotNil(popover);
        XCTAssertEqual(popover.behavior,NSPopoverBehaviorTransient);
        XCTAssertEqual(buttons.count,2u);
        NSMutableArray<NSString *> *content = [NSMutableArray array];
        for (NSView *view in [self descendants:popover.contentViewController.view]) {
            if ([view isKindOfClass:NSTextField.class]) [content addObject:((NSTextField *)view).stringValue];
        }
        NSString *text = [content componentsJoinedByString:@"\n"];
        for (NSDictionary *summary in @[firstSummary,secondSummary]) {
            XCTAssertTrue([text containsString:summary[@"providerName"]]);
            XCTAssertTrue([text containsString:summary[@"destination"]]);
        }
        for (NSUInteger index = 0; index < buttons.count; index++) {
            NSButton *button = buttons[index];
            XCTAssertEqualObjects(button.cell.representedObject,(@[firstSummary,secondSummary])[index]);
            XCTAssertEqualObjects(button.title,@"Cancel");
            XCTAssertEqual(button.target,controller);
            XCTAssertEqual(button.action,@selector(cancelWaitingCall:));
            id accessible = NSAccessibilityUnignoredDescendant(button);
            NSString *role = [accessible respondsToSelector:@selector(accessibilityRole)] ? [accessible accessibilityRole] :
                [accessible accessibilityAttributeValue:NSAccessibilityRoleAttribute];
            XCTAssertEqualObjects(role,NSAccessibilityButtonRole);
            XCTAssertGreaterThan(button.accessibilityLabel.length,0u);
        }
        [controller cancelWaitingCall:buttons.firstObject];
        XCTAssertEqual(first.individualCancellations,1u);
        XCTAssertEqual(second.individualCancellations,0u);
        XCTAssertEqual(first.pendingRoutedCallSummaries.count,0u);
        XCTAssertEqualObjects(second.pendingRoutedCallSummaries,(@[secondSummary]));
        XCTAssertEqualObjects(dialler.pendingCallsButton.title,@"Waiting 1");
        [controller cancelWaitingCall:buttons.firstObject];
        XCTAssertEqual(first.individualCancellations,1u);
        XCTAssertEqualObjects([controller valueForKey:@"pendingRequests"],(@[secondSummary]));
    } @finally {
        [[controller valueForKey:@"pendingPopover"] close];
        [controller.window orderOut:nil];
    }
}
- (void)testWaitingRowsTrackAccountRemovalAndBulkCancellationWithoutUsingStaleButtons {
    JPSSharedDiallerAccountFixture *first = [self accountWithUUID:@"first" name:@"Synthetic first" availability:@"registering"];
    JPSSharedDiallerAccountFixture *second = [self accountWithUUID:@"second" name:@"Synthetic second" availability:@"registering"];
    first.pendingRoutedCallSummaries = @[[self pendingSummaryForAccount:first destination:@"+447700900123"]];
    second.pendingRoutedCallSummaries = @[[self pendingSummaryForAccount:second destination:@"+442079460958"]];
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new]; accounts.all = @[first,second];
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        [controller rebuildPendingPopover];
        NSArray<NSButton *> *buttons = [controller valueForKey:@"pendingCancelButtons"];
        NSButton *removedAccountButton = buttons.lastObject;
        accounts.all = @[first];
        [controller refreshAccounts];
        XCTAssertEqualObjects(dialler.pendingCallsButton.title,@"Waiting 1");
        [controller cancelWaitingCall:removedAccountButton];
        XCTAssertEqual(first.individualCancellations,0u);
        XCTAssertEqual(second.individualCancellations,0u);
        XCTAssertEqual(second.pendingRoutedCallSummaries.count,1u);
        NSMenuItem *bulk = nil;
        for (NSMenuItem *item in [controller moreActionsMenu].itemArray) {
            if (item.action == @selector(cancelPendingCalls:)) { bulk = item; break; }
        }
        XCTAssertNotNil(bulk);
        [controller cancelPendingCalls:bulk];
        XCTAssertEqual(first.bulkCancellations,1u);
        XCTAssertEqual(second.bulkCancellations,0u);
        XCTAssertTrue(dialler.pendingCallsButton.hidden);
        XCTAssertFalse(dialler.pendingCallsButton.enabled);
        XCTAssertEqual([[controller valueForKey:@"pendingRequests"] count],0u);
        XCTAssertNotEqual(dialler.callDestinationField.nextKeyView,dialler.pendingCallsButton);
    } @finally {
        [[controller valueForKey:@"pendingPopover"] close];
        [controller.window orderOut:nil];
    }
}
- (void)testWaitingControlKeepsCentredGeometryHitRegionsAndKeyboardChainInLightAndDark {
    JPSSharedDiallerAccountFixture *account = [self accountWithUUID:@"synthetic" name:@"A long synthetic waiting provider" availability:@"registering"];
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new]; accounts.all = @[account];
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        dialler.callDestinationField.delegate = nil;
        dialler.callDestinationField.stringValue = @"07700900123";
        NSButton *waiting = dialler.pendingCallsButton;
        NSButton *call = [dialler valueForKey:@"dialButton"];
        NSButton *history = [dialler valueForKey:@"historyButton"];
        NSPopUpButton *availability = [controller valueForKey:@"availability"];
        XCTAssertEqualObjects(waiting.identifier,@"CompactPendingCallsButton");
        XCTAssertFalse(waiting.refusesFirstResponder);
        XCTAssertTrue([waiting.accessibilityHelp containsString:@"cancel"]);
        [self assertNoPermanentRouteStatusInController:controller];
        for (NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
            controller.window.appearance = [NSAppearance appearanceNamed:appearance];
            [controller.window.contentView layoutSubtreeIfNeeded];
            NSRect originalFieldFrame = [dialler.callDestinationField convertRect:dialler.callDestinationField.bounds toView:controller.window.contentView];
            [controller.window makeFirstResponder:dialler.callDestinationField];
            NSResponder *editor = controller.window.firstResponder;
            for (NSNumber *count in @[@0,@1,@3,@0]) {
                NSMutableArray *summaries = [NSMutableArray array];
                for (NSUInteger index = 0; index < count.unsignedIntegerValue; index++)
                    [summaries addObject:[self pendingSummaryForAccount:account destination:@"+447700900123"]];
                account.pendingRoutedCallSummaries = summaries;
                [controller.window.contentView layoutSubtreeIfNeeded];
                XCTAssertEqual(controller.window.firstResponder,editor, @"A count refresh must not take focus from the number editor.");
                XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.width,368,0.5);
                XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.height,104,0.5);
                NSRect fieldFrame = [dialler.callDestinationField convertRect:dialler.callDestinationField.bounds toView:controller.window.contentView];
                XCTAssertTrue(NSEqualRects(fieldFrame,originalFieldFrame), @"Waiting calls must not displace the centred field.");
                XCTAssertGreaterThanOrEqual(fieldFrame.size.width,160);
                for (NSView *control in @[availability,call,history,history.nextKeyView]) {
                    NSRect controlFrame = [control convertRect:control.bounds toView:controller.window.contentView];
                    XCTAssertEqualWithAccuracy(control.bounds.size.width,44,0.5);
                    XCTAssertEqualWithAccuracy(control.bounds.size.height,44,0.5);
                    XCTAssertEqualWithAccuracy(NSMidY(fieldFrame),NSMidY(controlFrame),0.5, @"The number field must share the 3.5 icon centre line.");
                    if (count.unsignedIntegerValue) {
                        NSRect waitingFrame = [waiting convertRect:waiting.bounds toView:controller.window.contentView];
                        XCTAssertFalse(NSIntersectsRect(waitingFrame,controlFrame), @"Waiting must preserve each icon's full hit region.");
                    }
                }
                XCTAssertEqual(waiting.hidden,count.unsignedIntegerValue == 0);
                XCTAssertEqual(dialler.callDestinationField.nextKeyView,count.unsignedIntegerValue ? waiting : call);
                XCTAssertEqual(waiting.nextKeyView,call);
                XCTAssertEqual(call.nextKeyView,history);
                if (count.unsignedIntegerValue) {
                    NSRect waitingFrame = [waiting convertRect:waiting.bounds toView:controller.window.contentView];
                    NSRect localFrame = [waiting convertRect:waiting.bounds toView:dialler.view];
                    XCTAssertTrue(NSContainsRect(dialler.view.bounds,localFrame));
                    XCTAssertFalse(NSIntersectsRect(waitingFrame,fieldFrame));
                    XCTAssertGreaterThanOrEqual(waitingFrame.size.width,54);
                    for (NSNumber *y in @[@(NSMinY(localFrame) + 1), @(NSMidY(localFrame)), @(NSMaxY(localFrame) - 1)]) {
                        NSPoint hitPoint = [dialler.view convertPoint:NSMakePoint(NSMidX(localFrame),y.doubleValue) toView:dialler.view.superview];
                        XCTAssertEqual([dialler.view hitTest:hitPoint],waiting, @"The whole waiting link must be reachable, including its edge outside the glass bar.");
                    }
                    NSString *expectedTitle = [NSString stringWithFormat:@"Waiting %@",count];
                    XCTAssertEqualObjects(waiting.title,expectedTitle);
                }
                NSString *mode = [appearance isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
                [self writePendingSnapshotIfRequested:controller.window.contentView name:[NSString stringWithFormat:@"waiting-%@-%@.png",count,mode]];
                if (count.unsignedIntegerValue == 1) {
                    [controller rebuildPendingPopover];
                    NSPopover *popover = [controller valueForKey:@"pendingPopover"];
                    popover.contentViewController.view.appearance = [NSAppearance appearanceNamed:appearance];
                    [self writePendingSnapshotIfRequested:popover.contentViewController.view name:[NSString stringWithFormat:@"waiting-popover-%@.png",mode]];
                    [controller toggleHistory:nil];
                    [controller.window.contentView layoutSubtreeIfNeeded];
                    XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.width,368,0.5);
                    XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.height,268,0.5);
                    XCTAssertEqual(dialler.callDestinationField.nextKeyView,waiting);
                    [controller toggleHistory:nil];
                }
            }
        }
    } @finally {
        [[controller valueForKey:@"pendingPopover"] close];
        [controller.window orderOut:nil];
    }
}
- (void)testShownWaitingPopoverKeepsCancellationFocusAndRestoresDestinationAfterFinalRemoval {
    XCTAssertTrue([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"uk.jpsit.telephone.tests."], @"Popover focus regression requires the isolated synthetic host.");
    if (![NSBundle.mainBundle.bundleIdentifier hasPrefix:@"uk.jpsit.telephone.tests."]) return;
    JPSSharedDiallerAccountFixture *first = [self accountWithUUID:@"first" name:@"Synthetic first" availability:@"registering"];
    JPSSharedDiallerAccountFixture *second = [self accountWithUUID:@"second" name:@"Synthetic second" availability:@"registering"];
    first.pendingRoutedCallSummaries = @[[self pendingSummaryForAccount:first destination:@"+447700900123"]];
    NSMutableArray *secondSummaries = [NSMutableArray array];
    for (NSUInteger index = 0; index < 7; index++)
        [secondSummaries addObject:[self pendingSummaryForAccount:second destination:@"+442079460958"]];
    second.pendingRoutedCallSummaries = secondSummaries;
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new]; accounts.all = @[first,second];
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        dialler.callDestinationField.delegate = nil;
        [controller.window setFrameOrigin:NSMakePoint(-10000,-10000)];
        [controller.window orderFront:nil];
        [controller.window.contentView layoutSubtreeIfNeeded];
        [controller showPendingCalls:dialler.pendingCallsButton];
        NSPopover *popover = [controller valueForKey:@"pendingPopover"];
        NSArray<NSButton *> *buttons = [controller valueForKey:@"pendingCancelButtons"];
        XCTAssertTrue(popover.isShown);
        XCTAssertEqual(buttons.count,8u);
        XCTAssertEqual(popover.contentViewController.view.window.firstResponder,buttons.firstObject);
        XCTAssertEqual(buttons.firstObject.nextKeyView,buttons[1]);
        XCTAssertEqual(buttons.lastObject.nextKeyView,buttons.firstObject);
        [self writePendingSnapshotIfRequested:popover.contentViewController.view name:@"waiting-popover-shown.png"];

        [controller cancelWaitingCall:buttons.firstObject];
        XCTAssertTrue(popover.isShown);
        NSArray<NSButton *> *remaining = [controller valueForKey:@"pendingCancelButtons"];
        XCTAssertEqual(remaining.count,7u);
        XCTAssertEqualObjects(((NSDictionary *)remaining.firstObject.cell.representedObject)[@"accountUUID"],@"second");
        XCTAssertEqual(popover.contentViewController.view.window.firstResponder,remaining.firstObject);
        XCTAssertEqual(first.individualCancellations,1u);
        XCTAssertEqual(second.individualCancellations,0u);
        NSButton *lower = remaining[5];
        NSString *nextIdentifier = ((NSDictionary *)remaining[6].cell.representedObject)[@"id"];
        [lower.window makeFirstResponder:lower];
        [lower scrollRectToVisible:lower.bounds];
        [controller cancelWaitingCall:lower];
        XCTAssertEqual(second.individualCancellations,1u);
        XCTAssertTrue(popover.isShown);
        NSArray<NSButton *> *afterLowerCancellation = [controller valueForKey:@"pendingCancelButtons"];
        NSButton *focused = (id)popover.contentViewController.view.window.firstResponder;
        XCTAssertEqual(focused,afterLowerCancellation[5]);
        XCTAssertEqualObjects(((NSDictionary *)focused.cell.representedObject)[@"id"],nextIdentifier);
        NSScrollView *scroll = focused.enclosingScrollView;
        XCTAssertNotNil(scroll);
        NSRect focusedFrame = [focused convertRect:focused.bounds toView:scroll.documentView];
        XCTAssertTrue(NSIntersectsRect(focusedFrame,scroll.documentVisibleRect));
        [controller cancelPendingCalls:nil];
        XCTAssertFalse(popover.isShown);
        XCTAssertTrue(dialler.pendingCallsButton.hidden);
        NSResponder *restored = controller.window.firstResponder;
        XCTAssertTrue(restored == dialler.callDestinationField ||
                      (dialler.callDestinationField.currentEditor != nil && restored == dialler.callDestinationField.currentEditor));
        first.pendingRoutedCallSummaries = @[[self pendingSummaryForAccount:first destination:@"+447700900123"]];
        [controller showPendingCalls:dialler.pendingCallsButton];
        NSButton *final = [[controller valueForKey:@"pendingCancelButtons"] firstObject];
        [controller cancelWaitingCall:final];
        XCTAssertFalse(popover.isShown);
        XCTAssertTrue(dialler.pendingCallsButton.hidden);
        restored = controller.window.firstResponder;
        XCTAssertTrue(restored == dialler.callDestinationField ||
                      (dialler.callDestinationField.currentEditor != nil && restored == dialler.callDestinationField.currentEditor));
    } @finally {
        [[controller valueForKey:@"pendingPopover"] close];
        [controller.window orderOut:nil];
    }
}
- (void)writeRouteSnapshotIfRequested:(NSWindow *)window name:(NSString *)name {
    NSString *directory = NSProcessInfo.processInfo.environment[@"JPS_ROUTE_PREVIEW_CAPTURE_DIR"];
    if (directory.length == 0) return;
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    [window.contentView layoutSubtreeIfNeeded];
    NSBitmapImageRep *image = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
    [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:image];
    XCTAssertTrue([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                  writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]);
}
- (void)testCallHelpKeepsSelectedProviderTruthSeparateFromAggregateOnline {
    NSString *suite = [@"jps.tests.route-readiness." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    DialPlanStore *store = [[DialPlanStore alloc] initWithDefaults:defaults];
    JPSSharedDiallerAccountFixture *aa = [self accountWithUUID:@"aa" name:@"AA" availability:@"online"];
    JPSSharedDiallerAccountFixture *local = [self accountWithUUID:@"local" name:@"Localphone" availability:@"offline"];
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new];
    accounts.all = @[aa,local];
    NSMutableDictionary *configuration = [store.configuration mutableCopy];
    configuration[@"defaultAccountUUID"] = @"aa";
    configuration[@"categoryTargets"] = @{@"mobile":@"local"};
    NSError *error = nil;
    XCTAssertTrue([store updateConfiguration:configuration error:&error], @"%@", error);
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil
        routeResolver:^DialPlanRoute *(NSString *input, NSArray<DialPlanAccount *> *snapshot) { return [store resolveDestination:input accounts:snapshot]; }];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        // Raw input exercises the route-preview path without Contacts tokenisation.
        dialler.callDestinationField.delegate = nil;
        dialler.callDestinationField.stringValue = @"07700900123";
        NSButton *call = [dialler valueForKey:@"dialButton"];
        [self assertNoPermanentRouteStatusInController:controller];
        NSPopUpButton *availability = [controller valueForKey:@"availability"];
        XCTAssertTrue([call.toolTip containsString:@"Localphone is Offline."]);
        XCTAssertEqualObjects(availability.accessibilityValue,@"Online");
        XCTAssertEqualObjects(call.accessibilityLabel,@"Call");
        XCTAssertEqualObjects(call.accessibilityHelp,call.toolTip);
        XCTAssertEqualObjects(call.cell.accessibilityHelp,call.toolTip);
        XCTAssertTrue([call.toolTip containsString:@"+447700900123"]);
        XCTAssertTrue([call.accessibilityHelp containsString:@"no other connection will be used"]);
        DialPlanRoute *route = [store resolveDestination:@"07700900123" accounts:[self routeSnapshots:accounts]];
        XCTAssertEqualObjects(route.accountUUID,@"local");
        XCTAssertFalse(route.canDial);

        local.routingAvailability = @"registering";
        [NSNotificationCenter.defaultCenter postNotificationName:@"JPSAccountRoutingStateDidChangeNotification" object:local];
        XCTAssertTrue([call.toolTip containsString:@"Wait for Localphone to register"]);
        local.accountRegistered = YES; local.routingAvailability = @"online";
        [NSNotificationCenter.defaultCenter postNotificationName:@"JPSAccountRoutingStateDidChangeNotification" object:local];
        XCTAssertTrue([call.toolTip containsString:@"Use Localphone."]);
        XCTAssertEqualObjects(call.accessibilityHelp,call.toolTip);
        route = [store resolveDestination:@"07700900123" accounts:[self routeSnapshots:accounts]];
        XCTAssertEqualObjects(route.accountUUID,@"local");
        XCTAssertTrue(route.canDial);
        XCTAssertEqualObjects(route.destination.destination,@"+447700900123");
        local.enabled = NO;
        [controller refreshAccounts];
        XCTAssertTrue([call.toolTip containsString:@"Localphone is disabled."]);
        XCTAssertEqualObjects(call.accessibilityHelp,call.toolTip);
        XCTAssertEqualObjects(availability.accessibilityValue,@"Online");
    } @finally {
        [controller.window orderOut:nil];
        [defaults removePersistentDomainForName:suite];
    }
}
- (void)testCompactPreviewUsesOneFrozenSnapshotAndExposesLiteralServiceExplanation {
    NSString *suite = [@"jps.tests.route-presentation." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    DialPlanStore *store = [[DialPlanStore alloc] initWithDefaults:defaults];
    JPSSharedDiallerAccountFixture *selected = [self accountWithUUID:@"selected" name:@"Original connection" availability:@"online"];
    JPSSharedDiallerAccountFixture *other = [self accountWithUUID:@"other" name:@"Other connection" availability:@"online"];
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new]; accounts.all = @[selected,other];
    NSMutableDictionary *configuration = [store.configuration mutableCopy]; configuration[@"defaultAccountUUID"] = @"selected";
    NSError *error = nil;
    XCTAssertTrue([store updateConfiguration:configuration error:&error], @"%@", error);
    __block BOOL changeAfterResolution = YES;
    __block NSUInteger snapshotsResolved = 0;
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil
        routeResolver:^DialPlanRoute *(NSString *input, NSArray<DialPlanAccount *> *snapshot) {
            snapshotsResolved++;
            DialPlanRoute *route = [store resolveDestination:input accounts:snapshot];
            if (changeAfterResolution) {
                changeAfterResolution = NO;
                selected.accountDescription = @"Renamed connection"; selected.routingAvailability = @"offline";
            }
            return route;
        }];
    __block NSUInteger admittedRefreshes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:DialPlanStore.accountsChangeNotificationName object:nil queue:nil usingBlock:^(NSNotification *notification) {
        XCTAssertTrue(NSThread.isMainThread); XCTAssertNil(notification.object); XCTAssertNil(notification.userInfo);
        admittedRefreshes++;
    }];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        dialler.callDestinationField.delegate = nil;
        dialler.callDestinationField.stringValue = @"07700900123";
        NSButton *call = [dialler valueForKey:@"dialButton"];
        XCTAssertEqual(snapshotsResolved,1u);
        XCTAssertTrue([call.toolTip containsString:@"Use Original connection."]);
        [controller refreshAccounts];
        XCTAssertEqual(admittedRefreshes,1u);
        XCTAssertEqual(snapshotsResolved,2u);
        XCTAssertTrue([call.toolTip containsString:@"no other connection will be used"]);
        selected.routingAvailability = @"online";
        dialler.callDestinationField.stringValue = @"123R45P67";
        XCTAssertTrue([call.toolTip containsString:@"123R45P67"]);
        XCTAssertTrue([call.toolTip containsString:@"Pause/recall syntax is preserved"]);
        XCTAssertTrue([call.accessibilityHelp containsString:@"not converted into post-connect DTMF"]);
        XCTAssertEqualObjects(call.accessibilityHelp,call.toolTip);
        XCTAssertEqualObjects(call.cell.accessibilityHelp,call.toolTip);
        XCTAssertTrue([call.toolTip containsString:@"Use Renamed connection."]);
        XCTAssertEqualObjects(store.configuration[@"defaultAccountUUID"],@"selected");
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [controller.window orderOut:nil]; [defaults removePersistentDomainForName:suite];
    }
}
- (void)testDetachedPreviewHandlerDoesNotResolveAfterItsWindowControllerIsReleased {
    NSString *suite = [@"jps.tests.detached-preview." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    DialPlanStore *store = [[DialPlanStore alloc] initWithDefaults:defaults];
    __block NSUInteger resolutions = 0;
    __weak SharedDialerController *released;
    NSString *(^preview)(AKSIPURI *, NSString *);
    @autoreleasepool {
        SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:[AccountControllers new] historyFactory:nil
            routeResolver:^DialPlanRoute *(NSString *input, NSArray<DialPlanAccount *> *snapshot) {
                resolutions++;
                XCTFail(@"A detached preview must not enter resolution or Swift presentation.");
                return [store resolveDestination:input accounts:snapshot];
            }];
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        preview = [dialler.callRoutePreviewHandler copy];
        released = controller;
        [controller.window orderOut:nil];
    }
    XCTAssertNil(released);
    XCTAssertEqualObjects(preview(nil,@"07700900123"),@"Call");
    XCTAssertEqual(resolutions,0u);
    [defaults removePersistentDomainForName:suite];
}
- (void)testCallHelpFollowsDestinationSavedPlanAccountRenameAndRemovalWithoutStatusRow {
    NSString *suite = [@"jps.tests.route-updates." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    DialPlanStore *store = [[DialPlanStore alloc] initWithDefaults:defaults];
    JPSSharedDiallerAccountFixture *aa = [self accountWithUUID:@"aa" name:@"AA" availability:@"online"];
    JPSSharedDiallerAccountFixture *local = [self accountWithUUID:@"local" name:@"Localphone" availability:@"online"];
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new]; accounts.all = @[aa,local];
    NSMutableDictionary *configuration = [store.configuration mutableCopy]; configuration[@"defaultAccountUUID"] = @"aa";
    NSError *error = nil;
    XCTAssertTrue([store updateConfiguration:configuration error:&error], @"%@", error);
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil
        routeResolver:^DialPlanRoute *(NSString *input, NSArray<DialPlanAccount *> *snapshot) { return [store resolveDestination:input accounts:snapshot]; }];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        // Raw input exercises the route-preview path without Contacts tokenisation.
        dialler.callDestinationField.delegate = nil;
        NSButton *call = [dialler valueForKey:@"dialButton"];
        XCTAssertEqualObjects(call.toolTip,@"Call");
        [self assertNoPermanentRouteStatusInController:controller];
        dialler.callDestinationField.stringValue = @"02079460958";
        XCTAssertTrue([call.toolTip containsString:@"Use AA."]);
        NSString *savedPreview = call.toolTip;
        configuration[@"defaultAccountUUID"] = @"local";
        XCTAssertEqualObjects(call.toolTip,savedPreview, @"An unsaved draft must not change Call help.");
        XCTAssertTrue([store updateConfiguration:configuration error:&error], @"%@", error);
        XCTAssertTrue([call.toolTip containsString:@"Use Localphone."]);
        local.accountDescription = @"A deliberately long synthetic connection name for Call's outgoing connection help";
        [controller refreshAccounts];
        NSString *fullPreview = call.toolTip;
        XCTAssertTrue([fullPreview containsString:local.accountDescription]);
        XCTAssertEqualObjects(call.accessibilityHelp,fullPreview);
        XCTAssertEqualObjects(call.cell.accessibilityHelp,fullPreview);
        id accessibleCall = NSAccessibilityUnignoredDescendant(call);
        NSString *accessibleHelp = [accessibleCall respondsToSelector:@selector(accessibilityHelp)] ? [accessibleCall accessibilityHelp] :
            [accessibleCall accessibilityAttributeValue:NSAccessibilityHelpAttribute];
        XCTAssertEqualObjects(accessibleHelp,fullPreview);
        [controller.window.contentView layoutSubtreeIfNeeded];
        CGFloat narrowWidth = dialler.callDestinationField.bounds.size.width;
        [controller.window setContentSize:NSMakeSize(500,104)];
        [controller.window.contentView layoutSubtreeIfNeeded];
        XCTAssertGreaterThan(dialler.callDestinationField.bounds.size.width,narrowWidth);
        XCTAssertEqualObjects(call.accessibilityHelp,fullPreview);
        [controller.window setContentSize:NSMakeSize(368,104)];
        for (NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
            controller.window.appearance = [NSAppearance appearanceNamed:appearance];
            [controller.window.contentView layoutSubtreeIfNeeded];
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.width,368,0.5);
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.height,104,0.5);
            NSRect callFrame = [call convertRect:call.bounds toView:controller.window.contentView];
            NSRect fieldFrame = [dialler.callDestinationField convertRect:dialler.callDestinationField.bounds toView:controller.window.contentView];
            XCTAssertTrue(NSContainsRect(controller.window.contentView.bounds,fieldFrame));
            XCTAssertEqualWithAccuracy(NSMidY(fieldFrame),NSMidY(callFrame),0.5);
            XCTAssertEqualObjects(call.toolTip,fullPreview);
            [self assertNoPermanentRouteStatusInController:controller];
            NSString *name = [appearance isEqualToString:NSAppearanceNameAqua] ? @"centred-field-light.png" : @"centred-field-dark.png";
            [self writeRouteSnapshotIfRequested:controller.window name:name];
            [controller toggleHistory:nil];
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.height,268,0.5);
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.width,368,0.5);
            [controller toggleHistory:nil];
        }
        accounts.all = @[aa];
        [controller refreshAccounts];
        XCTAssertTrue([call.toolTip containsString:@"The selected connection was removed."]);
        dialler.callDestinationField.stringValue = @"07700900123";
        configuration[@"categoryTargets"] = @{@"mobile":@"block"};
        XCTAssertTrue([store updateConfiguration:configuration error:&error], @"%@", error);
        XCTAssertTrue([call.toolTip containsString:@"Blocked by the dialling plan."]);
        dialler.callDestinationField.stringValue = @"123?invalid";
        XCTAssertTrue([call.toolTip containsString:@"Unsupported characters"]);
        XCTAssertEqualObjects(call.accessibilityHelp,call.toolTip);
        dialler.callDestinationField.stringValue = @"";
        XCTAssertEqualObjects(call.toolTip,@"Call");
        XCTAssertEqualObjects(call.accessibilityHelp,@"Call");
        XCTAssertEqualObjects(call.cell.accessibilityHelp,@"Call");
        [self assertNoPermanentRouteStatusInController:controller];
    } @finally {
        [controller.window orderOut:nil];
        [defaults removePersistentDomainForName:suite];
    }
}
- (void)testSharedDiallerKeepsCompactNativeControlsAndEditableOfflineField {
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:[AccountControllers new] historyFactory:nil];
    NSWindow *window = controller.window;
    [window.contentView layoutSubtreeIfNeeded];
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.height,104,0.5);
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.width,368,0.5);
    XCTAssertNotNil([window standardWindowButton:NSWindowCloseButton]);
    NSArray *views = [self descendants:window.contentView];
    NSUInteger tokenFields = 0, tables = 0;
    for (NSView *view in views) {
        if ([view isKindOfClass:NSTokenField.class]) {
            tokenFields++; XCTAssertFalse(view.hidden); XCTAssertTrue(((NSTokenField *)view).isEditable);
            XCTAssertTrue(NSContainsRect(window.contentView.bounds,[view convertRect:view.bounds toView:window.contentView]));
        }
        if ([view isKindOfClass:NSTableView.class]) tables++;
    }
    XCTAssertEqual(tokenFields,1u); XCTAssertEqual(tables,1u);
    for (NSString *appearanceName in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        window.appearance = [NSAppearance appearanceNamed:appearanceName];
        [window.contentView layoutSubtreeIfNeeded];
        NSBitmapImageRep *image = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
        [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:image];
        NSString *directory = @"/private/tmp/jps-guided-routes-snapshots";
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *name = [appearanceName isEqualToString:NSAppearanceNameAqua] ? @"shared-dialler-light.png" : @"shared-dialler-dark.png";
        XCTAssertTrue([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]);
    }
    [controller toggleHistory:nil];
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.height,268,0.5);
    [controller toggleHistory:nil];
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.height,104,0.5);
    [window orderOut:nil];
}
- (void)testExplicitSIPDestinationKeepsTransportAndPortAcrossCopies {
    AKSIPURI *uri = [AKSIPURI SIPURIWithString:@"sip:someone@example.test:5071;transport=tls"];
    XCTAssertNotNil(uri);
    AKSIPURI *copy = [uri copy];
    XCTAssertEqual(copy.port,5071);
    XCTAssertEqual(copy.transport,2);
    XCTAssertTrue([copy.description containsString:@";transport=tls"]);
    XCTAssertTrue([copy.description containsString:@"example.test:5071"]);
}
- (void)testExpandingHistoryPreservesWidthChosenWhileCollapsed {
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:[AccountControllers new] historyFactory:nil];
    NSWindow *window = controller.window;
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.width,368,0.5);
    [window setContentSize:NSMakeSize(500,104)];
    [controller toggleHistory:nil];
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.width,500,0.5);
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.height,268,0.5);
    [window setContentSize:NSMakeSize(620,310)];
    [controller toggleHistory:nil];
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.width,620,0.5);
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.height,104,0.5);
    [window setContentSize:NSMakeSize(500,104)];
    [controller toggleHistory:nil];
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.width,500,0.5);
    XCTAssertEqualWithAccuracy(window.contentView.bounds.size.height,310,0.5);
    [window orderOut:nil];
}
- (void)testUnavailableOutgoingAccountUsesNeutralStatusRatherThanOffline {
    JPSSharedDiallerAccountFixture *account = [JPSSharedDiallerAccountFixture new];
    account.enabled = YES;
    account.accountDescription = @"Synthetic connection";
    account.routingAvailability = @"unavailable";
    account.account = [JPSSharedDiallerAccountInfo new];
    account.account.uuid = @"synthetic-status"; account.account.domain = @"example.invalid";
    JPSSharedDiallerAccountsFixture *accounts = [JPSSharedDiallerAccountsFixture new];
    accounts.all = @[account];
    SharedDialerController *controller = [[SharedDialerController alloc] initWithAccounts:(id)accounts historyFactory:nil];
    NSPopUpButton *availability = [controller valueForKey:@"availability"];
    XCTAssertEqualObjects(availability.toolTip,@"Unavailable");
    XCTAssertEqualObjects(availability.accessibilityValue,@"Unavailable");
    XCTAssertEqualObjects(availability.accessibilityLabel,@"Account availability");
    XCTAssertEqualObjects(availability.cell.accessibilityLabel,@"Account availability");
    NSMenuItem *unavailable = availability.itemArray.lastObject.submenu.itemArray[1];
    XCTAssertEqual(unavailable.state,NSControlStateValueOn);

    account.accountRegistered = YES; account.routingAvailability = @"online";
    [controller rebuildAvailability];
    XCTAssertEqualObjects(availability.toolTip,@"Online");
    XCTAssertEqualObjects(availability.accessibilityValue,@"Online");
    account.accountRegistered = NO; account.routingAvailability = @"offline";
    [controller rebuildAvailability];
    XCTAssertEqualObjects(availability.toolTip,@"Offline");
    XCTAssertEqualObjects(availability.accessibilityValue,@"Offline");
    account.routingAvailability = @"unavailable"; account.enabled = NO;
    [controller rebuildAvailability];
    XCTAssertEqualObjects(availability.toolTip,@"Offline");
    XCTAssertEqualObjects(availability.accessibilityValue,@"Offline");
    [controller.window orderOut:nil];
}
- (void)testGuidedRoutesMenuExplicitlyTargetsApplicationDelegateOnce {
    [NSApplication sharedApplication];
    JPSSharedGuidedRoutesDispatchBoundary *controller = [[JPSSharedGuidedRoutesDispatchBoundary alloc] initWithAccounts:[AccountControllers new] historyFactory:nil];
    JPSSharedGuidedRoutesDelegate *delegate = [JPSSharedGuidedRoutesDelegate new];
    delegate.preferences = [JPSSharedGuidedRoutesPreferences new];
    id previousDelegate = NSApp.delegate;
    Method dispatch = class_getInstanceMethod(NSApplication.class,@selector(sendAction:to:from:));
    JPSOriginalApplicationSendAction = method_getImplementation(dispatch);
    JPSGuidedRouteDispatchTargets = [NSMutableArray new];
    method_setImplementation(dispatch,(IMP)JPSObserveApplicationSendAction);
    @try {
        NSApp.delegate = delegate;
        NSMenu *menu = [controller moreActionsMenu];
        NSMenuItem *guidedRoutes = nil;
        for (NSMenuItem *item in menu.itemArray) {
            if (item.action == @selector(showGuidedRoutes:)) { guidedRoutes = item; break; }
        }
        XCTAssertNotNil(guidedRoutes);
        XCTAssertEqualObjects(guidedRoutes.title,@"Guided routes…");
        XCTAssertEqual(guidedRoutes.target,controller);
        XCTAssertTrue([NSApp sendAction:guidedRoutes.action to:guidedRoutes.target from:guidedRoutes]);
        XCTAssertEqualObjects(JPSGuidedRouteDispatchTargets,(@[controller,delegate]));
        XCTAssertFalse(controller.interceptedLoop);
        XCTAssertEqual(controller.actionEntries,1u);
        XCTAssertEqual(delegate.deliveries,1u);
        XCTAssertEqual(delegate.lastSender,guidedRoutes);
        XCTAssertEqual(delegate.preferences.shows,1u);
        XCTAssertEqual(delegate.preferences.dialPlanShows,1u);

        // Missing ownership must not cause nil-target redispatch.
        NSApp.delegate = nil;
        [JPSGuidedRouteDispatchTargets removeAllObjects];
        controller.actionEntries = 0;
        controller.interceptedLoop = NO;
        XCTAssertTrue([NSApp sendAction:guidedRoutes.action to:guidedRoutes.target from:guidedRoutes]);
        XCTAssertEqualObjects(JPSGuidedRouteDispatchTargets,(@[controller]));
        XCTAssertFalse(controller.interceptedLoop);
        XCTAssertEqual(controller.actionEntries,1u);
        XCTAssertEqual(delegate.deliveries,1u);
        XCTAssertEqual(delegate.preferences.shows,1u);
        XCTAssertEqual(delegate.preferences.dialPlanShows,1u);
    } @finally {
        method_setImplementation(dispatch,JPSOriginalApplicationSendAction);
        JPSGuidedRouteDispatchTargets = nil;
        NSApp.delegate = previousDelegate;
        [controller.window orderOut:nil];
    }
}
@end
