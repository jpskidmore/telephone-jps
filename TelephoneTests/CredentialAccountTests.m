#import <XCTest/XCTest.h>
#import "AKKeychain.h"
#import "AccountController.h"
#import "AppController.h"
#import "AccountControllers.h"
#import "AccountWindowController.h"
#import "AuthenticationFailureController.h"

@interface AccountController (CredentialAccountTestBoundary)
- (void)presentCredentialReadFailure:(AKCredentialReadResult *)result;
- (void)changeAccountState:(AccountWindowControllerAccountState)state;
@end

@interface K73DeferredBroker : AKCredentialBroker
@property(nonatomic) NSMutableArray *completions;
@property(nonatomic) NSUInteger reads, invalidations;
- (instancetype)init;
@end
@implementation K73DeferredBroker
- (instancetype)init {
    if ((self = [super initWithReader:^AKCredentialReadResult *(NSString *service, NSString *account) {
        XCTFail(@"Deferred consumer fixture must not invoke a Security reader");
        return [AKCredentialReadResult successWithPassword:@"synthetic"];
    }])) _completions = [NSMutableArray new];
    return self;
}
- (void)readPasswordForService:(NSString *)service account:(NSString *)account completion:(AKCredentialReadCompletion)completion {
    self.reads++; [self.completions addObject:[completion copy]];
}
- (void)invalidateService:(NSString *)service account:(NSString *)account { self.invalidations++; }
@end

@interface K73SyntheticAccount : AKSIPAccount
@property(nonatomic) NSUInteger positiveRegistrations, unregistrations;
@end
@implementation K73SyntheticAccount
- (void)setRegistered:(BOOL)registered { self.desiredRegistered = registered; if (registered) self.positiveRegistrations++; else self.unregistrations++; }
@end
@interface K73RegistrationAgent : NSObject
@property(nonatomic, getter=isStarted) BOOL started;
@property(nonatomic) NSUInteger adds, removals;
@property(nonatomic, copy) NSString *password;
@property(nonatomic, copy) void (^addCompletion)(BOOL);
@property(nonatomic) AKSIPAccount *removedAccount;
@end
@implementation K73RegistrationAgent
- (void)addAccount:(AKSIPAccount *)account withPassword:(NSString *)password completion:(void (^)(BOOL))completion {
    self.adds++; self.password = password; self.addCompletion = completion;
}
- (void)removeAccount:(AKSIPAccount *)account completion:(void (^)(BOOL))completion {
    self.removals++; self.removedAccount = account; completion(YES);
}
@end
@interface K73CredentialAccount : AccountController
@property(nonatomic) K73DeferredBroker *broker;
@property(nonatomic) NSUInteger errors, connecting, unavailable;
@end
@implementation K73CredentialAccount
- (AKCredentialBroker *)credentialBroker { return self.broker; }
- (void)showConnectingState { self.connecting++; }
- (void)showUnavailableState { self.unavailable++; }
- (void)showOfflineState {}
- (void)presentCredentialReadFailure:(AKCredentialReadResult *)result { self.errors++; }
@end

@interface AppController (K73WakeBoundary)
- (void)workspaceDidWake:(NSNotification *)notification;
@end
@interface K73WakeSleep : NSObject
@property(nonatomic, getter=isSleeping) BOOL sleeping;
@end
@implementation K73WakeSleep @end
@interface K73WakeAccounts : NSObject
@property(nonatomic) BOOL suspended;
@property(nonatomic) NSUInteger registrations;
@end
@implementation K73WakeAccounts
- (void)setCredentialAccessSuspended:(BOOL)suspended { self.suspended = suspended; }
- (void)registerReachableAccounts { self.registrations++; }
@end
@interface K73WakeApplication : AppController
@property(nonatomic) K73WakeSleep *syntheticSleep;
@property(nonatomic) K73WakeAccounts *syntheticAccounts;
@property(nonatomic) BOOL syntheticTerminating;
@end
@implementation K73WakeApplication
// Exercise only the wake method. Do not construct the production composition,
// defaults, Contacts, credentials, native SIP or application delegate lifecycle.
- (instancetype)init { return self; }
- (id)sleepStatus { return self.syntheticSleep; }
- (id)accountControllers { return self.syntheticAccounts; }
- (BOOL)isUserSessionActive { return YES; }
- (BOOL)isTerminating { return self.syntheticTerminating; }
@end

