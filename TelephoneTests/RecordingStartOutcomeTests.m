#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "AKSIPCall.h"
#import "AKStereoRecording.h"

@interface AKSIPCall (RecordingStartOutcomeTests)
- (void)performDialogOperation:(pj_status_t (^)(pjsua_call_info *))operation completion:(void (^)(pj_status_t))completion;
- (BOOL)hasRecordingAudioFailure;
- (pjsua_conf_port_id)recordingCallPort;
- (NSURL *)createRecordingRecoveryDirectoryWithError:(NSError **)error;
- (pj_status_t)createRecordingRecorderAtURL:(NSURL *)URL identifier:(pjsua_recorder_id *)identifier;
- (pjsua_conf_port_id)recordingPortForRecorder:(pjsua_recorder_id)identifier;
- (pj_status_t)connectRecordingAudioSource:(pjsua_conf_port_id)source destination:(pjsua_conf_port_id)destination;
- (void)destroyRecordingRecorder:(pjsua_recorder_id)identifier;
- (BOOL)stopNativeRecorders;
- (void)finalizeRecordingFromLocalURL:(NSURL *)localURL remoteURL:(NSURL *)remoteURL
                     destinationURL:(NSURL *)destinationURL completion:(void (^)(BOOL))completion;
@end

@interface RSOAccessSpy : NSObject
@property(nonatomic) NSUInteger releases;
@property(nonatomic, strong) NSURL *reservation;
@property(nonatomic) BOOL removedBeforeRelease;
@end
@implementation RSOAccessSpy
- (void)stopAccessingSecurityScopedResource {
    self.releases++;
    self.removedBeforeRelease = ![NSFileManager.defaultManager fileExistsAtPath:self.reservation.path];
}
@end

// Allocate without AKSIPCall's initializer. Every native/audio/default-storage
// boundary is replaced, including shutdown/finalisation reached from dealloc.
@interface RSOCall : AKSIPCall
@property(nonatomic, strong) NSURL *scratchRoot;
@property(nonatomic) BOOL failedAudio, failedPrivateStorage, staleDialog;
@property(nonatomic) NSInteger failedRecorderNumber, failedConnectionNumber;
@property(nonatomic) pjsua_conf_port_id fakeCallPort;
@property(nonatomic) pjsip_inv_state fakeNativeState;
@property(nonatomic) NSUInteger admissions, recorderCreates, recorderDestroys, connections, nativeStops;
@property(nonatomic, copy) pj_status_t (^heldOperation)(pjsua_call_info *);
@property(nonatomic, copy) void (^heldCompletion)(pj_status_t);
@property(nonatomic) pj_status_t workerStatus;
- (void)runWorker;
- (void)completeWorker;
@end
@implementation RSOCall
- (BOOL)requiresSIPControlThread { return NO; }
- (BOOL)hasRecordingAudioFailure { return self.failedAudio; }
- (pjsua_conf_port_id)recordingCallPort { return self.fakeCallPort; }
- (NSURL *)createRecordingRecoveryDirectoryWithError:(NSError **)error {
    if (self.failedPrivateStorage) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:13 userInfo:nil];
        return nil;
    }
    return AKCreateRecordingRecoveryDirectoryAtRoot(self.scratchRoot, error);
}
- (pj_status_t)createRecordingRecorderAtURL:(NSURL *)URL identifier:(pjsua_recorder_id *)identifier {
    self.recorderCreates++;
    if (self.recorderCreates == self.failedRecorderNumber) return PJ_EUNKNOWN;
    *identifier = (pjsua_recorder_id)self.recorderCreates;
    [@"Synthetic recorder data" writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:URL.path error:nil];
    return PJ_SUCCESS;
}
- (pjsua_conf_port_id)recordingPortForRecorder:(pjsua_recorder_id)identifier { return identifier + 10; }
- (pj_status_t)connectRecordingAudioSource:(pjsua_conf_port_id)source destination:(pjsua_conf_port_id)destination {
    self.connections++;
    return self.connections == self.failedConnectionNumber ? PJ_EUNKNOWN : PJ_SUCCESS;
}
- (void)destroyRecordingRecorder:(pjsua_recorder_id)identifier { self.recorderDestroys++; }
- (BOOL)stopNativeRecorders {
    self.nativeStops++;
    [self setValue:@NO forKey:@"nativeRecordingActive"];
    return YES;
}
- (void)finalizeRecordingFromLocalURL:(NSURL *)localURL remoteURL:(NSURL *)remoteURL
                     destinationURL:(NSURL *)destinationURL completion:(void (^)(BOOL))completion { completion(YES); }
