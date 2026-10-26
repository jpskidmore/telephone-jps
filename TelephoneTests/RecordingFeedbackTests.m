#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <errno.h>
#import "AKSIPCall.h"
#import "AKStereoRecording.h"
#import "ActiveCallViewController.h"
#import "CallController.h"

@interface CallController (RF65TestBoundaries)
- (NSURL *)selectedRecordingDirectoryURL;
- (NSURL *)defaultRecordingDirectoryURL;
- (NSURL *)reserveRecordingURLInDirectory:(NSURL *)directory filenameStem:(NSString *)stem
                               extension:(NSString *)extension error:(NSError **)error;
- (void)presentRecordingFolderPanelWithCompletion:(void (^)(NSURL *))completion;
- (NSData *)recordingFolderBookmarkForURL:(NSURL *)URL error:(NSError **)error;
- (void)revealRecordingDirectoryURL:(NSURL *)URL;
- (void)unsubscribeFromWindowFloatingChanges;
@end

@interface ActiveCallViewController (RF65TestPresentation)
- (IBAction)showRecordingDetails:(id)sender;
@end

// Redirect only an explicitly registered scratch URL. All other NSURL instances
// retain their original behaviour; no real sandbox grant is requested here.
@interface RF65Scope : NSObject
@property(nonatomic) BOOL granted;
@property(nonatomic) NSUInteger starts, stops;
@end
@implementation RF65Scope @end
static NSMutableDictionary<NSString *, RF65Scope *> *RF65Scopes;
static IMP RF65OriginalScopeStart, RF65OriginalScopeStop;
static BOOL RF65ScopeStart(NSURL *URL, SEL selector) {
    RF65Scope *scope = RF65Scopes[URL.absoluteString];
    if (scope) { scope.starts++; return scope.granted; }
    return ((BOOL (*)(id, SEL))RF65OriginalScopeStart)(URL, selector);
}
static void RF65ScopeStop(NSURL *URL, SEL selector) {
    RF65Scope *scope = RF65Scopes[URL.absoluteString];
    if (scope) { scope.stops++; return; }
    ((void (*)(id, SEL))RF65OriginalScopeStop)(URL, selector);
}

@interface RF65Attempt : NSObject
@property(nonatomic) NSURL *URL, *scope;
@property(nonatomic) BOOL retired;
@property(nonatomic, copy) void (^completion)(AKRecordingStartResult);
@end
@implementation RF65Attempt @end

// No native SIP methods, recorder, encoder, audio file or recovery root is used.
// This boundary owns only the empty reservation and simulated scope handed to it.
@interface RF65Call : AKSIPCall
@property(nonatomic) NSMutableArray<RF65Attempt *> *attempts;
@property(nonatomic) BOOL capturing;
@property(nonatomic) NSURL *capturedURL;
@property(nonatomic) NSUInteger stops;
- (void)completeAttempt:(NSUInteger)index result:(AKRecordingStartResult)result;
@end
@implementation RF65Call
- (instancetype)init {
    if ((self = [super init])) { _attempts = [NSMutableArray new]; self.state = kAKSIPCallConfirmedState; }
    return self;
}
- (BOOL)isRecording { return self.capturing; }
- (NSURL *)recordingURL { return self.capturedURL; }
- (BOOL)isActive { return self.state == kAKSIPCallConfirmedState; }
- (BOOL)isIncoming { return NO; }
- (BOOL)isMicrophoneMuted { return NO; }
- (BOOL)isOnLocalHold { return NO; }
- (BOOL)isOnRemoteHold { return NO; }
- (void)retireAttempt:(RF65Attempt *)attempt {
    if (attempt.retired) return;
    attempt.retired = YES;
    [NSFileManager.defaultManager removeItemAtURL:attempt.URL error:nil];
    [attempt.scope stopAccessingSecurityScopedResource];
    attempt.scope = nil;
}
- (void)startRecordingToURL:(NSURL *)URL accessedDirectoryURL:(NSURL *)scope
          resultCompletion:(void (^)(AKRecordingStartResult))completion {
    RF65Attempt *attempt = [RF65Attempt new];
    attempt.URL = URL; attempt.scope = scope; attempt.completion = completion;
    [self.attempts addObject:attempt];
}
- (void)completeAttempt:(NSUInteger)index result:(AKRecordingStartResult)result {
    RF65Attempt *attempt = self.attempts[index];
    if (!attempt.retired && result == AKRecordingStartResultSuccess) {
        self.capturing = YES; self.capturedURL = attempt.URL;
    } else if (!attempt.retired) {
        [self retireAttempt:attempt];
    }
    void (^completion)(AKRecordingStartResult) = attempt.completion;
    attempt.completion = nil;
    if (completion) completion(result);
}
- (void)stopRecording {
    self.stops++;
    for (RF65Attempt *attempt in self.attempts) [self retireAttempt:attempt];
    self.capturing = NO; self.capturedURL = nil;
}
@end

