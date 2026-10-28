//
//  CallControllerLifecycleTests.m
//  TelephoneTests
//

#import <XCTest/XCTest.h>

#import "AKSIPCall.h"
#import "AKStereoRecording.h"
#import "CallController.h"
#import "AccountController.h"

@interface AKStoppedRecordingCallStub : AKSIPCall
@end

#import "AuthenticationFailureController.h"
@interface AuthenticationFailureController (AsyncRetryTests)
- (void)presentCredentialError:(NSString *)message field:(NSTextField *)field;
@end
@interface AKAsyncAuthenticationAgent : NSObject
@property(nonatomic) NSUInteger adds, removals;
@property(nonatomic,copy) void (^addCompletion)(BOOL);
- (void)addAccount:(AKSIPAccount *)account withPassword:(NSString *)password completion:(void (^)(BOOL))completion;
- (void)removeAccount:(AKSIPAccount *)account completion:(void (^)(BOOL))completion;
@end
@implementation AKAsyncAuthenticationAgent
- (void)addAccount:(AKSIPAccount *)account withPassword:(NSString *)password completion:(void (^)(BOOL))completion { self.adds++; self.addCompletion=completion; }
- (void)removeAccount:(AKSIPAccount *)account completion:(void (^)(BOOL))completion { self.removals++; completion(YES); }
@end
@interface AKAsyncAuthenticationAccountController : AccountController
@property(nonatomic) NSUInteger removals, connecting, unavailable;
@property(nonatomic,copy) void (^removeCompletion)(BOOL);
@end
@implementation AKAsyncAuthenticationAccountController
- (void)removeAccountFromUserAgentWithCompletion:(void (^)(BOOL))completion { [self invalidateCredentialAccess]; self.removals++; self.removeCompletion=completion; }
- (void)showConnectingState { self.connecting++; }
- (void)showUnavailableState { self.unavailable++; }
@end
@interface AKAsyncAuthenticationController : AuthenticationFailureController
@property(nonatomic) NSUInteger dismissals, errors, saves;
@end
@implementation AKAsyncAuthenticationController
- (BOOL)savePassword:(NSString *)password service:(NSString *)service account:(NSString *)account error:(NSError **)error {
    self.saves++; return YES; // Synthetic boundary even if a stale-sheet guard regresses.
}
- (void)closeSheet:(id)sender { self.dismissals++; }
- (void)presentCredentialError:(NSString *)message field:(NSTextField *)field { self.errors++; }
@end
@interface AuthenticationAsyncRetryRepairTests : XCTestCase
@property(nonatomic) AKAsyncAuthenticationAccountController *owner;
@property(nonatomic) AKAsyncAuthenticationAgent *agent;
@property(nonatomic) AKAsyncAuthenticationController *sheet;
@property(nonatomic) NSArray *retainedControls;
@end
@implementation AuthenticationAsyncRetryRepairTests
- (void)setUp {
    [super setUp];
    AKSIPAccount *account=[[AKSIPAccount alloc] initWithDictionary:@{@"UUID":NSUUID.UUID.UUIDString,@"FullName":@"Synthetic",@"Realm":@"*",@"Username":@"old",@"Domain":@"example.invalid"} parser:nil];
    self.owner=[AKAsyncAuthenticationAccountController new];
    [self.owner setValue:account forKey:@"account"]; [self.owner setValue:@YES forKey:@"_enabled"];
    self.agent=[AKAsyncAuthenticationAgent new];
    self.sheet=[[AKAsyncAuthenticationController alloc] initWithAccountController:self.owner userAgent:(id)self.agent];
    NSTextField *username=[NSTextField new], *password=[NSTextField new]; NSButton *save=[NSButton new];
    username.stringValue=@" new "; password.stringValue=@"synthetic-only"; save.state=NSControlStateValueOff;
    self.retainedControls=@[username,password,save]; self.sheet.usernameField=username; self.sheet.passwordField=password; self.sheet.mustSaveCheckBox=save;
}
- (void)testRetryWaitsForDeleteThenNativeAddAndDoesNotUseOldRegistrationSnapshot {
    [self.sheet changeUsernameAndPassword:nil];
    XCTAssertEqual(self.owner.removals,1u); XCTAssertEqual(self.agent.adds,0u); XCTAssertEqualObjects(self.owner.account.username,@"old");
    [self.sheet changeUsernameAndPassword:nil]; XCTAssertEqual(self.owner.removals,1u);
    self.owner.removeCompletion(YES);
    XCTAssertEqual(self.agent.adds,1u); XCTAssertEqualObjects(self.owner.account.username,@"new"); XCTAssertEqual(self.sheet.dismissals,0u);
    self.agent.addCompletion(YES);
    XCTAssertEqual(self.sheet.dismissals,1u); XCTAssertEqual(self.sheet.errors,0u); XCTAssertEqual(self.owner.unavailable,0u);
    XCTAssertEqualObjects(self.sheet.passwordField.stringValue,@"");
}
- (void)testRejectedDeleteRetainsRetryFieldsAndDoesNotAdd {
    [self.sheet changeUsernameAndPassword:nil]; self.owner.removeCompletion(NO);
    XCTAssertEqual(self.agent.adds,0u); XCTAssertEqual(self.sheet.errors,1u); XCTAssertEqual(self.sheet.dismissals,0u);
    XCTAssertEqualObjects(self.owner.account.username,@"old"); XCTAssertEqualObjects(self.sheet.passwordField.stringValue,@"synthetic-only");
}
- (void)testRejectedAddRetainsSheetAndAllowsRetry {
    [self.sheet changeUsernameAndPassword:nil]; self.owner.removeCompletion(YES); self.agent.addCompletion(NO);
    XCTAssertEqual(self.sheet.errors,1u); XCTAssertEqual(self.sheet.dismissals,0u); XCTAssertEqual(self.owner.unavailable,1u);
    [self.sheet changeUsernameAndPassword:nil]; XCTAssertEqual(self.owner.removals,2u);
}
- (void)testOldRemovalCompletionCannotUnlockNewerRetry {
    [self.sheet changeUsernameAndPassword:nil];
    void (^oldCompletion)(BOOL) = self.owner.removeCompletion;
    [self.sheet prepareWithUsername:@"new" password:@"synthetic-second"];
    [self.sheet changeUsernameAndPassword:nil];
    oldCompletion(YES);
    XCTAssertTrue([[self.sheet valueForKey:@"retryPending"] boolValue]);
    [self.sheet changeUsernameAndPassword:nil];
    XCTAssertEqual(self.owner.removals, 2u); XCTAssertEqual(self.agent.adds, 0u);
}
- (void)testOldAddCompletionCannotUnlockOrRemoveNewerRetry {
    [self.sheet changeUsernameAndPassword:nil]; self.owner.removeCompletion(YES);
    void (^oldCompletion)(BOOL) = self.agent.addCompletion;
    [self.sheet prepareWithUsername:@"new" password:@"synthetic-second"];
    [self.sheet changeUsernameAndPassword:nil];
    oldCompletion(YES);
    XCTAssertTrue([[self.sheet valueForKey:@"retryPending"] boolValue]);
    [self.sheet changeUsernameAndPassword:nil];
    XCTAssertEqual(self.owner.removals, 2u); XCTAssertEqual(self.agent.removals, 0u);
}
- (void)testInvalidatedSheetCannotWriteOrReconnect {
    self.sheet.mustSaveCheckBox.state = NSControlStateValueOn;
    [self.owner setCredentialAccessSuspended:YES];
    [self.sheet changeUsernameAndPassword:nil];
    XCTAssertEqual(self.owner.removals, 0u); XCTAssertEqual(self.agent.adds, 0u); XCTAssertEqual(self.sheet.saves, 0u);
    XCTAssertEqual(self.sheet.errors, 1u);
}
- (void)testDisablingAccountWhileDeleteIsPendingCancelsRetry {
    [self.sheet changeUsernameAndPassword:nil]; [self.owner setValue:@NO forKey:@"_enabled"]; self.owner.removeCompletion(YES);
    XCTAssertEqual(self.agent.adds,0u); XCTAssertEqual(self.sheet.dismissals,0u); XCTAssertEqualObjects(self.owner.account.username,@"old");
}
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
- (BOOL)persistRecordingRecoveryJobAtDirectory:(NSURL *)directory localURL:(NSURL *)local
                                    remoteURL:(NSURL *)remote destinationURL:(NSURL *)destination error:(NSError **)error;
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
@property(nonatomic) BOOL manifestFails;
@property(nonatomic) NSUInteger nativeStops;
@property(nonatomic, copy) void (^pendingCompletion)(BOOL);
@property(nonatomic, strong) NSURL *testDirectory;
@property(nonatomic, strong) NSURL *testRoot;
- (void)complete:(BOOL)succeeded;
@end
@implementation AKDeferredRecordingCall
- (BOOL)isRecording { return self.recordingActive; }
- (BOOL)requiresSIPControlThread { return NO; }
- (BOOL)startRecordingToURL:(NSURL *)URL {
    if (self.setupFails) return NO;
    self.testRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                                    isDirectory:YES];
    NSError *error = nil;
    self.testDirectory = AKCreateRecordingRecoveryDirectoryAtRoot(self.testRoot, &error);
    AKRecordingJobOwnership *ownership = self.testDirectory ? AKClaimRecordingJob(self.testDirectory, &error) : nil;
    NSURL *local = [self.testDirectory URLByAppendingPathComponent:@"local.wav"];
    NSURL *remote = [self.testDirectory URLByAppendingPathComponent:@"remote.wav"];
    NSData *raw = [@"Synthetic held capture" dataUsingEncoding:NSUTF8StringEncoding];
    if (!ownership || !AKPersistOwnedRecordingRecoveryJob(ownership, local, remote, URL,
                                                         AKRecordingJobPhaseCapturing, &error) ||
        ![raw writeToURL:local atomically:YES] || ![raw writeToURL:remote atomically:YES]) {
        if (ownership) AKDiscardRecordingRecoveryJob(ownership);
        return NO;
    }
    self.recordingActive = YES;
    [self setValue:ownership forKey:@"recordingJobOwnership"];
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
- (BOOL)persistRecordingRecoveryJobAtDirectory:(NSURL *)directory localURL:(NSURL *)local remoteURL:(NSURL *)remote destinationURL:(NSURL *)destination error:(NSError **)error {
    return !self.manifestFails && [super persistRecordingRecoveryJobAtDirectory:directory localURL:local
                                                                   remoteURL:remote destinationURL:destination error:error];
}
- (void)complete:(BOOL)succeeded {
    void (^completion)(BOOL) = self.pendingCompletion;
    self.pendingCompletion = nil;
    if (completion) completion(succeeded);
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
- (void)drainFinalizations {
    XCTestExpectation *drained = [self expectationWithDescription:@"recording cleanup drained"];
    AKWaitForPendingRecordingFinalizations(^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:3];
}
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
    [self drainFinalizations];
    XCTAssertEqual(scope.releases, 1u);
    [(firstCallFirst ? b : a) complete:NO]; // Failed conversion must also release.
    [self drainFinalizations];
    XCTAssertEqual(scope.releases, 2u);
    [NSFileManager.defaultManager removeItemAtURL:a.testRoot error:nil];
    [NSFileManager.defaultManager removeItemAtURL:b.testRoot error:nil];
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
    XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.testRoot).count, 0u);
    XCTAssertEqual(scope.releases, 0u);
    XCTAssertNil(call.pendingCompletion);
    call.nativeStopFails = NO;
    [call stopRecording];
    [call complete:YES];
    [self drainFinalizations];
    XCTAssertEqual(scope.releases, 1u);
    [NSFileManager.defaultManager removeItemAtURL:call.testRoot error:nil];
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
    [self drainFinalizations];
    XCTAssertEqual(scope.releases, 2u);
    [NSFileManager.defaultManager removeItemAtURL:a.testRoot error:nil];
    [NSFileManager.defaultManager removeItemAtURL:b.testRoot error:nil];
}

