#import <XCTest/XCTest.h>
#import "AccountController.h"
#import "AccountWindowController.h"
#import "AKSIPURI.h"
#import "AKSIPUserAgent.h"
#import "AccountControllers.h"
#import "Telephone-Swift.h"

@interface AccountController (RoutingRegressionBoundary)
- (void)SIPAccountRegistrationDidChange:(AKSIPAccount *)account;
- (void)dispatchRoutedRequest:(NSDictionary *)request;
- (void)setAccountRegistered:(BOOL)registered;
@end

// NSObject collaborators deliberately avoid the native account initializer,
// credentials, real preferences, reachability and PJSIP endpoint operations.
@interface JPSRoutingAccountFixture : NSObject
@property(nonatomic, copy) NSString *uuid;
// These routing-only collaborators have no stored credential identity. The
// real controller can still fence credential admission when routing goes Offline.
@property(nonatomic, copy) NSString *username;
@property(nonatomic) id registrar;
@property(nonatomic) NSInteger identifier;
@property(nonatomic, getter=isRegistered) BOOL registered;
@property(nonatomic) BOOL desiredRegistered;
@property(nonatomic) NSInteger registrationStatus;
@property(nonatomic) NSInteger registrationExpireTime;
@property(nonatomic, weak) id delegate;
@property(nonatomic) NSUInteger cancellations;
- (void)cancelPendingOutgoingCalls;
@end
@implementation JPSRoutingAccountFixture
- (void)cancelPendingOutgoingCalls { self.cancellations++; }
@end

@interface JPSRoutingAgentFixture : NSObject
- (BOOL)isStarted;
@end
@implementation JPSRoutingAgentFixture
- (BOOL)isStarted { return YES; }
@end

@interface JPSRoutingControllerFixture : AccountController
@property(nonatomic) NSUInteger registrationRequests;
@property(nonatomic) NSUInteger unregistrationRequests;
@property(nonatomic) NSMutableArray<NSNumber *> *registrationFlags;
@property(nonatomic) NSMutableArray<NSDictionary *> *dispatched;
@end
@implementation JPSRoutingControllerFixture
- (BOOL)isEnabled { return YES; }
- (void)registerAccount { self.registrationRequests++; }
- (void)setAccountRegistered:(BOOL)registered {
    [self.registrationFlags addObject:@(registered)];
    ((JPSRoutingAccountFixture *)(id)self.account).desiredRegistered = registered;
    if (self.account.identifier != kAKSIPUserAgentInvalidIdentifier) self.account.registered = registered;
}
- (void)unregisterAccount {
    self.unregistrationRequests++;
    [self setAccountRegistered:NO];
}
- (void)dispatchRoutedRequest:(NSDictionary *)request {
    NSMutableDictionary *captured = [request mutableCopy];
    captured[@"accountUUID"] = self.account.uuid;
    [self.dispatched addObject:captured];
}
- (void)showAvailableState { }
- (void)showUnavailableState { }
- (void)showOfflineState { }
- (void)showConnectingState { }
@end