@interface RF65Agent : NSObject
@property(nonatomic) BOOL hasAudioFailure;
@end
@implementation RF65Agent @end

@interface RF65Controller : CallController
@property(nonatomic) NSURL *scratchDefault, *scratchSelected, *revealedURL;
@property(nonatomic) BOOL overridesSelection, rejectsReservation, rejectsBookmark;
@property(nonatomic) NSWindow *syntheticWindow;
@property(nonatomic) NSUInteger reservations, panels;
@property(nonatomic, copy) void (^folderCompletion)(NSURL *);
@end
@implementation RF65Controller
- (NSWindow *)window { return self.syntheticWindow; }
- (BOOL)isWindowLoaded { return self.syntheticWindow != nil; }
- (void)unsubscribeFromWindowFloatingChanges {}
- (NSURL *)defaultRecordingDirectoryURL { return self.scratchDefault; }
- (NSURL *)selectedRecordingDirectoryURL {
    return self.overridesSelection ? self.scratchSelected : [super selectedRecordingDirectoryURL];
}
- (NSURL *)reserveRecordingURLInDirectory:(NSURL *)directory filenameStem:(NSString *)stem
                               extension:(NSString *)extension error:(NSError **)error {
    self.reservations++;
    if (self.rejectsReservation) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:nil];
        return nil;
    }
    return [super reserveRecordingURLInDirectory:directory filenameStem:stem extension:extension error:error];
}
- (void)presentRecordingFolderPanelWithCompletion:(void (^)(NSURL *))completion {
    self.panels++; self.folderCompletion = completion;
}
- (NSData *)recordingFolderBookmarkForURL:(NSURL *)URL error:(NSError **)error {
    if (self.rejectsBookmark) return nil;
    self.overridesSelection = YES; self.scratchSelected = URL;
    return [@"synthetic explicit folder selection" dataUsingEncoding:NSUTF8StringEncoding];
}
- (void)revealRecordingDirectoryURL:(NSURL *)URL { self.revealedURL = URL; }
@end