- (void)testCaptureAndHeldEncoderCompletionStayOutOfRecovery {
    AKDeferredRecordingCall *call = [[AKDeferredRecordingCall alloc] init];
    NSURL *destination = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                               [NSUUID.UUID.UUIDString stringByAppendingString:@".wav"]]];
    XCTAssertTrue([call startRecordingToURL:destination]);
    NSURL *local = [call.testDirectory URLByAppendingPathComponent:@"local.wav"];
    NSURL *remote = [call.testDirectory URLByAppendingPathComponent:@"remote.wav"];
    NSData *original = [NSData dataWithContentsOfURL:local];
    NSDictionary *staleJob = @{@"directoryURL": call.testDirectory, @"localURL": local,
                               @"remoteURL": remote, @"destinationURL": destination};
    __block NSUInteger failureNotifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKRecordingExportDidFailNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) { failureNotifications++; }];
    for (NSUInteger phase = 0; phase < 2; phase++) {
        XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.testRoot).count, 0u);
        XCTestExpectation *rejected = [self expectationWithDescription:@"Owned recovery rejected on main"];
        __block BOOL returned = NO;
        AKRetryRecordingRecoveryJob(staleJob, destination, ^(BOOL succeeded) {
            XCTAssertTrue(NSThread.isMainThread);
            XCTAssertFalse(succeeded);
            XCTAssertTrue(returned);
            [rejected fulfill];
        });
        returned = YES;
        [self waitForExpectations:@[rejected] timeout:2];
        XCTAssertEqual(failureNotifications, 0u);
        XCTAssertEqualObjects([NSData dataWithContentsOfURL:local], original);
        if (phase == 0) {
            [call stopRecording];
            XCTAssertFalse(call.isRecording);
            XCTAssertNotNil(call.pendingCompletion); // Encoder completion is explicitly held.
            NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfURL:
                                      [call.testDirectory URLByAppendingPathComponent:@"recovery.plist"]];
            XCTAssertEqualObjects(manifest[@"state"], @"finalising");
        }
    }
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [call complete:NO];
    [self drainFinalizations];
    XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.testRoot).count, 1u);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:local], original);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:remote.path]);
    [NSFileManager.defaultManager removeItemAtURL:call.testRoot error:nil];
}

- (void)testEarlierCompletedOwnerCannotRemoveANewerRecoveryClaim {
    AKDeferredRecordingCall *call = [[AKDeferredRecordingCall alloc] init];
    XCTAssertTrue([call startRecordingToURL:[NSURL fileURLWithPath:@"/unused/ownership.wav"]]);
    AKRecordingJobOwnership *earlier = [call valueForKey:@"recordingJobOwnership"];
    [call stopRecording];
    [call complete:NO];
    [self drainFinalizations];
    AKRecordingJobOwnership *current = AKClaimRecordingJob(call.testDirectory, nil);
    XCTAssertNotNil(current);
    AKFinishRecordingRecoveryJob(earlier, YES);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:
                   [call.testDirectory URLByAppendingPathComponent:@"local.wav"].path]);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.testRoot).count, 0u);
    AKFinishRecordingRecoveryJob(current, NO);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.testRoot).count, 1u);
    [NSFileManager.defaultManager removeItemAtURL:call.testRoot error:nil];
}