@interface AccountRoutingRegressionTests : XCTestCase
@end
@implementation AccountRoutingRegressionTests
- (JPSRoutingControllerFixture *)controllerWithUUID:(NSString *)uuid registered:(BOOL)registered {
    JPSRoutingAccountFixture *account = [JPSRoutingAccountFixture new];
    account.uuid = uuid;
    account.identifier = 77;
    account.registered = registered;
    account.registrationStatus = 0;
    account.registrationExpireTime = 0;
    JPSRoutingControllerFixture *controller = [JPSRoutingControllerFixture new];
    controller.dispatched = [NSMutableArray array];
    controller.registrationFlags = [NSMutableArray array];
    [controller setValue:account forKey:@"account"];
    [controller setValue:[JPSRoutingAgentFixture new] forKey:@"userAgent"];
    [controller setValue:[NSMutableArray array] forKey:@"pendingRoutedCalls"];
    [controller setValue:[NSMutableArray array] forKey:@"callControllers"];
    [controller setValue:uuid forKey:@"accountDescription"];
    [controller setValue:@(AccountWindowControllerAccountStateAvailable) forKey:@"desiredAvailability"];
    return controller;
}
- (AKSIPURI *)uriWithNumber:(NSString *)number {
    return [[AKSIPURI alloc] initWithUser:number host:@"" displayName:@"Synthetic caller"];
}
- (void)completeRegistration:(JPSRoutingControllerFixture *)controller {
    JPSRoutingAccountFixture *account = (id)controller.account;
    account.registered = YES;
    [controller SIPAccountRegistrationDidChange:(id)account];
}
- (void)testTwoQueuedRequestsRetainImmutableDestinationsAndDistinctIDsThenDrainExactlyOnce {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"local" registered:NO];
    AKSIPURI *first = [self uriWithNumber:@"+447799414799"];
    AKSIPURI *second = [self uriWithNumber:@"+441442242110"];
    [controller makeRoutedCallToURI:first phoneLabel:@"mobile" canonicalDestination:@"+447799414799"];
    NSTimer *timeout = [controller valueForKey:@"routedCallTimeout"];
    [controller makeRoutedCallToURI:second phoneLabel:@"home" canonicalDestination:@"+441442242110"];
    first.user = @"mutated-after-queue";
    second.host = @"mutated.invalid";
    XCTAssertTrue(controller.hasPendingRoutedCalls);
    XCTAssertEqual(controller.registrationRequests, 2u);
    XCTAssertEqual(controller.dispatched.count, 0u);
    XCTAssertEqual([controller valueForKey:@"routedCallTimeout"], timeout);
    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 2u);
    XCTAssertEqualObjects([controller.dispatched[0][@"uri"] user], @"+447799414799");
    XCTAssertEqualObjects([controller.dispatched[1][@"uri"] host], @"");
    XCTAssertEqualObjects(controller.dispatched[0][@"label"], @"mobile");
    XCTAssertEqualObjects(controller.dispatched[1][@"canonical"], @"+441442242110");
    XCTAssertNotEqualObjects(controller.dispatched[0][@"id"], controller.dispatched[1][@"id"]);
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:controller.dispatched[0][@"id"]]);
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:controller.dispatched[1][@"id"]]);
    XCTAssertFalse(controller.hasPendingRoutedCalls);
    XCTAssertFalse(timeout.isValid);
    XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);
    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 2u);
}
- (void)testManualOfflineCancelsPendingRequestsAndRejectsLateRegistration {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"aa" registered:NO];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+441442242110"] phoneLabel:@"" canonicalDestination:@"+441442242110"];
    NSTimer *timeout = [controller valueForKey:@"routedCallTimeout"];
    [controller changeRoutingAvailability:@"offline"];
    XCTAssertFalse(controller.hasPendingRoutedCalls);
    XCTAssertFalse(timeout.isValid);
    XCTAssertEqual(((JPSRoutingAccountFixture *)(id)controller.account).cancellations, 1u);
    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 0u);
    XCTAssertFalse(controller.account.isRegistered);
}
- (void)testCancellingOneRequestRetainsOtherRequestAndOriginalAccountExpiry {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"synthetic-provider" registered:NO];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+447700900123"] phoneLabel:@"mobile" canonicalDestination:@"+447700900123"];
    NSTimer *timeout = [controller valueForKey:@"routedCallTimeout"];
    NSDate *originalExpiry = timeout.fireDate;
    NSString *cancelledIdentifier = controller.pendingRoutedCallSummaries.firstObject[@"id"];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+442079460958"] phoneLabel:@"home" canonicalDestination:@"+442079460958"];
    NSString *remainingIdentifier = controller.pendingRoutedCallSummaries.lastObject[@"id"];

    XCTAssertTrue([controller cancelPendingRoutedCallWithIdentifier:cancelledIdentifier]);
    XCTAssertEqual(controller.pendingRoutedCallSummaries.count, 1u);
    XCTAssertEqualObjects(controller.pendingRoutedCallSummaries.firstObject[@"id"], remainingIdentifier);
    XCTAssertEqual([controller valueForKey:@"routedCallTimeout"], timeout);
    XCTAssertTrue(timeout.isValid);
    XCTAssertEqualObjects(timeout.fireDate, originalExpiry);

    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 1u);
    XCTAssertEqualObjects(controller.dispatched.firstObject[@"id"], remainingIdentifier);
    XCTAssertEqualObjects([controller.dispatched.firstObject[@"uri"] user], @"+442079460958");
    XCTAssertEqualObjects(controller.dispatched.firstObject[@"canonical"], @"+442079460958");
    XCTAssertEqualObjects(controller.dispatched.firstObject[@"label"], @"home");
    XCTAssertFalse(timeout.isValid);
    XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);
    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 1u);
}
- (void)testPendingSummariesFreezeProviderAndDestinationWithoutExposingInternalObjects {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"synthetic-provider" registered:NO];
    NSMutableString *provider = [@"Synthetic provider" mutableCopy];
    NSMutableString *canonical = [@"+447700900123" mutableCopy];
    NSMutableString *label = [@"mobile" mutableCopy];
    [controller setValue:provider forKey:@"accountDescription"];
    AKSIPURI *first = [self uriWithNumber:@"+447700900123"];
    first.displayName = @"Private synthetic contact";
    [controller makeRoutedCallToURI:first phoneLabel:label canonicalDestination:canonical];
    AKSIPURI *second = [[AKSIPURI alloc] initWithUser:@"+442079460958" host:@"example.invalid" displayName:@"Another private synthetic contact" port:5071];
    [controller makeRoutedCallToURI:second phoneLabel:@"SIP" canonicalDestination:nil];
    NSArray<NSDictionary<NSString *, NSString *> *> *snapshot = controller.pendingRoutedCallSummaries;

    [provider appendString:@" renamed"];
    [canonical setString:@"changed after enqueue"];
    [label setString:@"changed label"];
    first.user = @"changed user";
    second.host = @"changed.invalid";
    ((JPSRoutingAccountFixture *)(id)controller.account).uuid = @"renamed-provider";
    [controller setValue:@"New provider name" forKey:@"accountDescription"];
    XCTAssertEqualObjects(controller.pendingRoutedCallSummaries, snapshot);
    XCTAssertFalse([snapshot isKindOfClass:NSMutableArray.class]);
    NSSet *expectedKeys = [NSSet setWithArray:@[@"id", @"accountUUID", @"providerName", @"destination"]];
    for (NSDictionary *summary in snapshot) {
        XCTAssertFalse([summary isKindOfClass:NSMutableDictionary.class]);
        XCTAssertEqualObjects([NSSet setWithArray:summary.allKeys], expectedKeys);
        for (id value in summary.allValues) XCTAssertTrue([value isKindOfClass:NSString.class]);
        XCTAssertEqualObjects(summary[@"accountUUID"], @"synthetic-provider");
        XCTAssertEqualObjects(summary[@"providerName"], @"Synthetic provider");
        XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:summary[@"id"]]);
    }
    XCTAssertEqualObjects(snapshot[0][@"destination"], @"+447700900123");
    XCTAssertEqualObjects(snapshot[1][@"destination"], @"+442079460958@example.invalid:5071");
    [self completeRegistration:controller];
    XCTAssertEqualObjects(controller.dispatched[0][@"canonical"], @"+447700900123");
    XCTAssertEqualObjects(controller.dispatched[0][@"label"], @"mobile");
    XCTAssertEqualObjects([controller.dispatched[1][@"uri"] host], @"example.invalid");
    XCTAssertEqual(snapshot.count, 2u);
    XCTAssertEqual(controller.pendingRoutedCallSummaries.count, 0u);
}
- (void)testPendingChangeNotificationsTrackMutationsAndFinalCancellationRejectsLateRegistration {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"synthetic-provider" registered:NO];
    NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:JPSPendingRoutedCallsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertNil(notification.object);
        XCTAssertNil(notification.userInfo);
        [counts addObject:@(controller.pendingRoutedCallSummaries.count)];
    }];
    @try {
        [controller makeRoutedCallToURI:[self uriWithNumber:@"+447700900123"] phoneLabel:@"" canonicalDestination:@"+447700900123"];
        NSString *firstIdentifier = controller.pendingRoutedCallSummaries.firstObject[@"id"];
        [controller makeRoutedCallToURI:[self uriWithNumber:@"+442079460958"] phoneLabel:@"" canonicalDestination:@"+442079460958"];
        NSString *lastIdentifier = controller.pendingRoutedCallSummaries.lastObject[@"id"];
        NSTimer *timeout = [controller valueForKey:@"routedCallTimeout"];
        XCTAssertFalse([controller cancelPendingRoutedCallWithIdentifier:NSUUID.UUID.UUIDString]);
        XCTAssertTrue([controller cancelPendingRoutedCallWithIdentifier:firstIdentifier]);
        XCTAssertFalse([controller cancelPendingRoutedCallWithIdentifier:firstIdentifier]);
        XCTAssertTrue([controller cancelPendingRoutedCallWithIdentifier:lastIdentifier]);
        XCTAssertFalse([controller cancelPendingRoutedCallWithIdentifier:lastIdentifier]);
        XCTAssertFalse(timeout.isValid);
        XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);
        [self completeRegistration:controller];
        XCTAssertEqual(controller.dispatched.count, 0u);
        XCTAssertEqualObjects(counts, (@[@1, @2, @1, @0]));

        ((JPSRoutingAccountFixture *)(id)controller.account).registered = NO;
        [controller makeRoutedCallToURI:[self uriWithNumber:@"+447700900123"] phoneLabel:@"" canonicalDestination:@"+447700900123"];
        [controller cancelPendingRoutedCalls];
        [controller cancelPendingRoutedCalls];
        [self completeRegistration:controller];
        XCTAssertEqual(controller.dispatched.count, 0u);
        ((JPSRoutingAccountFixture *)(id)controller.account).registered = NO;
        [controller makeRoutedCallToURI:[self uriWithNumber:@"+442079460958"] phoneLabel:@"" canonicalDestination:@"+442079460958"];
        [self completeRegistration:controller];
        [self completeRegistration:controller];
        XCTAssertEqual(controller.dispatched.count, 1u);
        XCTAssertEqualObjects(counts, (@[@1, @2, @1, @0, @1, @0, @1, @0]));
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [controller cancelPendingRoutedCalls];
    }
}
- (void)testExplicitCancellationCannotDialAfterRegistrationEventuallySucceeds {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"local" registered:NO];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+447799414799"] phoneLabel:@"" canonicalDestination:@"+447799414799"];
    [controller cancelPendingRoutedCalls];
    [controller cancelPendingRoutedCalls];
    XCTAssertFalse(controller.hasPendingRoutedCalls);
    XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);
    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 0u);
}
- (void)testUnsuccessfulRegistrationCallbackCancelsQueueAndLaterSuccessDoesNotReplayIt {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"aa" registered:NO];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+447799414799"] phoneLabel:@"" canonicalDestination:@"+447799414799"];
    // An inert unregistered snapshot exercises the actual failed-registration
    // queue branch without authentication sheets or automatic retry timers.
    [controller SIPAccountRegistrationDidChange:controller.account];
    XCTAssertFalse(controller.hasPendingRoutedCalls);
    XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);
    XCTAssertEqual(controller.dispatched.count, 0u);
    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 0u);
}
- (void)testSelectedAccountOwnsQueuedRequestWithoutFallbackToAnotherRegisteredAccount {
    JPSRoutingControllerFixture *selected = [self controllerWithUUID:@"aa" registered:NO];
    JPSRoutingControllerFixture *other = [self controllerWithUUID:@"local" registered:YES];
    [selected makeRoutedCallToURI:[self uriWithNumber:@"+447799414799"] phoneLabel:@"" canonicalDestination:@"+447799414799"];
    XCTAssertEqual(other.dispatched.count, 0u);
    [self completeRegistration:selected];
    XCTAssertEqual(selected.dispatched.count, 1u);
    XCTAssertEqualObjects(selected.dispatched[0][@"accountUUID"], @"aa");
    XCTAssertEqual(other.dispatched.count, 0u);
}
- (void)testRegisteredAccountDispatchesImmediatelyWithoutRegistrationQueueOrTimer {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"local" registered:YES];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+441442242110"] phoneLabel:@"home" canonicalDestination:@"+441442242110"];
    XCTAssertEqual(controller.dispatched.count, 1u);
    XCTAssertEqual(controller.registrationRequests, 0u);
    XCTAssertFalse(controller.hasPendingRoutedCalls);
    XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);
    XCTAssertEqualObjects(controller.dispatched[0][@"accountUUID"], @"local");
}
- (void)testUnavailableRegisteredIdentityStillAllowsOutgoingCalls {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"local" registered:NO];
    controller.accountUnavailable = YES;
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+441442242110"] phoneLabel:@"" canonicalDestination:@"+441442242110"];
    XCTAssertEqual(controller.dispatched.count, 1u);
    XCTAssertEqual(controller.registrationRequests, 0u);
    XCTAssertFalse(controller.hasPendingRoutedCalls);
}
- (void)testUnavailableAccountNotYetAddedQueuesWithoutChangingIncomingCallIntent {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"aa" registered:NO];
    ((JPSRoutingAccountFixture *)(id)controller.account).identifier = kAKSIPUserAgentInvalidIdentifier;
    [controller changeRoutingAvailability:@"unavailable"];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+441442242110"] phoneLabel:@"home" canonicalDestination:@"+441442242110"];

    XCTAssertTrue(controller.hasPendingRoutedCalls);
    XCTAssertEqual(controller.dispatched.count, 0u);
    XCTAssertEqual(controller.registrationRequests, 0u);
    XCTAssertEqualObjects(controller.registrationFlags, (@[@NO, @NO]));
    XCTAssertEqualObjects([controller valueForKey:@"desiredAvailability"], @(AccountWindowControllerAccountStateUnavailable));
    XCTAssertTrue(controller.isAccountUnavailable);
    XCTAssertFalse(((JPSRoutingAccountFixture *)(id)controller.account).desiredRegistered);

    [controller cancelPendingRoutedCalls];
    XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);
}
- (void)testPendingAvailableCallDrainsOnceAfterUnavailableSelectedWithoutEnablingIncomingCalls {
    JPSRoutingControllerFixture *controller = [self controllerWithUUID:@"local" registered:NO];
    [controller makeRoutedCallToURI:[self uriWithNumber:@"+447799414799"] phoneLabel:@"mobile" canonicalDestination:@"+447799414799"];
    NSTimer *timeout = [controller valueForKey:@"routedCallTimeout"];
    XCTAssertEqual(controller.registrationRequests, 1u);
    [controller changeRoutingAvailability:@"unavailable"];
    XCTAssertTrue(controller.hasPendingRoutedCalls);

    [self completeRegistration:controller];
    XCTAssertEqual(controller.dispatched.count, 1u);
    XCTAssertEqualObjects(controller.dispatched[0][@"accountUUID"], @"local");
    XCTAssertEqualObjects([controller.dispatched[0][@"uri"] user], @"+447799414799");
    XCTAssertEqual(controller.registrationRequests, 1u);
    XCTAssertEqual(controller.unregistrationRequests, 2u);
    XCTAssertEqualObjects(controller.registrationFlags, (@[@NO, @NO]));
    XCTAssertEqualObjects([controller valueForKey:@"desiredAvailability"], @(AccountWindowControllerAccountStateUnavailable));
    XCTAssertTrue(controller.isAccountUnavailable);
    XCTAssertFalse(controller.account.isRegistered);
    XCTAssertFalse(((JPSRoutingAccountFixture *)(id)controller.account).desiredRegistered);
    XCTAssertFalse(controller.hasPendingRoutedCalls);
    XCTAssertFalse(timeout.isValid);
    XCTAssertNil([controller valueForKey:@"routedCallTimeout"]);

    [self completeRegistration:controller];
    [controller SIPAccountRegistrationDidChange:controller.account];
    XCTAssertEqual(controller.dispatched.count, 1u);
    XCTAssertEqual(controller.registrationRequests, 1u);
    XCTAssertFalse(controller.account.isRegistered);
}
@end