@interface CredentialAccountTests : XCTestCase
@property(nonatomic) K73CredentialAccount *owner;
@property(nonatomic) K73RegistrationAgent *agent;
@end
@implementation CredentialAccountTests
- (K73SyntheticAccount *)syntheticAccount {
    return [[K73SyntheticAccount alloc] initWithDictionary:@{@"UUID": NSUUID.UUID.UUIDString,
        @"FullName": @"Synthetic", @"Domain": @"example.invalid", @"Username": @"synthetic", @"Realm": @"*"} parser:nil];
}
- (void)setUp {
    [super setUp];
    self.owner = [K73CredentialAccount new]; self.owner.broker = [[K73DeferredBroker alloc] init];
    self.agent = [K73RegistrationAgent new]; self.agent.started = YES;
    [self.owner setValue:[self syntheticAccount] forKey:@"account"];
    [self.owner setValue:self.agent forKey:@"userAgent"];
    [self.owner setValue:@YES forKey:@"_enabled"];
    [self.owner setValue:@(AccountWindowControllerAccountStateAvailable) forKey:@"desiredAvailability"];
    [self.owner setValue:[NSMutableArray new] forKey:@"callControllers"];
}
- (void)deliver:(AKCredentialReadResult *)result at:(NSUInteger)index {
    AKCredentialReadCompletion completion = self.owner.broker.completions[index]; completion(result);
}
- (void)testRegistrationWaitsForCredentialAndAcceptsLegitimateEmptySuccess {
    [self.owner registerAccount]; XCTAssertEqual(self.agent.adds, 0u);
    XCTAssertEqual(self.owner.broker.reads, 1u);
    [self deliver:[AKCredentialReadResult successWithPassword:@""] at:0];
    XCTAssertEqual(self.agent.adds, 1u); XCTAssertEqualObjects(self.agent.password, @"");
}
- (void)testFailedReadsNeverAddEmptyPasswordOrAutomaticallyRetry {
    for (NSNumber *status in @[@(AKCredentialReadStatusMissing), @(AKCredentialReadStatusCancelled),
             @(AKCredentialReadStatusDenied), @(AKCredentialReadStatusInvalidData), @(AKCredentialReadStatusFailure)]) {
        [self.owner changeAccountState:AccountWindowControllerAccountStateAvailable];
        NSUInteger reads = self.owner.broker.reads;
        [self deliver:[AKCredentialReadResult failureWithStatus:status.integerValue securityStatus:errSecAuthFailed] at:reads - 1];
        [self.owner resumeRegistrationIfDesired]; [self.owner registerAccount];
        XCTAssertEqual(self.owner.broker.reads, reads); XCTAssertEqual(self.agent.adds, 0u);
    }
}
- (void)testManualOnlineAllowsOneNewAttemptAfterCancellation {
    [self.owner registerAccount];
    [self deliver:[AKCredentialReadResult failureWithStatus:AKCredentialReadStatusCancelled securityStatus:errSecUserCanceled] at:0];
    [self.owner changeAccountState:AccountWindowControllerAccountStateAvailable];
    XCTAssertEqual(self.owner.broker.reads, 2u);
    [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:1]; XCTAssertEqual(self.agent.adds, 1u);
}
- (void)testOfflineRejectsLateCredentialResult {
    [self.owner registerAccount]; [self.owner changeAccountState:AccountWindowControllerAccountStateOffline];
    [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:0]; XCTAssertEqual(self.agent.adds, 0u);
}
- (void)testRemovalRejectsLateCredentialResultEvenWhenAccountWasNotAdded {
    [self.owner registerAccount]; __block BOOL removed = NO;
    [self.owner removeAccountFromUserAgentWithCompletion:^(BOOL success) { removed = success; }];
    XCTAssertTrue(removed);
    [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:0]; XCTAssertEqual(self.agent.adds, 0u);
}
- (void)testSuspensionAndAccountReplacementRejectLateResults {
    [self.owner registerAccount]; [self.owner setCredentialAccessSuspended:YES];
    [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:0]; XCTAssertEqual(self.agent.adds, 0u);
    [self.owner setCredentialAccessSuspended:NO]; [self.owner registerAccount];
    [self.owner setValue:[self syntheticAccount] forKey:@"account"];
    [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:1]; XCTAssertEqual(self.agent.adds, 0u);
}
- (void)testRenamedCredentialRejectsLateResult {
    [self.owner registerAccount]; [self.owner.account updateUsername:@"new-synthetic"];
    [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:0]; XCTAssertEqual(self.agent.adds, 0u);
}
- (void)testLateNativeAddCleansUpCapturedAccountAfterReplacement {
    AKSIPAccount *captured = self.owner.account;
    [self.owner registerAccount]; [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:0];
    [self.owner setValue:[self syntheticAccount] forKey:@"account"];
    self.agent.addCompletion(YES);
    XCTAssertEqual(self.agent.removedAccount, captured); XCTAssertEqual(self.agent.removals, 1u);
}
- (void)testSuspensionRejectsAddedAccountRegistrationButAllowsUnregister {
    K73SyntheticAccount *account = (id)self.owner.account; [account updateIdentifier:77];
    [self.owner setCredentialAccessSuspended:YES]; [self.owner registerAccount];
    XCTAssertEqual(account.positiveRegistrations, 0u); XCTAssertEqual(self.owner.broker.reads, 0u);
    [self.owner unregisterAccount]; XCTAssertEqual(account.unregistrations, 1u);
}
- (void)testObsoleteNativeAddCannotRemoveNewerSameAccountAttempt {
    [self.owner registerAccount]; [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:0];
    void (^oldCompletion)(BOOL) = self.agent.addCompletion;
    [self.owner changeAccountState:AccountWindowControllerAccountStateAvailable];
    oldCompletion(YES);
    XCTAssertEqual(self.agent.removals, 0u);
    [self deliver:[AKCredentialReadResult successWithPassword:@"new-synthetic"] at:1];
    XCTAssertEqual(self.agent.adds, 2u);
}
- (void)testCollectionRemovalInvalidatesCredentialAdmission {
    AccountControllers *controllers = [AccountControllers new]; [controllers addController:self.owner];
    [self.owner registerAccount]; [controllers removeControllerAtIndex:0];
    [self deliver:[AKCredentialReadResult successWithPassword:@"synthetic"] at:0]; XCTAssertEqual(self.agent.adds, 0u);
}
- (void)testWakeReactivationWaitsForOtherSleepObservers {
    K73WakeApplication *application = [K73WakeApplication new];
    application.syntheticSleep = [K73WakeSleep new]; application.syntheticSleep.sleeping = YES;
    application.syntheticAccounts = [K73WakeAccounts new]; application.syntheticAccounts.suspended = YES;
    [application workspaceDidWake:nil];
    XCTAssertEqual(application.syntheticAccounts.registrations, 0u);
    application.syntheticSleep.sleeping = NO;
    XCTestExpectation *done = [self expectationWithDescription:@"wake observers completed"];
    dispatch_async(dispatch_get_main_queue(), ^{
        XCTAssertEqual(application.syntheticAccounts.registrations, 1u);
        XCTAssertFalse(application.syntheticAccounts.suspended); [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:2];
}
- (void)testQueuedWakeCannotReopenCredentialAdmissionAfterQuit {
    K73WakeApplication *application = [K73WakeApplication new];
    application.syntheticSleep = [K73WakeSleep new];
    application.syntheticAccounts = [K73WakeAccounts new]; application.syntheticAccounts.suspended = YES;
    [application workspaceDidWake:nil]; application.syntheticTerminating = YES;
    XCTestExpectation *done = [self expectationWithDescription:@"obsolete wake ignored"];
    dispatch_async(dispatch_get_main_queue(), ^{
        XCTAssertEqual(application.syntheticAccounts.registrations, 0u);
        XCTAssertTrue(application.syntheticAccounts.suspended); [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:2];
}
@end