- (void)testFinalisationManifestFailureRetainsRawAndReleasesTheClaim {
    AKDeferredRecordingCall *call = [[AKDeferredRecordingCall alloc] init];
    AKScopeReleaseSpy *scope = [[AKScopeReleaseSpy alloc] init];
    XCTAssertTrue([call startRecordingToURL:[NSURL fileURLWithPath:@"/unused/manifest.wav"]
                       accessedDirectoryURL:(NSURL *)scope]);
    call.manifestFails = YES;
    __block BOOL failed = NO;
    [call stopRecordingWithCompletion:^(BOOL succeeded) { failed = !succeeded; }];
    [self drainFinalizations];
    XCTAssertTrue(failed);
    XCTAssertEqual(scope.releases, 1u);
    XCTAssertNil(call.pendingCompletion);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.testRoot).count, 1u);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:
                   [call.testDirectory URLByAppendingPathComponent:@"local.wav"].path]);
    [NSFileManager.defaultManager removeItemAtURL:call.testRoot error:nil];
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
#import "SharedDialerController.h"
#import "AccountControllers.h"

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
@property(nonatomic) BOOL rejectsHangUp;
@property(nonatomic) BOOL rejectsHold;
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
- (void)requestHangUpWithCompletion:(void (^)(BOOL))completion { self.hangups++; completion(!self.rejectsHangUp); }
- (void)requestToggleHoldWithCompletion:(void (^)(BOOL))completion { if (!self.rejectsHold) self.localHeld = !self.localHeld; completion(!self.rejectsHold); }
- (void)stopRecording { self.recordingStops++; }
- (void)toggleMicrophoneMute { self.muted = !self.muted; }
- (void)requestToggleMicrophoneMuteWithCompletion:(void (^)(BOOL))completion { self.muted = !self.muted; completion(YES); }
- (void)toggleHold { self.localHeld = !self.localHeld; }
- (void)sendDTMFDigits:(NSString *)digits { [self.sentDigits appendString:digits]; }
@end

@interface AKCompactCallController : CallController
@end

@interface AKDeferredHangupCall : AKCompactCallFixture
@property(nonatomic,copy) void (^hangupCompletion)(BOOL);
@end
@implementation AKDeferredHangupCall
- (void)requestHangUpWithCompletion:(void (^)(BOOL))completion { self.hangups++; self.hangupCompletion=completion; }
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
- (BOOL)windowShouldClose:(NSWindow *)window;
@end