@interface RecordingFeedbackTests : XCTestCase
@property(nonatomic) RF65Controller *controller;
@property(nonatomic) RF65Call *call;
@property(nonatomic) RF65Agent *agent;
@property(nonatomic) NSUserDefaults *defaults;
@property(nonatomic) NSString *suite;
@property(nonatomic) NSURL *scratch;
@end
@implementation RecordingFeedbackTests
- (void)setUp {
    [super setUp];
    self.suite = [@"test.telephone.recording65." stringByAppendingString:NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suite];
    [self.defaults setBool:YES forKey:@"AutomaticallyRecordCalls"];
    [self.defaults setObject:@"source" forKey:@"RecordingFormat"];
    self.scratch = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:self.suite] isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.scratch withIntermediateDirectories:YES attributes:nil error:nil]);
    RF65Scopes = [NSMutableDictionary new];
    RF65OriginalScopeStart = method_setImplementation(class_getInstanceMethod(NSURL.class, @selector(startAccessingSecurityScopedResource)), (IMP)RF65ScopeStart);
    RF65OriginalScopeStop = method_setImplementation(class_getInstanceMethod(NSURL.class, @selector(stopAccessingSecurityScopedResource)), (IMP)RF65ScopeStop);
    self.agent = [RF65Agent new];
    self.controller = [[RF65Controller alloc] initWithWindowNibName:@"Call" accountController:nil userAgent:(id)self.agent delegate:nil];
    [self.controller setValue:self.defaults forKey:@"defaults"];
    self.controller.scratchDefault = [self.scratch URLByAppendingPathComponent:@"default" isDirectory:YES];
    self.controller.displayedName = @"Synthetic recording test";
    self.controller.title = @"020 7946 0123";
    self.controller.status = @"Connected";
    self.call = [RF65Call new]; self.controller.call = self.call; self.controller.callActive = YES;
}
- (void)tearDown {
    self.controller.callActive = NO;
    [self.controller stopRecording];
    [self.controller.activeCallViewController stopCallTimer];
    [self.controller.activeCallViewController removeObservations];
    for (RF65Attempt *attempt in self.call.attempts) attempt.completion = nil;
    [self.controller.syntheticWindow orderOut:nil];
    self.controller.syntheticWindow = nil;
    self.controller = nil; self.call = nil;
    method_setImplementation(class_getInstanceMethod(NSURL.class, @selector(startAccessingSecurityScopedResource)), RF65OriginalScopeStart);
    method_setImplementation(class_getInstanceMethod(NSURL.class, @selector(stopAccessingSecurityScopedResource)), RF65OriginalScopeStop);
    RF65Scopes = nil;
    [self.defaults removePersistentDomainForName:self.suite];
    [NSFileManager.defaultManager removeItemAtURL:self.scratch error:nil];
    [super tearDown];
}
- (RF65Scope *)selectScratchFolder:(NSURL *)URL granted:(BOOL)granted {
    self.controller.overridesSelection = YES; self.controller.scratchSelected = URL;
    [self.defaults setObject:[@"synthetic bookmark" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"RecordingFolderBookmark"];
    RF65Scope *scope = [RF65Scope new]; scope.granted = granted;
    RF65Scopes[URL.absoluteString] = scope;
    return scope;
}
- (void)testDisabledStartingAndConfirmedCaptureAreDistinctAndPendingStartReservesOnlyOnce {
    [self.defaults setBool:NO forKey:@"AutomaticallyRecordCalls"];
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusDisabled);
    XCTAssertEqual(self.call.attempts.count, 0u);
    XCTAssertTrue([self.controller.recordingSummary containsString:@"off"]);
    [self.defaults setBool:YES forKey:@"AutomaticallyRecordCalls"];
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusStarting);
    XCTAssertNil(self.controller.recordingCapturedURL);
    XCTAssertTrue([self.controller.recordingDetail containsString:@"not yet been confirmed"]);
    [self.controller startAutomaticRecordingIfNeeded]; [self.controller retryRecording:nil];
    XCTAssertEqual(self.call.attempts.count, 1u); XCTAssertEqual(self.controller.reservations, 1u);
    [self.call completeAttempt:0 result:AKRecordingStartResultSuccess];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusCapturing);
    XCTAssertEqualObjects(self.controller.recordingCapturedURL, self.call.recordingURL);
    [self.controller startAutomaticRecordingIfNeeded]; [self.controller retryRecording:nil];
    XCTAssertEqual(self.call.attempts.count, 1u); XCTAssertEqual(self.controller.reservations, 1u);
}
- (void)testFailedStartStaysVisibleUntilExplicitRetryReadsCurrentFolderAndFormat {
    [self.controller startAutomaticRecordingIfNeeded];
    NSURL *first = self.call.attempts.firstObject.URL;
    [self.call completeAttempt:0 result:AKRecordingStartResultPrivateStorageFailure];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusFailed);
    XCTAssertEqual(self.controller.recordingStartResult, AKRecordingStartResultPrivateStorageFailure);
    XCTAssertNil(self.controller.recordingCapturedURL);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:first.path]);
    XCTAssertTrue([self.controller.recordingDetail containsString:@"No recording was created"]);
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.call.attempts.count, 1u);
    NSURL *chosen = [self.scratch URLByAppendingPathComponent:@"new settings" isDirectory:YES];
    [self selectScratchFolder:chosen granted:YES];
    [self.defaults setObject:@"mp3" forKey:@"RecordingFormat"];
    [self.controller retryRecording:nil];
    XCTAssertEqual(self.call.attempts.count, 2u);
    XCTAssertEqualObjects(self.call.attempts.lastObject.URL.pathExtension, @"mp3");
    XCTAssertEqualObjects(self.call.attempts.lastObject.URL.URLByDeletingLastPathComponent.path, chosen.path);
    XCTAssertNotEqualObjects(self.call.attempts.lastObject.URL, first);
}
- (void)testTypedNativeFailuresNeverClaimCapture {
    for (NSNumber *outcome in @[@(AKRecordingStartResultRecorderCreationFailure), @(AKRecordingStartResultConnectionFailure),
                               @(AKRecordingStartResultBusy), @(AKRecordingStartResultStaleCall), @(AKRecordingStartResultAudioFailure)]) {
        [self.controller retryRecording:nil];
        [self.call completeAttempt:self.call.attempts.count - 1 result:outcome.integerValue];
        XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusFailed);
        XCTAssertEqual(self.controller.recordingStartResult, outcome.integerValue);
        XCTAssertNil(self.controller.recordingCapturedURL);
        XCTAssertNotEqual(self.controller.recordingDetail.length, 0u);
    }
}
- (void)testSuccessCallbackWithoutAnActualCurrentCaptureCannotShowREC {
    [self.controller startAutomaticRecordingIfNeeded];
    RF65Attempt *attempt = self.call.attempts.firstObject;
    void (^completion)(AKRecordingStartResult) = attempt.completion;
    attempt.completion = nil;
    completion(AKRecordingStartResultSuccess);
    XCTAssertFalse(self.call.isRecording);
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusFailed);
    XCTAssertEqual(self.controller.recordingStartResult, AKRecordingStartResultStaleCall);
    XCTAssertNil(self.controller.recordingCapturedURL);
}
- (void)testAudioFailureIsVisibleWithoutReservingAndRecoveryCanStartCurrentCall {
    self.agent.hasAudioFailure = YES;
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusFailed);
    XCTAssertEqual(self.controller.recordingStartResult, AKRecordingStartResultAudioFailure);
    XCTAssertEqual(self.call.attempts.count, 0u); XCTAssertEqual(self.controller.reservations, 0u);
    self.agent.hasAudioFailure = NO;
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusStarting);
    XCTAssertEqual(self.call.attempts.count, 1u);
    [self.call completeAttempt:0 result:AKRecordingStartResultSuccess];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusCapturing);
}
- (void)testDeniedCustomFolderReportsFallbackAndRevealUsesActualFolder {
    NSURL *selected = [self.scratch URLByAppendingPathComponent:@"denied" isDirectory:YES];
    RF65Scope *scope = [self selectScratchFolder:selected granted:NO];
    NSData *bookmark = [self.defaults dataForKey:@"RecordingFolderBookmark"];
    [self.controller startAutomaticRecordingIfNeeded];
    [self.call completeAttempt:0 result:AKRecordingStartResultSuccess];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusCapturing);
    XCTAssertTrue(self.controller.recordingUsesFallback);
    XCTAssertEqual(self.controller.recordingDestinationReason, AKRecordingDestinationReasonAccessDenied);
    XCTAssertEqualObjects(self.controller.recordingDestinationFolderURL.path, self.controller.scratchDefault.path);
    XCTAssertTrue([self.controller.recordingSummary containsString:self.controller.scratchDefault.path]);
    [self.controller revealRecordingFolder:nil];
    XCTAssertEqualObjects(self.controller.revealedURL, self.controller.recordingDestinationFolderURL);
    XCTAssertEqualObjects([self.defaults dataForKey:@"RecordingFolderBookmark"], bookmark);
    XCTAssertEqual(scope.starts, 1u); XCTAssertEqual(scope.stops, 0u);
}
- (void)testInvalidBookmarkFallsBackWithoutAcquiringDefaultAsCustomScope {
    [self.defaults setObject:[@"not bookmark data" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"RecordingFolderBookmark"];
    RF65Scope *fallback = [RF65Scope new]; fallback.granted = YES;
    RF65Scopes[self.controller.scratchDefault.absoluteString] = fallback;
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingDestinationReason, AKRecordingDestinationReasonInvalidBookmark);
    XCTAssertTrue(self.controller.recordingUsesFallback);
    XCTAssertEqualObjects(self.call.attempts.firstObject.URL.URLByDeletingLastPathComponent.path, self.controller.scratchDefault.path);
    XCTAssertEqual(fallback.starts, 0u); XCTAssertEqual(fallback.stops, 0u);
}
- (void)testCustomFolderCreationFailureReleasesGrantedScopeBeforeFallback {
    NSURL *file = [self.scratch URLByAppendingPathComponent:@"regular-file"];
    XCTAssertTrue([[@"synthetic blocker" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES]);
    RF65Scope *scope = [self selectScratchFolder:[file URLByAppendingPathComponent:@"folder"] granted:YES];
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingDestinationReason, AKRecordingDestinationReasonCreationFailed);
    XCTAssertTrue(self.controller.recordingUsesFallback);
    XCTAssertEqual(scope.starts, 1u); XCTAssertEqual(scope.stops, 1u);
    XCTAssertNil(self.call.attempts.firstObject.scope);
    [self.call completeAttempt:0 result:AKRecordingStartResultSuccess];
    [self.controller stopRecording]; XCTAssertEqual(scope.stops, 1u);
}
- (void)testDefaultFolderCreationFailureDoesNotReachRecorderOrReserveAFile {
    NSURL *file = [self.scratch URLByAppendingPathComponent:@"regular-file"];
    XCTAssertTrue([[@"synthetic blocker" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES]);
    self.controller.scratchDefault = [file URLByAppendingPathComponent:@"folder"];
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusFailed);
    XCTAssertEqual(self.controller.recordingStartResult, AKRecordingStartResultInvalidDestination);
    XCTAssertEqual(self.call.attempts.count, 0u); XCTAssertEqual(self.controller.reservations, 0u);
    XCTAssertNil(self.controller.recordingCapturedURL);
}
- (void)testReservationFailureReleasesCustomScopeAndOffersExplicitRetry {
    RF65Scope *scope = [self selectScratchFolder:[self.scratch URLByAppendingPathComponent:@"selected"] granted:YES];
    self.controller.rejectsReservation = YES;
    [self.controller startAutomaticRecordingIfNeeded];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusFailed);
    XCTAssertEqual(self.controller.recordingDestinationReason, AKRecordingDestinationReasonReservationFailed);
    XCTAssertEqual(self.call.attempts.count, 0u);
    XCTAssertEqual(scope.starts, 1u); XCTAssertEqual(scope.stops, 1u);
    [self.controller startAutomaticRecordingIfNeeded]; XCTAssertEqual(self.controller.reservations, 1u);
    self.controller.rejectsReservation = NO; [self.controller retryRecording:nil];
    XCTAssertEqual(self.call.attempts.count, 1u);
    [self.call completeAttempt:0 result:AKRecordingStartResultSuccess];
    XCTAssertEqual(scope.stops, 1u, @"The current session owns its granted scope");
    [self.controller stopRecording]; [self.controller stopRecording];
    XCTAssertEqual(scope.starts, 2u); XCTAssertEqual(scope.stops, 2u);
}
- (void)testLateCompletionAfterStopCannotStopNewerSessionOnSameCall {
    [self.controller startAutomaticRecordingIfNeeded];
    [self.controller stopRecording];
    [self.controller startAutomaticRecordingIfNeeded];
    [self.call completeAttempt:1 result:AKRecordingStartResultSuccess];
    NSURL *current = self.controller.recordingCapturedURL;
    NSUInteger stops = self.call.stops;
    [self.call completeAttempt:0 result:AKRecordingStartResultSuccess];
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusCapturing);
    XCTAssertEqualObjects(self.controller.recordingCapturedURL, current);
    XCTAssertEqual(self.call.stops, stops); XCTAssertTrue(self.call.isRecording);
}
- (void)testLateCompletionAfterRebindOrCallEndCannotRecordLaterCall {
    [self.controller startAutomaticRecordingIfNeeded];
    RF65Call *old = self.call;
    self.call = [RF65Call new]; self.controller.call = self.call;
    [self.controller startAutomaticRecordingIfNeeded];
    [self.call completeAttempt:0 result:AKRecordingStartResultSuccess];
    NSURL *current = self.controller.recordingCapturedURL;
    [old completeAttempt:0 result:AKRecordingStartResultSuccess];
    XCTAssertEqualObjects(self.controller.recordingCapturedURL, current);
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusCapturing);
    [self.controller stopRecording];
    [self.controller startAutomaticRecordingIfNeeded];
    self.controller.callActive = NO;
    [self.call completeAttempt:1 result:AKRecordingStartResultSuccess];
    XCTAssertNotEqual(self.controller.recordingStatus, AKCallRecordingStatusCapturing);
    XCTAssertNil(self.controller.recordingCapturedURL);
}
- (void)testExplicitFolderSelectionUsesCurrentSettingsButStalePanelCannotStartLaterCall {
    [self.controller startAutomaticRecordingIfNeeded];
    [self.call completeAttempt:0 result:AKRecordingStartResultConnectionFailure];
    [self.controller chooseRecordingFolder:nil]; [self.controller chooseRecordingFolder:nil];
    XCTAssertEqual(self.controller.panels, 1u);
    NSURL *chosen = [self.scratch URLByAppendingPathComponent:@"chosen" isDirectory:YES];
    RF65Scope *scope = [RF65Scope new]; scope.granted = YES; RF65Scopes[chosen.absoluteString] = scope;
    [self.defaults setObject:@"mp3" forKey:@"RecordingFormat"];
    self.controller.folderCompletion(chosen);
    XCTAssertEqual(self.call.attempts.count, 2u);
    XCTAssertEqualObjects(self.call.attempts.lastObject.URL.pathExtension, @"mp3");
    XCTAssertEqualObjects(self.call.attempts.lastObject.URL.URLByDeletingLastPathComponent.path, chosen.path);
    [self.call completeAttempt:1 result:AKRecordingStartResultConnectionFailure];
    [self.controller chooseRecordingFolder:nil];
    self.call = [RF65Call new]; self.controller.call = self.call;
    self.controller.folderCompletion(chosen);
    XCTAssertEqual(self.call.attempts.count, 0u);
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusDisabled);
}
- (void)testCancelledOrRejectedFolderSelectionDoesNotReplaceSavedPreference {
    NSData *original = [@"original synthetic preference" dataUsingEncoding:NSUTF8StringEncoding];
    [self.defaults setObject:original forKey:@"RecordingFolderBookmark"];
    [self.controller chooseRecordingFolder:nil]; self.controller.folderCompletion(nil);
    XCTAssertEqualObjects([self.defaults dataForKey:@"RecordingFolderBookmark"], original);
    XCTAssertEqual(self.call.attempts.count, 0u);
    self.controller.rejectsBookmark = YES;
    [self.controller chooseRecordingFolder:nil];
    self.controller.folderCompletion([self.scratch URLByAppendingPathComponent:@"rejected"]);
    XCTAssertEqualObjects([self.defaults dataForKey:@"RecordingFolderBookmark"], original);
    XCTAssertEqual(self.controller.recordingStatus, AKCallRecordingStatusFailed);
    XCTAssertEqual(self.call.attempts.count, 0u);
}
- (void)attachNativeView:(NSView *)view name:(NSString *)name {
    [view.window displayIfNeeded]; [view displayIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    XCTAssertNotNil(bitmap);
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSImage *cached = [[NSImage alloc] initWithData:bitmap.TIFFRepresentation];
    NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
    [image lockFocus];
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [NSColor.windowBackgroundColor setFill]; NSRectFill(view.bounds);
        [cached drawInRect:view.bounds];
    }];
    [image unlockFocus];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = name; attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}