- (void)performDialogOperation:(pj_status_t (^)(pjsua_call_info *))operation completion:(void (^)(pj_status_t))completion {
    self.admissions++;
    self.heldOperation = operation;
    self.heldCompletion = completion;
}
- (void)runWorker {
    pj_status_t (^operation)(pjsua_call_info *) = self.heldOperation;
    self.heldOperation = nil;
    pjsua_call_info info = {0};
    info.state = self.fakeNativeState;
    self.workerStatus = self.staleDialog ? PJ_ECANCELLED : operation(&info);
}
- (void)completeWorker {
    void (^completion)(pj_status_t) = self.heldCompletion;
    self.heldCompletion = nil;
    completion(self.workerStatus);
}
@end

@interface RecordingStartOutcomeTests : XCTestCase
@property(nonatomic, strong) NSURL *scratch;
@property(nonatomic, strong) NSMutableArray<RSOCall *> *calls;
@end
@implementation RecordingStartOutcomeTests
- (void)drainFinalizations {
    XCTestExpectation *drained = [self expectationWithDescription:@"owned recording cleanup drained"];
    AKWaitForPendingRecordingFinalizations(^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:3];
}
- (void)setUp {
    [super setUp];
    self.scratch = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                            isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.scratch withIntermediateDirectories:YES attributes:nil error:nil]);
    self.calls = [NSMutableArray new];
}
- (void)tearDown {
    for (RSOCall *call in self.calls) {
        [call stopRecording];
        // Failure assertions must not leave a self-retaining held worker block.
        call.heldOperation = nil;
        call.heldCompletion = nil;
    }
    [self drainFinalizations];
    self.calls = nil;
    [NSFileManager.defaultManager removeItemAtURL:self.scratch error:nil];
    [super tearDown];
}
- (RSOCall *)newCall {
    RSOCall *call = class_createInstance(RSOCall.class, 0);
    call.state = kAKSIPCallConfirmedState;
    call.fakeNativeState = PJSIP_INV_STATE_CONFIRMED;
    call.fakeCallPort = 4;
    call.scratchRoot = [self.scratch URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    [self.calls addObject:call];
    return call;
}
- (NSURL *)reservation {
    NSURL *URL = [self.scratch URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".wav"]];
    XCTAssertTrue([NSData.data writeToURL:URL atomically:YES]);
    return URL;
}
- (RSOAccessSpy *)scopeForURL:(NSURL *)URL {
    RSOAccessSpy *scope = [RSOAccessSpy new]; scope.reservation = URL; return scope;
}
- (AKRecordingStartResult)startCall:(RSOCall *)call URL:(NSURL *)URL scope:(RSOAccessSpy *)scope {
    __block AKRecordingStartResult result = AKRecordingStartResultBusy;
    [call startRecordingToURL:URL accessedDirectoryURL:(id)scope resultCompletion:^(AKRecordingStartResult value) { result = value; }];
    [call runWorker];
    [call completeWorker];
    return result;
}
- (void)assertFailure:(AKRecordingStartResult)expected call:(RSOCall *)call {
    NSURL *URL = [self reservation]; RSOAccessSpy *scope = [self scopeForURL:URL];
    XCTAssertEqual([self startCall:call URL:URL scope:scope], expected);
    XCTAssertFalse(call.isRecording);
    XCTAssertNil(call.recordingURL);
    XCTAssertEqual(scope.releases, 1u);
    XCTAssertTrue(scope.removedBeforeRelease);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.scratchRoot).count, 0u);
}
- (void)testSuccessPublishesActualDestinationAndRetainsScopeUntilStop {
    RSOCall *call = [self newCall]; NSURL *URL = [self reservation]; RSOAccessSpy *scope = [self scopeForURL:URL];
    XCTAssertEqual([self startCall:call URL:URL scope:scope], AKRecordingStartResultSuccess);
    XCTAssertTrue(call.isRecording); XCTAssertEqualObjects(call.recordingURL, URL);
    XCTAssertEqual(call.recorderCreates, 2u); XCTAssertEqual(call.connections, 2u);
    XCTAssertEqual(scope.releases, 0u);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRoot(call.scratchRoot).count, 0u);
    [call stopRecording];
    [self drainFinalizations];
    XCTAssertEqual(scope.releases, 1u); XCTAssertEqual(call.nativeStops, 1u);
    XCTAssertFalse(call.isRecording); XCTAssertNil(call.recordingURL);
}
- (void)testAudioFailureHasItsOwnOutcomeAndCreatesNoRecorder {
    RSOCall *call = [self newCall]; call.failedAudio = YES;
    [self assertFailure:AKRecordingStartResultAudioFailure call:call]; XCTAssertEqual(call.recorderCreates, 0u);
}
- (void)testPrivateStorageFailureHasItsOwnOutcome {
    RSOCall *call = [self newCall]; call.failedPrivateStorage = YES;
    [self assertFailure:AKRecordingStartResultPrivateStorageFailure call:call]; XCTAssertEqual(call.recorderCreates, 0u);
}
- (void)testFirstRecorderFailureDiscardsOnlyTheUnusedPrivateJob {
    RSOCall *call = [self newCall]; call.failedRecorderNumber = 1;
    [self assertFailure:AKRecordingStartResultRecorderCreationFailure call:call]; XCTAssertEqual(call.recorderDestroys, 0u);
}
- (void)testSecondRecorderFailureDestroysTheFirstRecorder {
    RSOCall *call = [self newCall]; call.failedRecorderNumber = 2;
    [self assertFailure:AKRecordingStartResultRecorderCreationFailure call:call]; XCTAssertEqual(call.recorderDestroys, 1u);
}
- (void)testMissingCallPortHasConnectionOutcomeWithoutCreatingRecorders {
    RSOCall *call = [self newCall]; call.fakeCallPort = PJSUA_INVALID_ID;
    [self assertFailure:AKRecordingStartResultConnectionFailure call:call]; XCTAssertEqual(call.recorderCreates, 0u);
}
- (void)testRemoteConnectionFailureDestroysBothRecorders {
    RSOCall *call = [self newCall]; call.failedConnectionNumber = 1;
    [self assertFailure:AKRecordingStartResultConnectionFailure call:call]; XCTAssertEqual(call.recorderDestroys, 2u);
}
- (void)testMicrophoneConnectionFailureDestroysBothRecorders {
    RSOCall *call = [self newCall]; call.failedConnectionNumber = 2;
    [self assertFailure:AKRecordingStartResultConnectionFailure call:call]; XCTAssertEqual(call.recorderDestroys, 2u);
}
- (void)testInvalidDestinationCannotRemoveADirectoryOrItsContents {
    RSOCall *call = [self newCall]; NSURL *directory = [self.scratch URLByAppendingPathComponent:@"keep" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:nil]);
    NSURL *data = [directory URLByAppendingPathComponent:@"retained"];
    XCTAssertTrue([@"retained" writeToURL:data atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    RSOAccessSpy *scope = [self scopeForURL:directory];
    XCTAssertEqual([self startCall:call URL:directory scope:scope], AKRecordingStartResultInvalidDestination);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:data.path]);
    XCTAssertEqual(scope.releases, 1u); XCTAssertEqual(call.recorderCreates, 0u);
}
- (void)testStaleDialogReleasesReservationWithoutEnteringSetup {
    RSOCall *call = [self newCall]; call.staleDialog = YES;
    [self assertFailure:AKRecordingStartResultStaleCall call:call]; XCTAssertEqual(call.recorderCreates, 0u);
}
- (void)testNativeEndedDialogRejectsAConfirmedObjectSnapshot {
    RSOCall *call = [self newCall]; call.fakeNativeState = PJSIP_INV_STATE_DISCONNECTED;
    [self assertFailure:AKRecordingStartResultStaleCall call:call]; XCTAssertEqual(call.recorderCreates, 0u);
}
- (void)testPendingDuplicatePreservesOriginalReservationAndScope {
    RSOCall *call = [self newCall]; NSURL *URL = [self reservation];
    RSOAccessSpy *first = [self scopeForURL:URL], *duplicate = [self scopeForURL:URL];
    [call startRecordingToURL:URL accessedDirectoryURL:(id)first resultCompletion:^(AKRecordingStartResult result) {
        XCTAssertEqual(result, AKRecordingStartResultSuccess);
    }];
    [call startRecordingToURL:URL accessedDirectoryURL:(id)duplicate resultCompletion:^(AKRecordingStartResult result) {
        XCTAssertEqual(result, AKRecordingStartResultBusy);
    }];
    XCTAssertEqual(call.admissions, 1u); XCTAssertEqual(first.releases, 0u); XCTAssertEqual(duplicate.releases, 1u);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:URL.path]);
    [call runWorker]; [call completeWorker]; [call stopRecording];
    [self drainFinalizations]; XCTAssertEqual(first.releases, 1u);
}
- (void)testActiveDuplicatePreservesDestinationAndCleansItsSeparateReservation {
    RSOCall *call = [self newCall]; NSURL *URL = [self reservation]; RSOAccessSpy *first = [self scopeForURL:URL];
    XCTAssertEqual([self startCall:call URL:URL scope:first], AKRecordingStartResultSuccess);
    for (NSURL *candidate in @[URL, [self reservation]]) {
        RSOAccessSpy *duplicate = [self scopeForURL:candidate];
        [call startRecordingToURL:candidate accessedDirectoryURL:(id)duplicate resultCompletion:^(AKRecordingStartResult result) {
            XCTAssertEqual(result, AKRecordingStartResultBusy);
        }];
        XCTAssertEqual(duplicate.releases, 1u);
        XCTAssertEqual([NSFileManager.defaultManager fileExistsAtPath:candidate.path], [candidate isEqual:URL]);
    }
    XCTAssertEqualObjects(call.recordingURL, URL); XCTAssertEqual(call.recorderCreates, 2u); XCTAssertEqual(first.releases, 0u);
    XCTAssertFalse([call startRecordingToURL:URL]); // The legacy wrapper cannot falsely claim a new session.
}
- (void)testStopBeforeWorkerCancelsPendingStartAndReleasesOnce {
    RSOCall *call = [self newCall]; NSURL *URL = [self reservation]; RSOAccessSpy *scope = [self scopeForURL:URL];
    __block AKRecordingStartResult result = AKRecordingStartResultSuccess;
    [call startRecordingToURL:URL accessedDirectoryURL:(id)scope resultCompletion:^(AKRecordingStartResult value) { result = value; }];
    [call stopRecording]; [call runWorker]; [call completeWorker];
    XCTAssertEqual(result, AKRecordingStartResultStaleCall); XCTAssertEqual(call.recorderCreates, 0u);
    XCTAssertEqual(scope.releases, 1u); XCTAssertTrue(scope.removedBeforeRelease);
}
- (void)testStopAfterWorkerBeforeCompletionCannotReportCaptureOrAffectReplacement {
    RSOCall *old = [self newCall]; NSURL *oldURL = [self reservation]; RSOAccessSpy *oldScope = [self scopeForURL:oldURL];
    __block AKRecordingStartResult oldResult = AKRecordingStartResultSuccess;
    [old startRecordingToURL:oldURL accessedDirectoryURL:(id)oldScope resultCompletion:^(AKRecordingStartResult value) { oldResult = value; }];
    [old runWorker]; XCTAssertTrue(old.isRecording); [old stopRecording];
    RSOCall *replacement = [self newCall]; NSURL *newURL = [self reservation]; RSOAccessSpy *newScope = [self scopeForURL:newURL];
    XCTAssertEqual([self startCall:replacement URL:newURL scope:newScope], AKRecordingStartResultSuccess);
    [old completeWorker];
    [self drainFinalizations];
    XCTAssertEqual(oldResult, AKRecordingStartResultStaleCall); XCTAssertEqual(oldScope.releases, 1u);
    XCTAssertTrue(replacement.isRecording); XCTAssertEqualObjects(replacement.recordingURL, newURL);
    XCTAssertEqual(replacement.nativeStops, 0u); XCTAssertEqual(newScope.releases, 0u);
}
- (void)testLegacyBooleanCompletionMatchesTypedFailureAndSuccess {
    for (NSNumber *failure in @[@YES, @NO]) {
        RSOCall *call = [self newCall]; call.failedAudio = failure.boolValue; NSURL *URL = [self reservation];
        __block BOOL accepted = failure.boolValue;
        [call startRecordingToURL:URL accessedDirectoryURL:nil completion:^(BOOL result) { accepted = result; }];
        [call runWorker]; [call completeWorker]; XCTAssertEqual(accepted, !failure.boolValue);
    }
}
@end