@interface CompactCallCardTests : XCTestCase
@property(nonatomic) AKCompactCallController *controller;
@property(nonatomic) AKCompactCallFixture *call;
@property(nonatomic) AKCompactAccountFixture *account;
@property(nonatomic) NSUserDefaults *defaults;
@property(nonatomic) NSString *defaultsSuite;
@property(nonatomic) SharedDialerController *referenceDialler;
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
    [self.referenceDialler.window close]; self.referenceDialler = nil;
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
- (SharedDialerController *)defaultDiallerReference {
    if (!self.referenceDialler) {
        // Nil factory means no saved-frame restoration, history loading or
        // provider composition; the reference is the real native dialler.
        self.referenceDialler = [[SharedDialerController alloc] initWithAccounts:[AccountControllers new] historyFactory:nil];
    }
    return self.referenceDialler;
}
- (void)assertDefaultFootprint {
    NSWindow *reference = self.defaultDiallerReference.window;
    XCTAssertEqualWithAccuracy(reference.contentView.bounds.size.width, 368, 0.1);
    XCTAssertEqualWithAccuracy(reference.contentView.bounds.size.height, 104, 0.1);
    XCTAssertEqualWithAccuracy(self.controller.window.frame.size.width, reference.frame.size.width, 0.1);
    XCTAssertEqualWithAccuracy(self.controller.window.frame.size.height, reference.frame.size.height, 0.1);
}
- (void)assertCompactView:(NSView *)view actionCount:(NSUInteger)count {
    [self.controller.window.contentView layoutSubtreeIfNeeded];
    [self assertDefaultFootprint];
    NSSize compact = JPSCompactDiallerContentSize();
    XCTAssertEqualWithAccuracy(view.frame.size.width, compact.width, 0.1);
    XCTAssertEqualWithAccuracy(view.frame.size.height, compact.height, 0.1);
    XCTAssertEqualWithAccuracy(self.controller.window.contentView.frame.size.height, compact.height, 0.1);
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
        XCTAssertTrue([(AKWindowMaterialView *)child usesOpaqueTitlebarBackground]);
        XCTAssertLessThan([root.subviews indexOfObjectIdenticalTo:child], paneIndex,
                          @"Window backdrop must remain behind the current call pane");
    }
    XCTAssertEqual(backdropCount, 1u);
    XCTAssertFalse(self.controller.window.titlebarAppearsTransparent);
    XCTAssertEqual(self.controller.window.titleVisibility, NSWindowTitleVisible);
    XCTAssertEqualWithAccuracy(self.controller.window.backgroundColor.alphaComponent, 1, 0.01);
    XCTAssertEqualObjects(self.controller.window.backgroundColor, NSColor.windowBackgroundColor);
    XCTAssertEqual(self.controller.window.isOpaque,
                   NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency);
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
- (void)testLongErrorRetainsFootprintAndFullAccessibleStatus {
    [self.controller showActiveCallView];
    NSRect original = self.controller.window.frame;
    self.controller.status = @"The remote telephone could not be reached. Please check the number and try the call again.";
    [self.controller.window.contentView layoutSubtreeIfNeeded];
    NSView *view = self.controller.activeCallViewController.view;
    NSTextField *status = [self.controller.activeCallViewController valueForKey:@"statusField"];
    [self assertCompactView:view actionCount:5];
    XCTAssertEqualWithAccuracy(self.controller.window.frame.size.height, original.size.height, 0.1);
    XCTAssertEqualWithAccuracy(self.controller.window.frame.size.width, original.size.width, 0.1);
    XCTAssertTrue(NSContainsRect(view.bounds, [status convertRect:status.bounds toView:view]));
    XCTAssertEqual(status.maximumNumberOfLines, 1);
    XCTAssertEqual(status.lineBreakMode, NSLineBreakByTruncatingTail);
    XCTAssertEqualObjects(status.stringValue, self.controller.status);
    XCTAssertEqualObjects(status.toolTip, self.controller.status);
    XCTAssertEqualObjects(status.accessibilityValue, self.controller.status);
    for (NSView *child in view.subviews) if ([child isKindOfClass:AKGlassControlContainer.class]) {
        XCTAssertFalse(NSIntersectsRect([status convertRect:status.bounds toView:view], child.frame));
    }
    self.controller.status = @"00:12";
    [self assertCompactView:view actionCount:5];
}
- (void)testInitialAndSavedLegacyWindowUseDiallerFootprintBeforeFirstCallPane {
    [self assertDefaultFootprint];
    NSUserDefaults *isolatedDefaults = NSUserDefaults.standardUserDefaults;
    NSString *key = @"NSWindow Frame Call";
    id previous = [isolatedDefaults objectForKey:key];
    NSWindow *legacy = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 120, 300, 112)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    legacy.releasedWhenClosed = NO;
    AKCompactCallController *restored;
    @try {
        // The unique-identity nib-free host owns this registration-domain test
        // state. Never run against the production application profile.
        [legacy saveFrameUsingName:@"Call"];
        restored = [[AKCompactCallController alloc] initWithWindowNibName:@"Call"
            accountController:(id)self.account userAgent:nil delegate:nil];
        [restored setValue:self.defaults forKey:@"defaults"];
        NSWindow *window = restored.window;
        XCTAssertEqualWithAccuracy(window.frame.size.width, self.defaultDiallerReference.window.frame.size.width, 0.1);
        XCTAssertEqualWithAccuracy(window.frame.size.height, self.defaultDiallerReference.window.frame.size.height, 0.1);
        window.frameAutosaveName = @"";
        [window close];
    } @finally {
        [legacy close];
        if (previous) [isolatedDefaults setObject:previous forKey:key]; else [isolatedDefaults removeObjectForKey:key];
    }
}
- (void)testCallPhasesRetainSameOuterFrameAwayFromScreenEdges {
    NSScreen *screen = NSScreen.mainScreen;
    XCTAssertNotNil(screen);
    [self.controller showActiveCallView];
    NSRect visible = screen.visibleFrame;
    [self.controller.window setFrameOrigin:NSMakePoint(NSMidX(visible) - 184, NSMidY(visible) - 80)];
    NSRect original = self.controller.window.frame;
    for (NSNumber *state in @[@(kAKSIPCallCallingState), @(kAKSIPCallConnectingState), @(kAKSIPCallIncomingState),
                             @(kAKSIPCallConfirmedState), @(kAKSIPCallDisconnectedState)]) {
        self.call.state = state.unsignedIntegerValue;
        if (self.call.state == kAKSIPCallIncomingState) [self.controller showIncomingCallView];
        else if (self.call.state == kAKSIPCallDisconnectedState) [self.controller showEndedCallView];
        else [self.controller showActiveCallView];
        [self assertDefaultFootprint];
        XCTAssertEqualWithAccuracy(NSMinX(self.controller.window.frame), NSMinX(original), 0.1);
        XCTAssertEqualWithAccuracy(NSMaxY(self.controller.window.frame), NSMaxY(original), 0.1);
    }
}
- (void)testRecordingFeedbackAndLongDurationCannotResizeCall {
    [self.controller showActiveCallView];
    self.controller.callActive = YES;
    self.controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 3905;
    [self.controller setValue:[NSURL fileURLWithPath:@"/synthetic/call74/recordings"] forKey:@"recordingDestinationFolderURL"];
    for (NSNumber *state in @[@(AKCallRecordingStatusStarting), @(AKCallRecordingStatusFailed), @(AKCallRecordingStatusCapturing)]) {
        [self.controller setValue:state forKey:@"recordingStatus"];
        [self.controller.activeCallViewController refreshPresentation];
        [self assertCompactView:self.controller.activeCallViewController.view actionCount:5];
        NSTextField *duration = [self.controller.activeCallViewController valueForKey:@"durationField"];
        XCTAssertTrue(NSContainsRect(self.controller.activeCallViewController.view.bounds, duration.frame));
        XCTAssertEqualObjects(duration.stringValue, self.controller.presentationDuration);
    }
}
- (NSImage *)cachedWindowFrame:(NSWindow *)window {
    NSView *frame = window.contentView.superview;
    [frame layoutSubtreeIfNeeded]; [window displayIfNeeded]; [frame displayIfNeeded];
    NSBitmapImageRep *bitmap = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    XCTAssertNotNil(bitmap);
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:bitmap];
    return [[NSImage alloc] initWithData:bitmap.TIFFRepresentation];
}
- (void)attachDiallerAndCallForState:(NSString *)state appearance:(NSString *)appearance {
    NSWindow *dialler = self.defaultDiallerReference.window;
    [self assertDefaultFootprint];
    NSImage *left = [self cachedWindowFrame:dialler], *right = [self cachedWindowFrame:self.controller.window];
    CGFloat margin = 12, heading = 26;
    NSSize size = NSMakeSize(left.size.width + right.size.width + margin * 3, MAX(left.size.height, right.size.height) + heading + margin * 2);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [self.controller.window.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [NSColor.windowBackgroundColor setFill]; NSRectFill(NSMakeRect(0, 0, size.width, size.height));
        [left drawAtPoint:NSMakePoint(margin, margin) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        [right drawAtPoint:NSMakePoint(left.size.width + margin * 2, margin) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        NSDictionary *attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12], NSForegroundColorAttributeName:NSColor.labelColor};
        [@"Dialler" drawAtPoint:NSMakePoint(margin, size.height - heading) withAttributes:attributes];
        [state drawAtPoint:NSMakePoint(left.size.width + margin * 2, size.height - heading) withAttributes:attributes];
    }];
    [image unlockFocus];
    XCTAttachment *capture = [XCTAttachment attachmentWithImage:image];
    capture.name = [NSString stringWithFormat:@"call74-%@-%@", state, appearance];
    capture.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:capture];
    NSDictionary *geometry = @{@"state": state, @"appearance": appearance,
        @"diallerOuter": NSStringFromRect(dialler.frame), @"callOuter": NSStringFromRect(self.controller.window.frame),
        @"diallerContent": NSStringFromRect(dialler.contentView.bounds),
        @"callContent": NSStringFromRect(self.controller.window.contentView.bounds),
        @"callThemeFrame": NSStringFromRect(self.controller.window.contentView.superview.bounds),
        @"backingScale": @(self.controller.window.backingScaleFactor),
        @"scope": @"Real native nibs/window chrome and synthetic call snapshots only; no SIP, profile, Keychain or provider."};
    NSData *data = [NSJSONSerialization dataWithJSONObject:geometry options:NSJSONWritingPrettyPrinted error:nil];
    XCTAttachment *metadata = [XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
    metadata.name = [NSString stringWithFormat:@"call74-geometry-%@-%@", state, appearance];
    metadata.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:metadata];
}
- (void)testNativeSideBySideCallFootprintInBothAppearances {
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        self.controller.window.appearance = [NSAppearance appearanceNamed:appearance];
        self.defaultDiallerReference.window.appearance = self.controller.window.appearance;
        NSString *name = [appearance isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light";
        self.call.state = kAKSIPCallIncomingState; self.controller.status = @"Incoming call";
        [self.controller showIncomingCallView]; [self attachDiallerAndCallForState:@"incoming" appearance:name];
        self.call.state = kAKSIPCallCallingState; self.controller.status = @"Connecting…";
        [self.controller showActiveCallView]; [self attachDiallerAndCallForState:@"connecting" appearance:name];
        self.call.state = kAKSIPCallConfirmedState; self.controller.status = @"00:12";
        [self attachDiallerAndCallForState:@"active" appearance:name];
        [self.controller setValue:@(AKCallRecordingStatusFailed) forKey:@"recordingStatus"];
        self.controller.status = @"The remote telephone could not be reached. Please check the number and try the call again.";
        [self.controller.activeCallViewController refreshPresentation]; [self attachDiallerAndCallForState:@"long-status-recording" appearance:name];
        self.call.state = kAKSIPCallDisconnectedState; self.controller.status = @"Call ended";
        [self.controller showEndedCallView]; [self attachDiallerAndCallForState:@"ended" appearance:name];
    }
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
    XCTAssertEqualObjects(self.controller.displayedName, @"Alex Morgan");
    XCTAssertEqualObjects([[active valueForKey:@"keypadDigitsField"] stringValue], self.call.sentDigits);
    XCTAssertEqualObjects(self.controller.window.title, @"Personal");
    [active activeCallView:(AKActiveCallView *)active.view didReceiveText:@"invalid!"];
    XCTAssertEqualObjects(self.controller.displayedName, @"Alex Morgan");
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
    XCTAssertEqual(self.call.delegate, self.controller);
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

- (void)testDeadKeyDoesNotTransmitAndNormalDigitsStillDo {
    [self.controller showActiveCallView];
    AKActiveCallView *view = (id)self.controller.activeCallViewController.view;
    NSEvent *dead = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagOption
        timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"e" isARepeat:NO keyCode:14];
    XCTAssertNoThrow([view keyDown:dead]);
    XCTAssertEqualObjects(self.call.sentDigits, @"");
    [view insertText:@"5#ABCDR"];
    XCTAssertEqualObjects(self.call.sentDigits, @"5#ABCDR");
}

