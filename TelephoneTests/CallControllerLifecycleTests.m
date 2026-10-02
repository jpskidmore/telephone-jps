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
