#import <XCTest/XCTest.h>
#import "AppController.h"

@interface AppController (TerminationRegressionInterface)
- (void)finishTerminationAfterRecordings;
- (NSArray *)pendingRecordingRecoveryJobs;
- (void)refreshRecordingRecoveryJobsWithCompletion:(void (^)(BOOL current, NSArray *jobs, NSError *error))completion;
- (BOOL)confirmQuitWithRecordingRecoveryError:(NSError *)error;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (void)waitForRecordingFinalizations:(dispatch_block_t)completion;
- (void)finishPendingHistoryWrites:(dispatch_block_t)completion;
- (void)retryFailedHistoryWrites:(void (^)(BOOL))completion;
- (void)replyToTermination:(BOOL)shouldTerminate;
- (BOOL)confirmQuitWithRecoveryJobs:(NSArray *)jobs;
- (void)callHistoryPersistenceDidFail:(NSNotification *)notification;
- (AKSIPUserAgent *)userAgent;
- (NSUserDefaults *)networkSettingsDefaults;
- (void)preferencesControllerDidChangeNetworkSettings:(NSNotification *)notification;
- (void)SIPUserAgentDidFinishStarting:(NSNotification *)notification;
- (void)SIPUserAgentDidFinishStopping:(NSNotification *)notification;
- (void)stopUserAgent;

@end

@interface InertTerminationAgent: NSObject
@property(nonatomic, readonly) AKSIPUserAgentState state;
@property(nonatomic, readonly) BOOL isStarted;
@end
@implementation InertTerminationAgent
- (AKSIPUserAgentState)state { return AKSIPUserAgentStateStopped; }
- (BOOL)isStarted { return NO; }
@end

@interface ControlledTerminationController: AppController
@property(nonatomic) InertTerminationAgent *inertAgent;
@property(nonatomic) NSArray *jobs;
@property(nonatomic) NSMutableArray<NSNumber *> *replies;
@property(nonatomic, copy) dispatch_block_t recordingCompletion;
@property(nonatomic, copy) dispatch_block_t historyCompletion;
@property(nonatomic, copy) void (^retryCompletion)(BOOL);
@property(nonatomic) NSUInteger recordingWaitCount;
@property(nonatomic) NSUInteger historyWaitCount;
@property(nonatomic) NSUInteger retryCount;
@property(nonatomic) NSUInteger historyWarnings;
@property(nonatomic) NSUInteger recordingConfirmations;
@property(nonatomic) BOOL allowQuitWithRecovery;
@property(nonatomic) BOOL deferRecoveryScan, allowQuitWithScanError;
@property(nonatomic) NSUInteger recoveryScans, scanWarnings;
@property(nonatomic) NSError *recoveryScanError;
@property(nonatomic, copy) void (^scanCompletion)(BOOL, NSArray *, NSError *);
- (instancetype)initForRegression;
@end
@implementation ControlledTerminationController
- (instancetype)initForRegression {
    // Do not call AppController.init: it constructs user defaults/accounts/SDK.
    // Objective-C allocation already zeroes NSObject storage; initialise only
    // synthetic subclass state, never awakeFromNib or the real application.
    _inertAgent = [InertTerminationAgent new];
    _jobs = @[];
    _replies = [NSMutableArray array];
    _allowQuitWithRecovery = YES; _allowQuitWithScanError = YES;
    [self setValue:@YES forKey:@"terminating"];
    return self;
}
- (AKSIPUserAgent *)userAgent { return (id)self.inertAgent; }
- (NSArray *)pendingRecordingRecoveryJobs { return self.jobs; }
- (void)refreshRecordingRecoveryJobsWithCompletion:(void (^)(BOOL, NSArray *, NSError *))completion {
    self.recoveryScans++;
    if (self.deferRecoveryScan) self.scanCompletion = completion;
    else completion(YES, self.jobs, self.recoveryScanError);
}
- (BOOL)confirmQuitWithRecordingRecoveryError:(NSError *)error { self.scanWarnings++; return self.allowQuitWithScanError; }
- (void)waitForRecordingFinalizations:(dispatch_block_t)completion {
    self.recordingWaitCount++; self.recordingCompletion = completion;
}
- (void)finishPendingHistoryWrites:(dispatch_block_t)completion {
    self.historyWaitCount++; self.historyCompletion = completion;
}
- (void)retryFailedHistoryWrites:(void (^)(BOOL))completion {
    self.retryCount++; self.retryCompletion = completion;
}
- (void)replyToTermination:(BOOL)shouldTerminate { [self.replies addObject:@(shouldTerminate)]; }
- (BOOL)confirmQuitWithRecoveryJobs:(NSArray *)jobs {
    self.recordingConfirmations++; return self.allowQuitWithRecovery;
}
- (void)callHistoryPersistenceDidFail:(NSNotification *)notification { self.historyWarnings++; }
@end