- (void)testDurationContinuesDuringLocalRemoteHoldAndMute {
    self.controller.callActive = YES;
    self.controller.callStartTime = NSDate.timeIntervalSinceReferenceDate - 61;
    [self.controller showActiveCallView];
    [self.controller.activeCallViewController startCallTimer];
    for (NSString *status in @[@"on hold", @"on remote hold", @"mic muted"]) {
        [self.controller.activeCallViewController stopCallTimer];
        self.controller.status = status;
        XCTAssertNotNil(self.controller.activeCallViewController.callTimer);
        self.controller.callStartTime -= 5;
        [self.controller.activeCallViewController callTimerTick:nil];
        XCTAssertEqualObjects(self.controller.status, status);
        XCTAssertEqualObjects([[self.controller.activeCallViewController valueForKey:@"durationField"] stringValue], self.controller.presentationDuration);
    }
    self.call.state = kAKSIPCallDisconnectedState;
    self.call.duration = 84;
    self.controller.callActive = NO;
    [self.controller.activeCallViewController stopCallTimer];
    XCTAssertNil(self.controller.activeCallViewController.callTimer);
    XCTAssertEqualObjects(self.controller.presentationDuration, @"01:24");
}

- (void)testCallerIdentitySurvivesDTMFAndEndedView {
    [self.controller showActiveCallView];
    [self.controller.activeCallViewController activeCallView:(id)self.controller.activeCallViewController.view didReceiveText:@"12#"];
    self.call.state = kAKSIPCallDisconnectedState;
    [self.controller showEndedCallView];
    XCTAssertEqualObjects(self.controller.displayedName, @"Alex Morgan");
    XCTAssertEqualObjects(self.controller.endedCallViewController.displayedNameField.stringValue, @"Alex Morgan");
    XCTAssertEqualObjects(self.controller.endedCallViewController.displayedNameField.accessibilityLabel, @"Caller");
    XCTAssertEqualObjects(self.call.sentDigits, @"12#");
}

- (void)testCallGrowthAtScreenBottomStaysInVisibleAreaInBothAppearances {
    NSScreen *screen = NSScreen.mainScreen;
    XCTAssertNotNil(screen);
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        self.controller.window.appearance = [NSAppearance appearanceNamed:appearance];
        [self.controller showActiveCallView];
        self.controller.status = @"00:12";
        NSRect frame = self.controller.window.frame;
        frame.origin = NSMakePoint(NSMinX(screen.visibleFrame) + 30, NSMinY(screen.visibleFrame));
        [self.controller.window setFrame:frame display:YES];
        [self.controller.window orderFront:nil];
        self.controller.status = @"The remote telephone could not be reached. Please check the number and try the call again.";
        XCTAssertGreaterThanOrEqual(NSMinY(self.controller.window.frame), NSMinY(screen.visibleFrame));
        XCTAssertTrue(NSContainsRect(screen.visibleFrame, self.controller.window.frame));
        for (NSView *child in self.controller.activeCallViewController.view.subviews) {
            if (![child isKindOfClass:NSButton.class]) continue;
            NSRect control = [self.controller.window convertRectToScreen:[child convertRect:child.bounds toView:nil]];
            XCTAssertTrue(NSContainsRect(screen.visibleFrame, control));
        }
        self.call.state = kAKSIPCallDisconnectedState;
        [self.controller showEndedCallView];
        XCTAssertTrue(NSContainsRect(screen.visibleFrame, self.controller.window.frame));
        self.call.state = kAKSIPCallConfirmedState;
    }
}

- (void)testRejectedHangupLeavesCallControllableAndCloseCanRetry {
    self.controller.callActive = YES;
    self.call.rejectsHangUp = YES;
    [self.controller showActiveCallView];
    [self.controller hangUpCall];
    XCTAssertTrue(self.controller.isCallActive);
    XCTAssertEqual(self.call.delegate, self.controller);
    XCTAssertTrue([self buttonWithAction:@selector(hangUpCall:) inView:self.controller.activeCallViewController.view].enabled);
    XCTAssertFalse([self.controller windowShouldClose:self.controller.window]);
    XCTAssertTrue(self.controller.isCallActive);
    self.call.rejectsHangUp = NO;
    [self.controller hangUpCall];
    XCTAssertFalse(self.controller.isCallActive);
    XCTAssertEqual(self.call.hangups, 3u);
}
- (void)testReplacingModelDuringHangupLeavesNewCallControllableAndClearsOldDigits {
    AKDeferredHangupCall *old=[AKDeferredHangupCall new]; old.state=kAKSIPCallConfirmedState;
    self.controller.call=old; self.controller.callActive=YES;
    [self.controller.activeCallViewController activeCallView:(id)self.controller.activeCallViewController.view didReceiveText:@"12"];
    [self.controller hangUpCall]; XCTAssertNotNil(old.hangupCompletion);
    AKCompactCallFixture *replacement=[AKCompactCallFixture new]; replacement.state=kAKSIPCallConfirmedState; replacement.rejectsHangUp=YES;
    self.controller.call=replacement; self.controller.callActive=YES;
    XCTAssertEqualObjects(self.controller.activeCallViewController.enteredDTMF,@"");
    XCTAssertEqualObjects([[self.controller.activeCallViewController valueForKey:@"keypadDigitsField"] stringValue],@"");
    [self.controller hangUpCall]; XCTAssertEqual(replacement.hangups,1u); XCTAssertTrue(self.controller.isCallActive);
    old.hangupCompletion(YES); XCTAssertTrue(self.controller.isCallActive); XCTAssertEqual(self.controller.call,replacement);
}

@end

#import "CallTransferController.h"
#import "ActiveCallTransferViewController.h"
#import "EndedCallTransferViewController.h"

@interface CallTransferController (RepairTests)
- (void)sourceCallControllerSIPCallTransferStatusDidChange:(NSNotification *)notification;
@end
@interface ActiveCallTransferViewController (RepairTests)
- (IBAction)transferCall:(id)sender;
- (void)callDidHold;
@end

@interface AKTransferFixtureController : CallTransferController
@property(nonatomic) NSUInteger transfers;
@property(nonatomic) NSUInteger closures;
@property(nonatomic) BOOL ignoreActualSheet;
@end
@implementation AKTransferFixtureController
- (void)transferCall { self.transfers++; }
- (void)closeSheet:(id)sender { self.closures++; [super closeSheet:sender]; }
- (NSWindow *)window { return nil; }
- (void)unsubscribeFromWindowFloatingChanges {}
@end

@interface TransferRepairTests : XCTestCase
@property(nonatomic) AKCompactCallController *source;
@property(nonatomic) AKCompactCallFixture *call;
@property(nonatomic) AKCompactAccountFixture *account;
@property(nonatomic) AKTransferFixtureController *transfer;
@end