- (void)assertWrappedFieldFits:(NSTextField *)field inView:(NSView *)view {
    XCTAssertTrue(NSContainsRect(view.bounds, [field convertRect:field.bounds toView:view]));
    NSSize required = [field.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(field.bounds), CGFLOAT_MAX)];
    XCTAssertLessThanOrEqual(required.height, NSHeight(field.bounds) + 1);
}
- (void)testNativeRecordingSlotPopoverAndActionsFitBothAppearances {
    ActiveCallViewController *viewController = self.controller.activeCallViewController;
    NSView *card = viewController.view;
    self.controller.syntheticWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 112)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.controller.syntheticWindow.contentView = card;
    [self.controller.syntheticWindow orderFront:nil];
    NSButton *status = [viewController valueForKey:@"recordingStatusButton"];
    XCTAssertNotNil(status); XCTAssertTrue(status.hidden);
    XCTAssertEqual(status.target, viewController);
    XCTAssertEqual(status.action, @selector(showRecordingDetails:));
    // A long, private scratch destination exercises actual wrapping in the
    // fallback explanation without exposing a user's selected folder.
    self.controller.scratchDefault = [self.scratch URLByAppendingPathComponent:
        @"A synthetic fallback recordings folder with a deliberately long descriptive name" isDirectory:YES];
    [self.defaults setObject:[@"invalid native fixture bookmark" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"RecordingFolderBookmark"];
    for (NSString *appearanceName in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSString *appearance = [appearanceName isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light";
        card.appearance = [NSAppearance appearanceNamed:appearanceName];
        self.controller.syntheticWindow.appearance = card.appearance;
        NSUInteger attempt = self.call.attempts.count;
        [self.controller startAutomaticRecordingIfNeeded];
        for (NSString *state in @[@"starting", @"failed", @"capturing-fallback"]) {
            if ([state isEqualToString:@"failed"]) {
                [self.call completeAttempt:attempt result:AKRecordingStartResultRecorderCreationFailure];
            } else if ([state isEqualToString:@"capturing-fallback"]) {
                NSButton *retry = [viewController valueForKey:@"recordingRetryButton"];
                XCTAssertTrue(retry.enabled);
                XCTAssertTrue([NSApp sendAction:retry.action to:retry.target from:retry]);
                [self.call completeAttempt:attempt + 1 result:AKRecordingStartResultSuccess];
            }
            [card layoutSubtreeIfNeeded];
            XCTAssertEqualWithAccuracy(NSWidth(card.bounds), 300, 0.1);
            XCTAssertEqualWithAccuracy(NSWidth(status.frame), 52, 0.1);
            XCTAssertEqualWithAccuracy(NSHeight(status.frame), 14, 0.1);
            XCTAssertTrue(NSContainsRect(card.bounds, status.frame));
            XCTAssertFalse(status.hidden);
            XCTAssertLessThanOrEqual(status.attributedTitle.size.width, NSWidth(status.bounds));
            XCTAssertEqualObjects(status.accessibilityLabel, self.controller.recordingSummary);
            XCTAssertEqualObjects(status.accessibilityHelp, self.controller.recordingDetail);
            NSPopover *popover = [viewController valueForKey:@"recordingPopover"];
            if (!popover.isShown) XCTAssertTrue([NSApp sendAction:status.action to:status.target from:status]);
            popover = [viewController valueForKey:@"recordingPopover"];
            XCTAssertNotNil(popover.contentViewController);
            NSView *details = popover.contentViewController.view;
            details.appearance = card.appearance;
            [details layoutSubtreeIfNeeded];
            [self assertWrappedFieldFits:[viewController valueForKey:@"recordingSummaryField"] inView:details];
            [self assertWrappedFieldFits:[viewController valueForKey:@"recordingDetailField"] inView:details];
            for (NSString *key in @[@"recordingRetryButton", @"recordingChooseFolderButton", @"recordingRevealFolderButton"]) {
                NSButton *button = [viewController valueForKey:key];
                XCTAssertTrue(NSContainsRect(details.bounds, [button convertRect:button.bounds toView:details]));
                XCTAssertEqual(button.target, viewController);
            }
            [self attachNativeView:card name:[NSString stringWithFormat:@"recording65-card-%@-%@", state, appearance]];
            [self attachNativeView:details name:[NSString stringWithFormat:@"recording65-details-%@-%@", state, appearance]];
        }
        XCTAssertEqualObjects(status.attributedTitle.string, @"REC*");
        NSButton *reveal = [viewController valueForKey:@"recordingRevealFolderButton"];
        XCTAssertTrue(reveal.enabled);
        XCTAssertTrue([NSApp sendAction:reveal.action to:reveal.target from:reveal]);
        XCTAssertEqualObjects(self.controller.revealedURL, self.controller.recordingDestinationFolderURL);
        NSButton *choose = [viewController valueForKey:@"recordingChooseFolderButton"];
        XCTAssertTrue(choose.enabled);
        NSUInteger panels = self.controller.panels;
        XCTAssertTrue([NSApp sendAction:choose.action to:choose.target from:choose]);
        XCTAssertEqual(self.controller.panels, panels + 1);
        self.controller.folderCompletion(nil);
        [self.controller stopRecording]; XCTAssertTrue(status.hidden);
    }
}
@end