@interface AppTerminationRegressionTests: XCTestCase
@end
@implementation AppTerminationRegressionTests
- (void)testFinalReplyWaitsForRecordingsHistoryDrainAndSuccessfulRetry {
    ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
    [controller finishTerminationAfterRecordings];
    [controller finishTerminationAfterRecordings];
    XCTAssertEqual(controller.recordingWaitCount, 1u);
    XCTAssertEqual(controller.historyWaitCount, 0u);
    XCTAssertEqual(controller.replies.count, 0u);
    controller.recordingCompletion();
    XCTAssertEqual(controller.historyWaitCount, 1u);
    XCTAssertEqual(controller.retryCount, 0u);
    XCTAssertEqual(controller.replies.count, 0u);
    [controller finishTerminationAfterRecordings];
    XCTAssertEqual(controller.recordingWaitCount, 1u);
    controller.historyCompletion();
    XCTAssertEqual(controller.retryCount, 1u);
    XCTAssertEqual(controller.replies.count, 0u);
    controller.retryCompletion(YES);
    XCTAssertEqualObjects(controller.replies, (@[@YES]));
    [controller finishTerminationAfterRecordings];
    XCTAssertEqual(controller.recordingWaitCount, 1u, @"A late stop/quit callback after YES must be idempotent");
    controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
}
- (void)testQuitWaitsForFreshRecoveryScanAndRepeatedQuitDoesNotReadmitBarriers {
    ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
    controller.deferRecoveryScan = YES;
    [controller finishTerminationAfterRecordings];
    controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(YES);
    XCTAssertEqual(controller.recoveryScans, 1u); XCTAssertEqual(controller.replies.count, 0u);
    [controller finishTerminationAfterRecordings];
    XCTAssertEqual([controller applicationShouldTerminate:nil], NSTerminateLater);
    XCTAssertEqual(controller.recordingWaitCount, 1u); XCTAssertEqual(controller.recoveryScans, 1u);
    void (^scan)(BOOL, NSArray *, NSError *) = controller.scanCompletion;
    scan(YES, @[], nil); scan(YES, @[], nil);
    XCTAssertEqualObjects(controller.replies, (@[@YES]));
    XCTAssertEqual([controller applicationShouldTerminate:nil], NSTerminateNow);
    controller.scanCompletion = nil; controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
}
- (void)testSupersededRecoveryScanRetriesDiscoveryWithoutRepeatingPersistenceDrains {
    ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
    controller.deferRecoveryScan = YES;
    [controller finishTerminationAfterRecordings];
    controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(YES);
    controller.scanCompletion(NO, @[], nil);
    XCTAssertEqual(controller.recoveryScans, 2u); XCTAssertEqual(controller.recordingWaitCount, 1u);
    XCTAssertEqual(controller.historyWaitCount, 1u); XCTAssertEqual(controller.retryCount, 1u); XCTAssertEqual(controller.replies.count, 0u);
    controller.scanCompletion(YES, @[], nil); XCTAssertEqualObjects(controller.replies, (@[@YES]));
    controller.scanCompletion = nil; controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
}
- (void)testCancelledQuitScanCannotReplyDuringANewerQuitAttempt {
    ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
    controller.deferRecoveryScan = YES; controller.allowQuitWithScanError = NO;
    [controller finishTerminationAfterRecordings];
    controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(YES);
    void (^oldScan)(BOOL, NSArray *, NSError *) = controller.scanCompletion;
    oldScan(YES, @[], [NSError errorWithDomain:NSPOSIXErrorDomain code:5 userInfo:nil]);
    XCTAssertEqualObjects(controller.replies, (@[@NO]));
    [controller.replies removeAllObjects]; [controller setValue:@YES forKey:@"terminating"];
    [controller finishTerminationAfterRecordings];
    oldScan(YES, @[], nil);
    XCTAssertEqual(controller.replies.count, 0u); XCTAssertEqual(controller.recordingWaitCount, 2u);
    controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(YES);
    controller.scanCompletion(YES, @[], nil); XCTAssertEqualObjects(controller.replies, (@[@YES]));
    controller.scanCompletion = nil; controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
}
- (void)testRecoveryScanFailureHasAnExplicitKeepOrStayDecision {
    for (NSNumber *allow in @[@YES, @NO]) {
        ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
        controller.recoveryScanError = [NSError errorWithDomain:NSPOSIXErrorDomain code:5 userInfo:nil];
        controller.allowQuitWithScanError = allow.boolValue;
        [controller finishTerminationAfterRecordings];
        controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(YES);
        XCTAssertEqualObjects(controller.replies, (@[allow])); XCTAssertEqual(controller.scanWarnings, 1u);
        XCTAssertEqual(controller.recordingConfirmations, 0u); XCTAssertEqual(controller.historyWarnings, 0u);
        XCTAssertEqual([[controller valueForKey:@"terminating"] boolValue], allow.boolValue);
        controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
    }
}
- (void)testHistoryFailureCancelsQuitAndWarnsEvenWithRecordingRecoveryJobs {
    ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
    controller.jobs = @[@{@"synthetic": @YES}];
    [controller finishTerminationAfterRecordings];
    controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(NO);
    XCTAssertEqualObjects(controller.replies, (@[@NO]));
    XCTAssertEqual(controller.historyWarnings, 1u);
    XCTAssertEqual(controller.recordingConfirmations, 0u);
    XCTAssertFalse([[controller valueForKey:@"terminating"] boolValue]);
    controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
}
- (void)testStayOpenForDurableRecordingRecoveryCancelsWithoutHistoryWarning {
    ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
    controller.jobs = @[@{@"synthetic": @YES}]; controller.allowQuitWithRecovery = NO;
    [controller finishTerminationAfterRecordings];
    controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(YES);
    XCTAssertEqualObjects(controller.replies, (@[@NO]));
    XCTAssertEqual(controller.recordingConfirmations, 1u);
    XCTAssertEqual(controller.historyWarnings, 0u);
    controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
}
- (void)testExplicitKeepFilesAndQuitPermitsTerminationAfterSuccessfulHistory {
    ControlledTerminationController *controller = [[ControlledTerminationController alloc] initForRegression];
    controller.jobs = @[@{@"synthetic": @YES}];
    [controller finishTerminationAfterRecordings];
    controller.recordingCompletion(); controller.historyCompletion(); controller.retryCompletion(YES);
    XCTAssertEqualObjects(controller.replies, (@[@YES]));
    XCTAssertEqual(controller.recordingConfirmations, 1u);
    controller.recordingCompletion = nil; controller.historyCompletion = nil; controller.retryCompletion = nil;
}
@end