@interface AKDeferredSetupHoldCall : AKCompactCallFixture
@property(nonatomic) NSUInteger holdRequests;
@property(nonatomic,copy) void (^holdCompletion)(BOOL);
@end
@implementation AKDeferredSetupHoldCall
- (void)requestToggleHoldWithCompletion:(void (^)(BOOL))completion {
    self.holdRequests++;
    if (self.holdRequests==1) self.holdCompletion=completion;
    else [super requestToggleHoldWithCompletion:completion];
}
@end
@implementation TransferRepairTests
- (void)setUp {
    self.account = [AKCompactAccountFixture new];
    self.account.accountDescription = @"Synthetic";
    self.source = [[AKCompactCallController alloc] initWithWindowNibName:@"Call" accountController:(id)self.account userAgent:nil delegate:nil];
    self.call = [AKCompactCallFixture new]; self.call.state = kAKSIPCallConfirmedState;
    self.source.call = self.call; self.source.callActive = YES;
    self.transfer = [[AKTransferFixtureController alloc] initWithSourceCallController:self.source userAgent:nil];
    [self.source setValue:self.transfer forKey:@"callTransferController"];
}
- (void)tearDown {
    self.source.callActive = NO;
    self.transfer.callActive = NO;
    [self.transfer.activeCallViewController stopCallTimer];
    [self.source.activeCallViewController stopCallTimer];
    [self.source.window close];
    self.transfer = nil; self.source = nil;
}
- (void)testClosingSetupPreservesManualHoldAndRestoresOnlySetupHold {
    self.source.callOnHold = YES; self.call.localHeld = YES;
    [self.transfer beginTransferSetup];
    [self.transfer closeSheet:nil];
    XCTAssertTrue(self.call.localHeld);
    self.source.callOnHold = NO; self.call.localHeld = NO;
    [self.transfer beginTransferSetup];
    self.source.callOnHold = YES; self.call.localHeld = YES;
    [self.transfer closeSheet:nil];
    XCTAssertFalse(self.call.localHeld);
}
- (void)testClosingBeforeSetupHoldAcknowledgementRestoresLateHold {
    AKDeferredSetupHoldCall *call=[AKDeferredSetupHoldCall new]; call.state=kAKSIPCallConfirmedState;
    self.source.call=call; self.source.callActive=YES; self.source.callOnHold=NO;
    [self.transfer beginTransferSetup]; XCTAssertEqual(call.holdRequests,1u);
    [self.transfer closeSheet:nil]; call.holdCompletion(YES);
    XCTAssertEqual(call.holdRequests,1u);
    call.localHeld=YES; self.source.callOnHold=YES;
    [NSNotificationCenter.defaultCenter postNotificationName:AKSIPCallDidLocalHoldNotification object:call];
    XCTAssertEqual(call.holdRequests,2u); XCTAssertFalse(call.localHeld);
}
- (void)testCachedTransferRebindsCurrentCallAndIgnoresOldFinalResult {
    AKCompactCallFixture *a = self.call;
    AKCompactCallFixture *b = [AKCompactCallFixture new]; b.state = kAKSIPCallConfirmedState;
    self.source.call = b;
    b.transferStatus = PJSIP_SC_OK;
    [NSNotificationCenter.defaultCenter postNotificationName:AKSIPCallTransferStatusDidChangeNotification object:b
        userInfo:@{@"AKFinalTransferNotification": @YES}];
    XCTAssertTrue([[self.transfer valueForKey:@"sourceCallTransferred"] boolValue]);
    XCTAssertEqual(self.transfer.closures, 1u);
    AKCompactCallFixture *c = [AKCompactCallFixture new]; c.state = kAKSIPCallConfirmedState;
    self.source.call = c;
    a.transferStatus = PJSIP_SC_OK;
    [NSNotificationCenter.defaultCenter postNotificationName:AKSIPCallTransferStatusDidChangeNotification object:a
        userInfo:@{@"AKFinalTransferNotification": @YES}];
    XCTAssertFalse([[self.transfer valueForKey:@"sourceCallTransferred"] boolValue]);
    XCTAssertEqual(self.transfer.closures, 1u);
    c.transferStatus = PJSIP_SC_BUSY_HERE;
    [NSNotificationCenter.defaultCenter postNotificationName:AKSIPCallTransferStatusDidChangeNotification object:c
        userInfo:@{@"AKFinalTransferNotification": @YES}];
    XCTAssertFalse([[self.transfer valueForKey:@"sourceCallTransferred"] boolValue]);
}
- (void)testRejectedPreliminaryHoldAllowsTransferRetryThenAcceptedAckTransfersOnce {
    AKCompactCallFixture *consultation = [AKCompactCallFixture new]; consultation.state = kAKSIPCallConfirmedState;
    self.transfer.call = consultation;
    self.transfer.callActive = YES;
    ActiveCallTransferViewController *view = (id)self.transfer.activeCallViewController;
    (void)view.view;
    NSButton *button = [view valueForKey:@"transferButton"];
    [view allowTransfer];
    consultation.rejectsHold = YES;
    [view transferCall:nil];
    XCTAssertFalse([[view valueForKey:@"waitingForHold"] boolValue]);
    XCTAssertTrue(button.enabled);
    XCTAssertEqual(self.transfer.transfers, 0u);
    consultation.rejectsHold = NO;
    [view transferCall:nil];
    XCTAssertTrue([[view valueForKey:@"waitingForHold"] boolValue]);
    XCTAssertFalse(button.enabled);
    self.transfer.callOnHold = YES;
    [view callDidHold];
    XCTAssertFalse([[view valueForKey:@"waitingForHold"] boolValue]);
    XCTAssertEqual(self.transfer.transfers, 1u);
    [view callDidHold];
    XCTAssertEqual(self.transfer.transfers, 1u);
}
- (void)testCompiledEndedTransferNibHasItsRedialOutletAndOneSecondGuard {
    AKCompactCallFixture *consultation = [AKCompactCallFixture new];
    consultation.state = kAKSIPCallDisconnectedState; consultation.lastStatus = PJSIP_SC_OK;
    self.transfer.call = consultation;
    (void)self.transfer.endedCallViewController.view;
    NSButton *redial = self.transfer.endedCallViewController.redialButton;
    XCTAssertNotNil(redial);
    XCTAssertEqual(redial.action, @selector(redial:));
    [self.transfer SIPCallDidDisconnect:[NSNotification notificationWithName:@"test" object:consultation]];
    XCTAssertFalse(redial.enabled);
    XCTestExpectation *enabled = [self expectationWithDescription:@"transfer redial guard"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertTrue(redial.enabled); [enabled fulfill];
    });
    [self waitForExpectations:@[enabled] timeout:3];
}
- (void)testLateHoldAcceptanceAfterTransferPaneClosesCannotTransfer {
    AKDeferredSetupHoldCall *call=[AKDeferredSetupHoldCall new]; call.state=kAKSIPCallConfirmedState;
    self.transfer.call=call; self.transfer.callActive=YES;
    ActiveCallTransferViewController *view=(id)self.transfer.activeCallViewController; (void)view.view;
    [view transferCall:nil]; XCTAssertEqual(call.holdRequests,1u);
    [view transferCall:nil]; XCTAssertEqual(call.holdRequests,1u);
    [view viewWillDisappear]; call.holdCompletion(YES);
    self.transfer.callOnHold=YES; [view callDidHold];
    XCTAssertFalse([[view valueForKey:@"waitingForHold"] boolValue]); XCTAssertNil([view valueForKey:@"holdAcceptanceTimer"]);
    XCTAssertEqual(self.transfer.transfers,0u);
}
@end

#import "AccountController.h"
#import "AccountControllers.h"
#import "AccountWindowController.h"
#import "AKSIPUserAgent.h"
#import <objc/runtime.h>

@interface AccountController (IntentRepairTests)
- (void)changeAccountState:(AccountWindowControllerAccountState)state;
- (void)SIPUserAgentDidFinishStarting:(NSNotification *)notification;
@end