@interface AccountRoutingCoordinatorIntegrationTests : XCTestCase
@property(nonatomic) DialPlanCoordinator *coordinator;
@property(nonatomic) AccountControllers *savedControllers;
@property(nonatomic, copy) NSDictionary *savedConfiguration;
@property(nonatomic) id savedStoredPlan;
@property(nonatomic, copy) void (^savedErrorHandler)(NSString *);
@property(nonatomic, copy) void (^savedShowHandler)(void);
@property(nonatomic, copy) void (^savedStartHandler)(void);
@property(nonatomic, copy) BOOL (^savedAcceptHandler)(void);
@property(nonatomic) JPSRoutingControllerFixture *local;
@property(nonatomic) JPSRoutingControllerFixture *aa;
@property(nonatomic) NSMutableArray<NSString *> *errors;
@property(nonatomic) NSUInteger backendStarts;
@property(nonatomic) BOOL isolatedHost;
@end

@implementation AccountRoutingCoordinatorIntegrationTests
- (void)setUp {
    [super setUp];
    // Shared production routing is exercised only in the explicitly isolated
    // host. A normal app's preference domain must never be used by this test.
    self.isolatedHost = [NSBundle.mainBundle.bundleIdentifier hasPrefix:@"uk.jpsit.telephone.tests."];
    XCTAssertTrue(self.isolatedHost, @"Coordinator integration requires the isolated synthetic host.");
    if (!self.isolatedHost) return;
    self.coordinator = DialPlanCoordinator.shared;
    self.savedControllers = self.coordinator.controllers;
    self.savedConfiguration = self.coordinator.store.configuration;
    self.savedStoredPlan = [self.coordinator.store.defaults objectForKey:DialPlanStore.settingsKey];
    self.savedErrorHandler = self.coordinator.errorHandler;
    self.savedShowHandler = self.coordinator.showDiallerHandler;
    self.savedStartHandler = self.coordinator.startBackendHandler;
    self.savedAcceptHandler = self.coordinator.canAcceptCallsHandler;

    AccountRoutingRegressionTests *factory = [AccountRoutingRegressionTests new];
    self.local = [factory controllerWithUUID:@"local" registered:YES];
    self.aa = [factory controllerWithUUID:@"aa" registered:YES];
    AccountControllers *controllers = [AccountControllers new];
    [controllers addController:self.local];
    [controllers addController:self.aa];
    self.coordinator.controllers = controllers;
    self.errors = [NSMutableArray array];
    __weak AccountRoutingCoordinatorIntegrationTests *weakSelf = self;
    self.coordinator.errorHandler = ^(NSString *message) { [weakSelf.errors addObject:message]; };
    self.coordinator.showDiallerHandler = ^{};
    self.coordinator.startBackendHandler = ^{ weakSelf.backendStarts++; };
    self.coordinator.canAcceptCallsHandler = ^{ return YES; };
    [self configureMobile:@"local" defaultConnection:@"aa" emergency:@"" service:@"" rules:@[]];
}
- (void)tearDown {
    if (self.isolatedHost) {
        NSError *error;
        XCTAssertTrue([self.coordinator.store updateConfiguration:self.savedConfiguration error:&error], @"Restoring synthetic plan: %@", error);
        if (self.savedStoredPlan) [self.coordinator.store.defaults setObject:self.savedStoredPlan forKey:DialPlanStore.settingsKey];
        else [self.coordinator.store.defaults removeObjectForKey:DialPlanStore.settingsKey];
        self.coordinator.controllers = self.savedControllers;
        self.coordinator.errorHandler = self.savedErrorHandler;
        self.coordinator.showDiallerHandler = self.savedShowHandler;
        self.coordinator.startBackendHandler = self.savedStartHandler;
        self.coordinator.canAcceptCallsHandler = self.savedAcceptHandler;
    }
    [super tearDown];
}
- (void)configureMobile:(NSString *)mobile defaultConnection:(NSString *)defaultConnection emergency:(NSString *)emergency service:(NSString *)service rules:(NSArray *)rules {
    NSDictionary *configuration = @{@"schemaVersion": @1, @"countryCode": @"+44", @"areaCode": @"01442",
                                    @"defaultAccountUUID": defaultConnection, @"emergencyAccountUUID": emergency,
                                    @"categoryTargets": @{@"mobile": mobile, @"service": service}, @"rules": rules};
    NSError *error;
    XCTAssertTrue([self.coordinator.store updateConfiguration:configuration error:&error], @"Synthetic routing configuration: %@", error);
}
- (NSDictionary *)blockRule:(NSString *)prefix {
    return @{@"id": NSUUID.UUID.UUIDString, @"prefix": prefix, @"enabled": @YES, @"target": @"block", @"comment": @"Synthetic block"};
}
- (void)testMobileNormalisationAndCallbackUseCurrentPlanAndPreserveDisplayName {
    if (!self.isolatedHost) return;
    XCTAssertTrue([self.coordinator routeDestination:@"07799414799" phoneLabel:@"mobile" displayName:@"Synthetic person"]);
    XCTAssertEqual(self.local.dispatched.count, 1u);
    XCTAssertEqual(self.aa.dispatched.count, 0u);
    NSDictionary *first = self.local.dispatched[0];
    XCTAssertEqualObjects([first[@"uri"] user], @"+447799414799");
    XCTAssertEqualObjects(first[@"canonical"], @"+447799414799");
    XCTAssertEqualObjects([first[@"uri"] displayName], @"Synthetic person");
    XCTAssertEqualObjects(first[@"label"], @"mobile");

    [self configureMobile:@"aa" defaultConnection:@"aa" emergency:@"" service:@"" rules:@[]];
    XCTAssertTrue([self.coordinator routeDestination:first[@"canonical"] phoneLabel:@"mobile" displayName:@"Synthetic person"]);
    XCTAssertEqual(self.local.dispatched.count, 1u);
    XCTAssertEqual(self.aa.dispatched.count, 1u);
    XCTAssertEqualObjects(self.aa.dispatched[0][@"accountUUID"], @"aa");
    XCTAssertEqualObjects([self.aa.dispatched[0][@"uri"] displayName], @"Synthetic person");
    XCTAssertEqual(self.backendStarts, 2u);
    XCTAssertEqual(self.errors.count, 0u);
}
- (void)testBareSIPAddressUsesDefaultConnectionAndRetainsExplicitPortAndTLS {
    if (!self.isolatedHost) return;
    XCTAssertTrue([self.coordinator routeDestination:@"person@example.invalid:5071;transport=tls" phoneLabel:@"SIP" displayName:@"Synthetic SIP person"]);
    XCTAssertEqual(self.local.dispatched.count, 0u);
    XCTAssertEqual(self.aa.dispatched.count, 1u);
    AKSIPURI *uri = self.aa.dispatched[0][@"uri"];
    XCTAssertEqualObjects(uri.user, @"person");
    XCTAssertEqualObjects(uri.host, @"example.invalid");
    XCTAssertEqual(uri.port, 5071);
    XCTAssertEqual(uri.transport, 2);
    XCTAssertTrue(uri.usesExplicitTransport);
    XCTAssertTrue([uri.description containsString:@";transport=tls"]);
    XCTAssertEqualObjects(uri.displayName, @"Synthetic SIP person");
    XCTAssertTrue([self.aa.dispatched[0][@"canonical"] containsString:@"example.invalid:5071;transport=tls"]);
    XCTAssertEqual(self.backendStarts, 1u);
}
- (void)testMoreSpecificBlockExceptionPreventsAnyAccountDispatch {
    if (!self.isolatedHost) return;
    [self configureMobile:@"local" defaultConnection:@"aa" emergency:@"" service:@"" rules:@[[self blockRule:@"+447799"]]];
    XCTAssertFalse([self.coordinator routeDestination:@"07799414799" phoneLabel:@"mobile"]);
    XCTAssertEqual(self.local.dispatched.count, 0u);
    XCTAssertEqual(self.aa.dispatched.count, 0u);
    XCTAssertEqual(self.backendStarts, 0u);
    XCTAssertEqual(self.errors.count, 1u);
}
- (void)testApplicationCallAdmissionGatePreventsRoutingAndBackendStartup {
    if (!self.isolatedHost) return;
    self.coordinator.canAcceptCallsHandler = ^{ return NO; };
    XCTAssertFalse([self.coordinator routeDestination:@"07799414799" phoneLabel:@"mobile"]);
    XCTAssertFalse([self.coordinator routeDestination:@"person@example.invalid:5071;transport=tls" phoneLabel:@"SIP"]);
    XCTAssertEqual(self.local.dispatched.count, 0u);
    XCTAssertEqual(self.aa.dispatched.count, 0u);
    XCTAssertEqual(self.backendStarts, 0u);
    XCTAssertEqual(self.errors.count, 0u);
}
- (void)testEmergencyAndServiceCallbacksRetainLiteralDestinationAndUseCurrentPolicy {
    if (!self.isolatedHost) return;
    [self configureMobile:@"local" defaultConnection:@"local" emergency:@"aa" service:@"" rules:@[]];
    XCTAssertTrue([self.coordinator routeDestination:@"999" phoneLabel:@""]);
    XCTAssertEqualObjects([self.aa.dispatched[0][@"uri"] user], @"999");
    XCTAssertEqualObjects(self.aa.dispatched[0][@"canonical"], @"999");

    [self configureMobile:@"local" defaultConnection:@"local" emergency:@"aa" service:@"block" rules:@[[self blockRule:@"9"]]];
    XCTAssertFalse([self.coordinator routeDestination:@"*21*123#" phoneLabel:@""]);
    XCTAssertEqual(self.local.dispatched.count, 0u);
    XCTAssertEqual(self.aa.dispatched.count, 1u);
    XCTAssertTrue([self.coordinator routeDestination:self.aa.dispatched[0][@"canonical"] phoneLabel:@""]);
    XCTAssertEqual(self.aa.dispatched.count, 2u);
    XCTAssertEqualObjects([self.aa.dispatched[1][@"uri"] user], @"999");
    XCTAssertEqualObjects(self.aa.dispatched[1][@"canonical"], @"999");
    XCTAssertEqual(self.local.dispatched.count, 0u);
    XCTAssertEqual(self.backendStarts, 2u);
    XCTAssertEqual(self.errors.count, 1u);
}
@end