// Actual AppController network/restart state machine with only its collaborators
// replaced. Neither this subclass initializer nor the settings source accesses
// normal app startup, user defaults, SIP accounts or a native agent.
@interface InMemoryRestartSettings: NSObject
@property(nonatomic) NSInteger port;
@property(nonatomic) BOOL ice;
@end
@implementation InMemoryRestartSettings
- (NSInteger)integerForKey:(NSString *)key { return [key isEqual:@"TransportPort"] ? self.port : 0; }
- (NSString *)stringForKey:(NSString *)key { return @""; }
- (BOOL)boolForKey:(NSString *)key { return [key isEqual:@"UseICE"] && self.ice; }
@end
@interface InertNetworkAgent: NSObject
@property(nonatomic) AKSIPUserAgentState state;
@property(nonatomic) NSUInteger transportPort, STUNServerPort, outboundProxyPort;
@property(nonatomic) BOOL usesICE;
@property(nonatomic, copy) NSString *STUNServerHost, *outboundProxyHost;
@property(nonatomic) NSArray *nameServers;
@property(nonatomic) NSUInteger consumedPort;
@property(nonatomic) BOOL consumedICE;
@end
@implementation InertNetworkAgent
- (BOOL)isStarted { return self.state == AKSIPUserAgentStateStarted; }
@end
@interface InertRestartAccount: NSObject
@end
@implementation InertRestartAccount
- (BOOL)shouldPresentRegistrationError { return NO; }
@end
@interface InertRestartAccounts: NSObject
@property(nonatomic) NSUInteger registrations;
@end
@implementation InertRestartAccounts
- (NSArray *)enabled { return @[[InertRestartAccount new]]; }
- (void)registerAllAccounts { self.registrations++; }
@end
@interface InertRestartUseCase: NSObject
@property(nonatomic) InertNetworkAgent *agent;
@property(nonatomic) NSUInteger starts;
@end
@implementation InertRestartUseCase
- (void)execute {
    self.starts++;
    self.agent.consumedPort = self.agent.transportPort;
    self.agent.consumedICE = self.agent.usesICE;
    self.agent.state = AKSIPUserAgentStateStarting;
}
@end
@interface ControlledNetworkController: AppController
@property(nonatomic) InMemoryRestartSettings *settings;
@property(nonatomic) InertNetworkAgent *agent;
@property(nonatomic) InertRestartAccounts *accounts;
@property(nonatomic) InertRestartUseCase *startUseCase;
@property(nonatomic) NSUInteger stops;
- (instancetype)initForNetworkRegression;
@end
@implementation ControlledNetworkController
- (instancetype)initForNetworkRegression {
    _settings = [InMemoryRestartSettings new]; _settings.port = 19080; _settings.ice = YES;
    _agent = [InertNetworkAgent new]; _agent.transportPort = 15060; _agent.consumedPort = 15060;
    _accounts = [InertRestartAccounts new];
    _startUseCase = [InertRestartUseCase new]; _startUseCase.agent = _agent;
    return self;
}
- (NSUserDefaults *)networkSettingsDefaults { return (id)self.settings; }
- (AKSIPUserAgent *)userAgent { return (id)self.agent; }
- (id)accountControllers { return self.accounts; }
- (id)userAgentStart { return self.startUseCase; }
- (void)stopUserAgent { self.stops++; self.agent.state = AKSIPUserAgentStateStopping; }
@end
@interface NetworkRestartRegressionTests: XCTestCase
@end
@implementation NetworkRestartRegressionTests
- (void)testSavingDuringStartupRestartsOnceWithLatestSavedValues {
    ControlledNetworkController *controller = [[ControlledNetworkController alloc] initForNetworkRegression];
    controller.agent.state = AKSIPUserAgentStateStarting;
    [controller preferencesControllerDidChangeNetworkSettings:nil];
    XCTAssertEqual(controller.agent.transportPort, 19080u);
    XCTAssertTrue(controller.agent.usesICE);
    XCTAssertEqual(controller.agent.consumedPort, 15060u);
    XCTAssertEqual(controller.stops, 0u);
    XCTAssertTrue([[controller valueForKey:@"pendingNetworkRestart"] boolValue]);
    controller.settings.port = 19081; controller.settings.ice = NO;
    [controller preferencesControllerDidChangeNetworkSettings:nil];
    controller.agent.state = AKSIPUserAgentStateStarted;
    [controller SIPUserAgentDidFinishStarting:nil];
    XCTAssertEqual(controller.stops, 1u);
    XCTAssertEqual(controller.accounts.registrations, 0u);
    XCTAssertFalse([[controller valueForKey:@"pendingNetworkRestart"] boolValue]);
    controller.agent.state = AKSIPUserAgentStateStopped;
    [controller SIPUserAgentDidFinishStopping:nil];
    XCTAssertEqual(controller.startUseCase.starts, 1u);
    XCTAssertEqual(controller.agent.consumedPort, 19081u);
    XCTAssertFalse(controller.agent.consumedICE);
    controller.agent.state = AKSIPUserAgentStateStarted;
    [controller SIPUserAgentDidFinishStarting:nil];
    XCTAssertEqual(controller.stops, 1u);
    XCTAssertEqual(controller.accounts.registrations, 1u);
}
- (void)testFailedStartupDoesNotLoopOrLeaveAnObsoleteRestartIntent {
    ControlledNetworkController *controller = [[ControlledNetworkController alloc] initForNetworkRegression];
    controller.agent.state = AKSIPUserAgentStateStarting;
    [controller preferencesControllerDidChangeNetworkSettings:nil];
    controller.agent.state = AKSIPUserAgentStateStopped;
    // The alert presentation itself is separate native UI; suppress only that
    // flag while executing the actual failed-start completion state logic.
    [controller setValue:@NO forKey:@"shouldPresentUserAgentLaunchError"];
    [controller SIPUserAgentDidFinishStarting:nil];
    XCTAssertEqual(controller.stops, 0u);
    XCTAssertEqual(controller.startUseCase.starts, 0u);
    XCTAssertFalse([[controller valueForKey:@"shouldRegisterAllAccounts"] boolValue]);
    XCTAssertFalse([[controller valueForKey:@"pendingNetworkRestart"] boolValue]);
}
- (void)testSavingDuringStoppingDefersOneStartWithUpdatedConfiguration {
    ControlledNetworkController *controller = [[ControlledNetworkController alloc] initForNetworkRegression];
    controller.agent.state = AKSIPUserAgentStateStopping;
    [controller preferencesControllerDidChangeNetworkSettings:nil];
    XCTAssertEqual(controller.stops, 0u);
    XCTAssertEqual(controller.startUseCase.starts, 0u);
    controller.agent.state = AKSIPUserAgentStateStopped;
    [controller SIPUserAgentDidFinishStopping:nil];
    XCTAssertEqual(controller.startUseCase.starts, 1u);
    XCTAssertEqual(controller.agent.consumedPort, 19080u);
    XCTAssertTrue(controller.agent.consumedICE);
    XCTAssertFalse([[controller valueForKey:@"pendingNetworkRestart"] boolValue]);
}
- (void)testStoppedSaveUpdatesFutureConfigurationWithoutStartingAgent {
    ControlledNetworkController *controller = [[ControlledNetworkController alloc] initForNetworkRegression];
    controller.agent.state = AKSIPUserAgentStateStopped;
    [controller preferencesControllerDidChangeNetworkSettings:nil];
    XCTAssertEqual(controller.agent.transportPort, 19080u);
    XCTAssertEqual(controller.stops, 0u); XCTAssertEqual(controller.startUseCase.starts, 0u);
    XCTAssertFalse([[controller valueForKey:@"pendingNetworkRestart"] boolValue]);
}
- (void)testStartedSaveStopsOnceAndTerminationSaveNeverRestarts {
    ControlledNetworkController *controller = [[ControlledNetworkController alloc] initForNetworkRegression];
    controller.agent.state = AKSIPUserAgentStateStarted;
    [controller preferencesControllerDidChangeNetworkSettings:nil];
    XCTAssertEqual(controller.stops, 1u);
    XCTAssertTrue([[controller valueForKey:@"shouldRegisterAllAccounts"] boolValue]);
    ControlledNetworkController *terminating = [[ControlledNetworkController alloc] initForNetworkRegression];
    terminating.agent.state = AKSIPUserAgentStateStarting;
    [terminating setValue:@YES forKey:@"terminating"];
    [terminating preferencesControllerDidChangeNetworkSettings:nil];
    XCTAssertEqual(terminating.agent.transportPort, 19080u);
    XCTAssertEqual(terminating.stops, 0u); XCTAssertEqual(terminating.startUseCase.starts, 0u);
    XCTAssertFalse([[terminating valueForKey:@"pendingNetworkRestart"] boolValue]);
}
@end
