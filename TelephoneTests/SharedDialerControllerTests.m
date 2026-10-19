#import <XCTest/XCTest.h>
#import "SharedDialerController.h"
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
@end
@implementation JPSSharedDiallerAccountFixture @end

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
- (NSTextField *)routeStatusInController:(SharedDialerController *)controller {
    for (NSView *view in [self descendants:controller.window.contentView]) {
        if ([view.identifier isEqualToString:@"CompactOutgoingRouteStatus"]) return (NSTextField *)view;
    }
    XCTFail(@"The selected outgoing connection must be visible in the compact dialler.");
    return nil;
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
- (void)testVisibleSelectedRouteReadinessDiffersFromAggregateOnlineAndTracksAccountState {
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
        routeResolver:^DialPlanRoute *(NSString *input) { return [store resolveDestination:input accounts:[self routeSnapshots:accounts]]; }];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        // Raw input exercises the route-preview path without Contacts tokenisation.
        dialler.callDestinationField.delegate = nil;
        dialler.callDestinationField.stringValue = @"07700900123";
        NSTextField *status = [self routeStatusInController:controller];
        NSPopUpButton *availability = [controller valueForKey:@"availability"];
        XCTAssertFalse(status.hidden);
        XCTAssertEqualObjects(status.stringValue,@"Offline · Localphone");
        XCTAssertEqualObjects(availability.accessibilityValue,@"Online");
        XCTAssertEqualObjects(status.accessibilityLabel,@"Outgoing connection");
        XCTAssertTrue([status.toolTip containsString:@"+447700900123"]);
        XCTAssertTrue([status.accessibilityHelp containsString:@"no other connection will be used"]);
        DialPlanRoute *route = [store resolveDestination:@"07700900123" accounts:[self routeSnapshots:accounts]];
        XCTAssertEqualObjects(route.accountUUID,@"local");
        XCTAssertFalse(route.canDial);

        local.routingAvailability = @"registering";
        [NSNotificationCenter.defaultCenter postNotificationName:@"JPSAccountRoutingStateDidChangeNotification" object:local];
        XCTAssertEqualObjects(status.stringValue,@"Waiting · Localphone");
        XCTAssertTrue([status.toolTip containsString:@"Wait for Localphone to register"]);
        local.accountRegistered = YES; local.routingAvailability = @"online";
        [NSNotificationCenter.defaultCenter postNotificationName:@"JPSAccountRoutingStateDidChangeNotification" object:local];
        XCTAssertEqualObjects(status.stringValue,@"Ready · Localphone");
        route = [store resolveDestination:@"07700900123" accounts:[self routeSnapshots:accounts]];
        XCTAssertEqualObjects(route.accountUUID,@"local");
        XCTAssertTrue(route.canDial);
        XCTAssertEqualObjects(route.destination.destination,@"+447700900123");
        local.enabled = NO;
        [controller refreshAccounts];
        XCTAssertEqualObjects(status.stringValue,@"Disabled · Localphone");
        XCTAssertEqualObjects(availability.accessibilityValue,@"Online");
    } @finally {
        [controller.window orderOut:nil];
        [defaults removePersistentDomainForName:suite];
    }
}
- (void)testVisibleRouteFollowsDestinationSavedPlanAccountRenameAndRemoval {
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
        routeResolver:^DialPlanRoute *(NSString *input) { return [store resolveDestination:input accounts:[self routeSnapshots:accounts]]; }];
    @try {
        ActiveAccountViewController *dialler = [controller valueForKey:@"dialler"];
        // Raw input exercises the route-preview path without Contacts tokenisation.
        dialler.callDestinationField.delegate = nil;
        NSTextField *status = [self routeStatusInController:controller];
        dialler.callDestinationField.stringValue = @"02079460958";
        XCTAssertEqualObjects(status.stringValue,@"Ready · AA");
        configuration[@"defaultAccountUUID"] = @"local";
        XCTAssertEqualObjects(status.stringValue,@"Ready · AA", @"An unsaved draft must not change the dialler.");
        XCTAssertTrue([store updateConfiguration:configuration error:&error], @"%@", error);
        XCTAssertEqualObjects(status.stringValue,@"Ready · Localphone");
        local.accountDescription = @"A deliberately long synthetic connection name for the compact outgoing status";
        [controller refreshAccounts];
        NSString *fullStatus = [@"Ready · " stringByAppendingString:local.accountDescription];
        XCTAssertEqualObjects(status.stringValue,fullStatus);
        XCTAssertEqualObjects(status.accessibilityValue,fullStatus);
        XCTAssertTrue([status.toolTip containsString:local.accountDescription]);
        XCTAssertEqual(status.lineBreakMode,NSLineBreakByTruncatingTail);
        id<NSAccessibility> accessibleStatus = NSAccessibilityUnignoredDescendant(status);
        XCTAssertEqualObjects(accessibleStatus.accessibilityLabel,@"Outgoing connection");
        XCTAssertEqualObjects(accessibleStatus.accessibilityValue,fullStatus);
        XCTAssertEqualObjects(accessibleStatus.accessibilityHelp,status.toolTip);
        XCTAssertFalse(status.isEditable);
        XCTAssertFalse(status.isSelectable);
        XCTAssertFalse(status.acceptsFirstResponder);
        [controller.window.contentView layoutSubtreeIfNeeded];
        CGFloat narrowWidth = status.bounds.size.width;
        [controller.window setContentSize:NSMakeSize(500,104)];
        [controller.window.contentView layoutSubtreeIfNeeded];
        XCTAssertGreaterThan(status.bounds.size.width,narrowWidth);
        XCTAssertEqualObjects(status.accessibilityValue,fullStatus);
        [controller.window setContentSize:NSMakeSize(368,104)];
        for (NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
            controller.window.appearance = [NSAppearance appearanceNamed:appearance];
            [controller.window.contentView layoutSubtreeIfNeeded];
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.width,368,0.5);
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.height,104,0.5);
            NSRect statusFrame = [status convertRect:status.bounds toView:controller.window.contentView];
            NSRect fieldFrame = [dialler.callDestinationField convertRect:dialler.callDestinationField.bounds toView:controller.window.contentView];
            XCTAssertTrue(NSContainsRect(controller.window.contentView.bounds,statusFrame));
            XCTAssertFalse(NSIntersectsRect(statusFrame,fieldFrame));
            XCTAssertGreaterThan(statusFrame.size.width,100);
            NSString *name = [appearance isEqualToString:NSAppearanceNameAqua] ? @"route-status-long-light.png" : @"route-status-long-dark.png";
            [self writeRouteSnapshotIfRequested:controller.window name:name];
            [controller toggleHistory:nil];
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.height,268,0.5);
            XCTAssertEqualWithAccuracy(controller.window.contentView.bounds.size.width,368,0.5);
            [controller toggleHistory:nil];
        }
        accounts.all = @[aa];
        [controller refreshAccounts];
        XCTAssertEqualObjects(status.stringValue,@"Connection removed");
        dialler.callDestinationField.stringValue = @"07700900123";
        configuration[@"categoryTargets"] = @{@"mobile":@"block"};
        XCTAssertTrue([store updateConfiguration:configuration error:&error], @"%@", error);
        XCTAssertEqualObjects(status.stringValue,@"Blocked by dial plan");
        dialler.callDestinationField.stringValue = @"123?invalid";
        XCTAssertEqualObjects(status.stringValue,@"Check number");
        XCTAssertTrue([status.toolTip containsString:@"Unsupported characters"]);
        dialler.callDestinationField.stringValue = @"";
        XCTAssertEqualObjects(status.stringValue,@"Enter a number");
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