@interface AKIntentAccount : AKSIPAccount
@property(nonatomic) NSUInteger registerRequests;
@property(nonatomic) NSUInteger unregisterRequests;
@end
@implementation AKIntentAccount
- (void)setRegistered:(BOOL)registered {
    self.desiredRegistered = registered;
    if (registered) self.registerRequests++; else self.unregisterRequests++;
}
- (void)setOnline:(BOOL)online {}
@end
@interface AKIntentAgent : NSObject
@property(nonatomic, getter=isStarted) BOOL started;
@property(nonatomic) NSUInteger removals;
- (void)removeAccount:(AKSIPAccount *)account completion:(void (^)(BOOL))completion;
@end
@implementation AKIntentAgent
- (void)removeAccount:(AKSIPAccount *)account completion:(void (^)(BOOL))completion { self.removals++; completion(YES); }
@end
@interface AKIntentController : AccountController
@property(nonatomic) NSUInteger offlinePresentations;
@property(nonatomic) NSUInteger unavailablePresentations;
@end
@implementation AKIntentController
- (void)showOfflineState { self.offlinePresentations++; }
- (void)showUnavailableState { self.unavailablePresentations++; }
- (void)showConnectingState {}
@end
@interface AKShutdownIntentController : AKIntentController
@property(nonatomic) NSUInteger removals;
@end
@implementation AKShutdownIntentController
- (void)removeAccountFromUserAgent { self.removals++; }
@end
@interface AKShutdownCallFixture : NSObject
@property(nonatomic,getter=isCallActive) BOOL callActive;
@property(nonatomic) NSUInteger hangups;
- (void)hangUpCall;
@end
@implementation AKShutdownCallFixture
- (void)hangUpCall { self.hangups++; }
- (void)close {}
@end
@interface AKRegistryTestAgent : AKSIPUserAgent
@end
@implementation AKRegistryTestAgent
- (void)performSIPOperation:(pj_status_t (^)(void))operation completion:(void (^)(pj_status_t))completion { if (completion) completion(PJ_SUCCESS); }
- (void)performSIPCleanupOperation:(pj_status_t (^)(void))operation completion:(void (^)(pj_status_t))completion {
    // Inert accepted account-delete boundary. No native operation is executed.
    if (completion) completion(PJ_SUCCESS);
}
@end

@interface AccountIntentRepairTests : XCTestCase
@end
@implementation AccountIntentRepairTests
- (void)testDisabledAccountWithRejectedHangupStillCountsForQuitAndShutdown {
    AKShutdownIntentController *controller=[AKShutdownIntentController new];
    [controller setValue:@NO forKey:@"_enabled"];
    AKShutdownCallFixture *call=[AKShutdownCallFixture new]; call.callActive=YES;
    [controller setValue:[NSMutableArray arrayWithObject:call] forKey:@"callControllers"];
    AccountControllers *controllers=[AccountControllers new]; [controllers addController:controller];
    XCTAssertEqual(controllers.enabled.count,0u); XCTAssertTrue(controllers.haveActiveCallControllers);
    [controllers hangUpCallsAndRemoveAccountsFromUserAgent];
    XCTAssertEqual(call.hangups,1u); XCTAssertEqual(controller.removals,1u);
    call.callActive=NO; XCTAssertFalse(controllers.haveActiveCallControllers);
}
- (AKIntentAccount *)account {
    return [[AKIntentAccount alloc] initWithDictionary:@{@"UUID": NSUUID.UUID.UUIDString, @"FullName": @"Synthetic",
        @"Realm": @"*", @"Username": @"test", @"Domain": @"example.invalid"} parser:nil];
}
- (AKIntentController *)controllerWithAccount:(AKIntentAccount *)account agent:(AKIntentAgent *)agent {
    AKIntentController *controller = [AKIntentController new];
    [controller setValue:account forKey:@"account"];
    [controller setValue:agent forKey:@"userAgent"];
    [controller setValue:[NSMutableArray new] forKey:@"callControllers"];
    [controller setValue:@(YES) forKey:@"_enabled"];
    [controller setValue:@(AccountWindowControllerAccountStateAvailable) forKey:@"desiredAvailability"];
    return controller;
}
- (void)testOfflineCancelsPendingRegistrationAndLateStartupDoesNotReverseIntent {
    AKIntentAccount *account = [self account];
    AKIntentAgent *agent = [AKIntentAgent new];
    AKIntentController *controller = [self controllerWithAccount:account agent:agent];
    [controller registerAccount];
    XCTAssertTrue(controller.attemptingToRegisterAccount);
    NSUInteger generation = account.outgoingGeneration;
    [controller changeAccountState:AccountWindowControllerAccountStateOffline];
    XCTAssertFalse(controller.attemptingToRegisterAccount);
    XCTAssertGreaterThan(account.outgoingGeneration, generation);
    agent.started = YES;
    [controller SIPUserAgentDidFinishStarting:[NSNotification notificationWithName:@"test" object:agent]];
    XCTAssertEqual(account.registerRequests, 0u);
    XCTAssertEqual(agent.removals, 0u);
}
- (void)testManualUnavailableSurvivesAutomaticRegistrationAndExplicitAvailableWorks {
    AKIntentAccount *account = [self account]; [account updateIdentifier:7];
    AKIntentAgent *agent = [AKIntentAgent new]; agent.started = YES;
    AKIntentController *controller = [self controllerWithAccount:account agent:agent];
    [controller changeAccountState:AccountWindowControllerAccountStateUnavailable];
    [controller resumeRegistrationIfDesired];
    XCTAssertTrue(controller.isAccountUnavailable);
    XCTAssertEqual(account.registerRequests, 0u);
    XCTAssertGreaterThan(account.unregisterRequests, 0u);
    [controller changeAccountState:AccountWindowControllerAccountStateAvailable];
    XCTAssertFalse(controller.isAccountUnavailable);
    XCTAssertEqual(account.registerRequests, 1u);
}
- (void)testOfflineRetainsActiveCallOwnershipAndAccountRemovalRetiresRegistryUntilDisconnect {
    AKIntentAccount *account = [self account]; [account updateIdentifier:7];
    AKCompactCallFixture *call = [AKCompactCallFixture new]; call.identifier = 3; call.state = kAKSIPCallConfirmedState;
    [call setValue:account forKey:@"account"];
    [[account valueForKey:@"calls"] addObject:call];
    AKRegistryTestAgent *registry = class_createInstance(AKRegistryTestAgent.class, 0);
    [registry setValue:[NSMutableArray arrayWithObject:account] forKey:@"accounts"];
    [registry setValue:[NSMutableArray new] forKey:@"retiredAccounts"];
    [registry setValue:@(2) forKey:@"state"];
    XCTAssertNotNil([registry callWithIdentifier:3]);
    AKIntentController *controller = [self controllerWithAccount:account agent:(id)registry];
    AKHeadlessCallController *card = [[AKHeadlessCallController alloc] initWithWindowNibName:@"Call"
        accountController:controller userAgent:nil delegate:nil];
    card.call = call; card.callActive = YES;
    [controller.callControllers addObject:card];
    [controller changeAccountState:AccountWindowControllerAccountStateOffline];
    XCTAssertEqual([registry callWithIdentifier:3], call);
    XCTAssertTrue(card.isCallActive);
    XCTAssertEqual(call.delegate, card);
    XCTAssertEqual(call.hangups, 0u);
    [card SIPCallDidLocalHold:[NSNotification notificationWithName:@"test" object:call]];
    XCTAssertTrue(card.isCallOnHold);
    __block BOOL removed = NO;
    [registry removeAccount:account completion:^(BOOL success) { removed = success; }];
    XCTAssertTrue(removed);
    XCTAssertEqualObjects([registry callWithIdentifier:3], call);
    XCTAssertEqual(account.callsSnapshot.count, 1u);
    [account removeCall:call];
    [registry forgetRetiredAccountIfUnused:account];
    XCTAssertNil([registry callWithIdentifier:3]);
}
- (void)testOutgoingCancellationTokenChangesOnRemovalAndIdentifierReplacement {
    AKIntentAccount *account = [self account];
    NSUInteger initial = account.outgoingGeneration;
    [account updateIdentifier:3];
    XCTAssertGreaterThan(account.outgoingGeneration, initial);
    NSUInteger added = account.outgoingGeneration;
    [account cancelPendingOutgoingCalls];
    XCTAssertGreaterThan(account.outgoingGeneration, added);
    NSUInteger cancelled = account.outgoingGeneration;
    [account updateIdentifier:3];
    XCTAssertEqual(account.outgoingGeneration, cancelled);
    [account updateIdentifier:-1];
    XCTAssertGreaterThan(account.outgoingGeneration, cancelled);
}
@end

@interface AKSIPUserAgent (RingbackRepairTests)
- (void)finishStopping;
@end
@interface AKRingbackTestAgent : AKRegistryTestAgent
@property(nonatomic) NSUInteger connectionRequests;
@end
@implementation AKRingbackTestAgent
- (pj_status_t)connectAudioSource:(pjsua_conf_port_id)source destination:(pjsua_conf_port_id)destination {
    self.connectionRequests++; return PJ_SUCCESS;
}
@end
@interface RingbackRestartRepairTests : XCTestCase
@end
@implementation RingbackRestartRepairTests
- (void)testFinishStoppingResetsEveryOldSlotAndNewTonePortConnectsOnce {
    AKRingbackTestAgent *agent = class_createInstance(AKRingbackTestAgent.class, 0);
    [agent setValue:[NSMutableArray new] forKey:@"accounts"];
    [agent setValue:[NSMutableArray new] forKey:@"retiredAccounts"];
    [agent setValue:@1 forKey:@"ringbackCount"];
    agent.callData[0].ringbackOn = PJ_TRUE;
    [agent finishStopping];
    XCTAssertEqual([[agent valueForKey:@"ringbackCount"] integerValue], 0);
    for (NSInteger i=0; i<PJSUA_MAX_CALLS; i++) XCTAssertFalse(agent.callData[i].ringbackOn);
    [agent setValue:@42 forKey:@"ringbackSlot"];
    AKCompactCallFixture *call = [AKCompactCallFixture new]; call.identifier = 0;
    XCTestExpectation *started = [self expectationWithDescription:@"ringback started on SDK worker"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        XCTAssertFalse(NSThread.isMainThread);
        [agent startRingbackForCall:call];
        [agent startRingbackForCall:call];
        [started fulfill];
    });
    [self waitForExpectations:@[started] timeout:2];
    XCTAssertEqual(agent.connectionRequests, 1u);
    XCTAssertEqual([[agent valueForKey:@"ringbackCount"] integerValue], 1);
    XCTAssertTrue(agent.callData[0].ringbackOn);
    [agent setValue:@(-1) forKey:@"ringbackSlot"];
    XCTestExpectation *stopped = [self expectationWithDescription:@"ringback stopped on SDK worker"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        XCTAssertFalse(NSThread.isMainThread);
        [agent stopRingbackForCall:call];
        [stopped fulfill];
    });
    [self waitForExpectations:@[stopped] timeout:2];
    XCTAssertFalse(agent.callData[0].ringbackOn);
    XCTAssertEqual([[agent valueForKey:@"ringbackCount"] integerValue], 0);
}
@end

#import "AKSIPURI.h"
#import <objc/message.h>

@interface AKOutgoingQueueAccount : AKSIPAccount
@property(nonatomic) id capturedParameters;
@end
@implementation AKOutgoingQueueAccount
- (void)performSelector:(SEL)selector onThread:(NSThread *)thread withObject:(id)object waitUntilDone:(BOOL)wait {
    NSCAssert([NSStringFromSelector(selector) isEqualToString:@"thread_makeCallWithParameters:"], @"unexpected SDK queue");
    self.capturedParameters = object;
}
@end
@interface AKOutgoingAgentDouble : NSObject
@property(nonatomic) NSUInteger audioGeneration;
- (BOOL)beginOutgoingCall;
@end
@implementation AKOutgoingAgentDouble
- (BOOL)beginOutgoingCall { return YES; }
@end
@interface AKCallInfoDouble : NSObject
@property(nonatomic) NSInteger identifier, accountIdentifier, state, lastStatus;
@property(nonatomic, copy) NSString *dialogIdentifier, *stateText, *lastStatusText;
@property(nonatomic) AKSIPURI *localURI, *remoteURI;
@property(nonatomic, getter=isIncoming) BOOL incoming;
@end
@implementation AKCallInfoDouble
@end
static id AKOutgoingRegressionAgent;
static id AKOutgoingSharedAgent(id receiver, SEL selector) { return AKOutgoingRegressionAgent; }

@interface OutgoingAccountRepairTests : XCTestCase
@end
@implementation OutgoingAccountRepairTests
- (void)testAcceptedCompletionCannotAttachAfterAccountRemovalOrTerminalDialog {
    Method shared = class_getClassMethod(AKSIPUserAgent.class, @selector(sharedUserAgent));
    IMP original = method_getImplementation(shared);
    AKOutgoingAgentDouble *agent = [AKOutgoingAgentDouble new]; agent.audioGeneration = 7;
    AKOutgoingRegressionAgent = agent;
    method_setImplementation(shared, (IMP)AKOutgoingSharedAgent);
    @try {
        for (NSString *scenario in @[@"current", @"removed", @"replaced", @"disconnected"]) {
            AKOutgoingQueueAccount *account = [[AKOutgoingQueueAccount alloc] initWithDictionary:
                @{@"UUID": NSUUID.UUID.UUIDString, @"FullName": @"Synthetic", @"Realm": @"*", @"Username": @"test", @"Domain": @"example.invalid"} parser:nil];
            [account updateIdentifier:3]; account.thread = NSThread.currentThread;
            AKSIPURI *uri = [[AKSIPURI alloc] initWithUser:@"remote" host:@"example.invalid" displayName:@""];
            __block NSUInteger completions = 0; __block AKSIPCall *returned = nil;
            [account makeCallTo:uri completion:^(AKSIPCall *call) { completions++; returned = call; }];
            XCTAssertNotNil(account.capturedParameters);
            AKCallInfoDouble *info = [AKCallInfoDouble new]; info.identifier = 9; info.accountIdentifier = 3;
            info.state = kAKSIPCallCallingState; info.dialogIdentifier = @"synthetic-dialog";
            info.stateText = @"Calling"; info.lastStatusText = @"Synthetic"; info.localURI = uri; info.remoteURI = uri;
            if ([scenario isEqual:@"removed"]) [account updateIdentifier:-1];
            if ([scenario isEqual:@"replaced"]) { [account updateIdentifier:-1]; [account updateIdentifier:3]; }
            if ([scenario isEqual:@"disconnected"]) {
                AKSIPCall *prior = [account addCallWithInfo:(id)info]; prior.state = kAKSIPCallDisconnectedState;
                [account removeCall:prior];
            }
            void (^complete)(BOOL,id) = [account.capturedParameters valueForKey:@"completion"];
            complete(YES, info);
            XCTAssertEqual(completions, 1u);
            XCTAssertEqual(returned != nil, [scenario isEqual:@"current"]);
            XCTAssertEqual(account.callsSnapshot.count, [scenario isEqual:@"current"] ? 1u : 0u);
        }
    } @finally {
        method_setImplementation(shared, original);
        AKOutgoingRegressionAgent = nil;
    }
}
@end
