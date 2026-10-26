//
//  CallController.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "CallController.h"

@import UseCases;

#import "AKActiveCallView.h"
#import "AKLiquidGlass.h"
#import "AKSIPURI.h"
#import "AKSIPURIFormatter.h"
#import "AKStereoRecording.h"
#import "AKSIPUserAgent.h"
#import "AKTelephoneNumberFormatter.h"

#import "AccountController.h"
#import "ActiveCallViewController.h"
#import "AppController.h"
#import "CallController+Protected.h"
#import "CallTransferController.h"
#import "EndedCallViewController.h"
#import "IncomingCallViewController.h"
#import "SIPResponseLocalization.h"

#import "Telephone-Swift.h"


// Window auto-close delay.
static const NSTimeInterval kCallWindowAutoCloseTime = 1.5;

// Redial button re-enable delay.
static const NSTimeInterval kRedialButtonReenableTime = 1.0;
static void *AKCallControlHoldObservationContext = &AKCallControlHoldObservationContext;

@interface CallController ()
- (NSRect)frameKeepingCallVisible:(NSRect)frame;

@property(nonatomic, readonly) AKSIPUserAgent *userAgent;

@property(nonatomic, readonly) NSUserDefaults *defaults;

// Keep the actual call status while a recoverable audio failure is displayed.
@property(nonatomic, copy) NSString *statusWithoutAudioFailure;
@property(nonatomic) BOOL hangUpPending;
@property(nonatomic) BOOL closeAfterHangUp;
@property(nonatomic) BOOL closed;
@property(nonatomic) BOOL callControlsRetired;
@property(nonatomic, readwrite) BOOL holdChangePending;
@property(nonatomic, readwrite) BOOL muteChangePending;
@property(nonatomic) NSUInteger callControlGeneration;
@property(nonatomic) AKSIPCall *observedControlCall;
- (void)observeCallControls;
- (void)removeCallControlObservations;
- (void)refreshCallControls;
@property(nonatomic, readwrite) AKCallRecordingStatus recordingStatus;
@property(nonatomic, readwrite) AKRecordingDestinationReason recordingDestinationReason;
@property(nonatomic, readwrite) AKRecordingDestinationReason recordingFallbackReason;
@property(nonatomic, readwrite) AKRecordingStartResult recordingStartResult;
@property(nonatomic, readwrite) BOOL recordingUsesFallback;
@property(nonatomic, readwrite, copy) NSURL *recordingDestinationFolderURL;
@property(nonatomic, readwrite, copy) NSURL *recordingCapturedURL;
@property(nonatomic) NSUInteger recordingAttemptGeneration;
@property(nonatomic) BOOL recordingStartPending;
@property(nonatomic) BOOL recordingFolderPanelPending;
@property(nonatomic) BOOL recordingFolderSelectionFailed;

// Call info view.
@property(nonatomic, strong) NSView *callInfoView;
- (void)refreshCompactPresentation;

// Closes call window.
- (void)closeCallWindow;

// Returns a unique destination for a new recording in the selected format.
- (NSURL *)newRecordingURLAccessingDirectory:(NSURL * _Nullable * _Nonnull)accessedDirectoryURL;

- (NSURL *)selectedRecordingDirectoryURL;
- (NSURL *)defaultRecordingDirectoryURL;
- (void)refreshRecordingPresentation;
- (NSURL *)reserveRecordingURLInDirectory:(NSURL *)directoryURL filenameStem:(NSString *)stem
                               extension:(NSString *)extension error:(NSError **)error;
- (void)presentRecordingFolderPanelWithCompletion:(void (^)(NSURL *URL))completion;
- (NSData *)recordingFolderBookmarkForURL:(NSURL *)URL error:(NSError **)error;
- (void)revealRecordingDirectoryURL:(NSURL *)URL;

@end

@implementation CallController

@synthesize callTransferController = _callTransferController;
@synthesize incomingCallViewController = _incomingCallViewController;
@synthesize status = _status;
@synthesize callActive = _callActive;

- (void)setStatus:(NSString *)status {
    self.statusWithoutAudioFailure = status;
    if (self.isCallActive && self.call != nil &&
        self.call.state != kAKSIPCallDisconnectedState && self.userAgent.hasAudioFailure) {
        _status = NSLocalizedString(@"Audio unavailable", @"Persistent status while call audio has failed.");
    } else {
        _status = [status copy];
    }
    [self refreshCompactPresentation];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingCompactWindowTitle {
    return [NSSet setWithArray:@[@"title", @"accountController.accountDescription",
                                @"accountController.callsShouldDisplayAccountInfo"]];
}

- (NSString *)compactWindowTitle {
    if (self.accountController.callsShouldDisplayAccountInfo && self.accountController.accountDescription.length > 0) {
        return self.accountController.accountDescription;
    }
    return self.title.length > 0 ? self.title : NSLocalizedString(@"Call", @"Window title.");
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingPresentationStatus {
    return [NSSet setWithObject:@"status"];
}

- (NSString *)presentationStatus {
    // The timer's original status remains intact for other consumers. The card
    // shows its duration separately so a running clock also has a named state.
    NSArray<NSString *> *parts = [self.status componentsSeparatedByString:@":"];
    BOOL clock = parts.count == 2 || parts.count == 3;
    NSCharacterSet *notDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    for (NSString *part in parts) {
        clock &= part.length == 2 && [part rangeOfCharacterFromSet:notDigits].location == NSNotFound;
    }
    return clock ? NSLocalizedString(@"Connected", @"Connected call status.") : (self.status ?: @"");
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingPresentationDuration {
    return [NSSet setWithArray:@[@"status", @"callStartTime", @"call.state"]];
}

- (NSString *)presentationDuration {
    if (self.callStartTime <= 0) return @"";
    NSInteger seconds = MAX(0, (NSInteger)(NSDate.timeIntervalSinceReferenceDate - self.callStartTime));
    if (self.call.state == kAKSIPCallDisconnectedState) seconds = MAX(0, self.call.duration);
    if (seconds < 3600) return [NSString stringWithFormat:@"%02ld:%02ld", (seconds / 60) % 60, seconds % 60];
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingPresentationTransferStatus {
    return [NSSet setWithArray:@[@"status", @"presentationDuration"]];
}

- (NSString *)presentationTransferStatus {
    if (self.callStartTime > 0 && [self.presentationStatus isEqualToString:NSLocalizedString(@"Connected", @"Connected call status.")]) {
        return self.presentationDuration;
    }
    return self.status ?: @"";
}

- (void)refreshCompactPresentation {
    if (!self.isWindowLoaded || ![self.windowNibName isEqualToString:@"Call"]) return;
    NSArray *controllers = @[(id)_activeCallViewController ?: NSNull.null,
                              (id)_incomingCallViewController ?: NSNull.null,
                              (id)_endedCallViewController ?: NSNull.null];
    for (id controller in controllers) {
        if ([controller isKindOfClass:NSViewController.class] && [(NSViewController *)controller isViewLoaded]) {
            [controller refreshPresentation];
        }
    }
    if (self.callInfoView != nil) {
        CGFloat delta = self.callInfoView.frame.size.height - self.window.contentView.frame.size.height;
        if (fabs(delta) > 0.1) {
            NSRect frame = self.window.frame;
            frame.size.height += delta;
            frame.origin.y -= delta;
            frame = [self frameKeepingCallVisible:frame];
            [self.window setFrame:frame display:YES];
        }
    }
}

- (NSRect)frameKeepingCallVisible:(NSRect)frame {
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    if (!screen) return frame;
    frame = [self.window constrainFrameRect:frame toScreen:screen];
    NSRect visible = screen.visibleFrame;
    // AppKit's standard constraints primarily keep the title bar reachable;
    // compact call actions must also stay above the Dock/visible-frame bottom.
    if (NSWidth(frame) <= NSWidth(visible))
        frame.origin.x = MIN(MAX(NSMinX(frame), NSMinX(visible)), NSMaxX(visible) - NSWidth(frame));
    if (NSHeight(frame) <= NSHeight(visible))
        frame.origin.y = MIN(MAX(NSMinY(frame), NSMinY(visible)), NSMaxY(visible) - NSHeight(frame));
    return frame;
}

- (void)setCallActive:(BOOL)callActive {
    _callActive = callActive;
    if (!callActive) {
        [self.intermediateStatusTimer invalidate];
        self.intermediateStatusTimer = nil;
        if (self.recordingStartPending || self.recordingStatus != AKCallRecordingStatusDisabled) [self stopRecording];
        [_activeCallViewController invalidateCallTimer];
        self.callControlGeneration++;
        self.holdChangePending = NO;
        self.muteChangePending = NO;
        self.hangUpPending = NO;
        [self removeCallControlObservations];
    } else {
        [self observeCallControls];
    }
    self.callControlsRetired = !callActive;
    [self refreshCallControls];
    // A call may be created after the user agent has already reported failure.
    // Ended calls must still display their normal final SIP status.
    [self setStatus:self.statusWithoutAudioFailure];
}

- (void)setCall:(AKSIPCall *)call {
    if (_call != call) {
        [self removeCallControlObservations];
        [_activeCallViewController invalidateCallTimer];
        self.callControlGeneration++;
        self.holdChangePending = NO;
        self.muteChangePending = NO;
        self.callControlsRetired = NO;
        [self.intermediateStatusTimer invalidate];
        self.intermediateStatusTimer = nil;
        self.callStartTime = 0;
        [self stopRecording];
        if (_call.delegate == self) {
            _call.delegate = nil;
        }
        _call = call;
        self.hangUpPending = NO;
        self.closeAfterHangUp = NO;
        self.closed = NO;
        _call.delegate = self;
        [self observeCallControls];
        _incomingCallViewController.representedObject = _call;
        _activeCallViewController.representedObject = _call;
        _endedCallViewController.representedObject = _call;
        [_callTransferController refreshSourceCallBinding];
        [_activeCallViewController.enteredDTMF setString:@""];
        if (_call != nil) {
            self.window.styleMask |= NSWindowStyleMaskClosable;
            [_activeCallViewController allowHangUp];
        }
        [self refreshCallControls];
    }
}

- (void)observeCallControls {
    if (self.closed || self.call == nil || self.observedControlCall == self.call) return;
    self.observedControlCall = self.call;
    [self.observedControlCall addObserver:self forKeyPath:@"localHold" options:0 context:AKCallControlHoldObservationContext];
    [self.observedControlCall addObserver:self forKeyPath:@"remoteHold" options:0 context:AKCallControlHoldObservationContext];
}

- (void)removeCallControlObservations {
    if (self.observedControlCall == nil) return;
    [self.observedControlCall removeObserver:self forKeyPath:@"localHold" context:AKCallControlHoldObservationContext];
    [self.observedControlCall removeObserver:self forKeyPath:@"remoteHold" context:AKCallControlHoldObservationContext];
    self.observedControlCall = nil;
}

- (void)refreshCallControls {
    [_activeCallViewController refreshControlPresentation];
}

- (BOOL)callControlsEnabled {
    return !self.closed && !self.hangUpPending && !self.callControlsRetired;
}

- (CallTransferController *)callTransferController {
    if (_callTransferController == nil) {
        _callTransferController = [[CallTransferController alloc] initWithSourceCallController:self userAgent:self.userAgent];
    }
    return _callTransferController;
}

- (IncomingCallViewController *)incomingCallViewController {
    if (_incomingCallViewController == nil) {
        _incomingCallViewController = [[IncomingCallViewController alloc] initWithCallController:self];
        [_incomingCallViewController setRepresentedObject:[self call]];
    }
    return _incomingCallViewController;
}

- (ActiveCallViewController *)activeCallViewController {
    if (_activeCallViewController == nil) {
        _activeCallViewController = [[ActiveCallViewController alloc] initWithNibName:@"ActiveCallView"
                                                                       callController:self];
        [_activeCallViewController setRepresentedObject:[self call]];
    }
    return _activeCallViewController;
}

- (EndedCallViewController *)endedCallViewController {
    if (_endedCallViewController == nil) {
        _endedCallViewController = [[EndedCallViewController alloc] initWithNibName:@"EndedCallView"
                                                                     callController:self];
        [_endedCallViewController setRepresentedObject:[self call]];
    }
    return _endedCallViewController;
}

- (void)setTitle:(NSString *)title {
    if (![_title isEqualToString:title]) {
        _title = [title copy];
        if (self.isWindowLoaded) {
            [self updateWindowTitle];
        }
    }
}

- (BOOL)acceptsPendingCallResult { return !self.closed; }

- (BOOL)isCallUnhandled {
    return self.call.isMissed;
}

- (instancetype)initWithWindowNibName:(NSString *)windowNibName
                    accountController:(AccountController *)accountController
                            userAgent:(AKSIPUserAgent *)userAgent
                             delegate:(id<CallControllerDelegate>)delegate {

    if ((self = [self initWithWindowNibName:windowNibName])) {
        _identifier = [NSUUID UUID].UUIDString;
        _accountController = accountController;
        _userAgent = userAgent;
        _delegate = delegate;
        _defaults = NSUserDefaults.standardUserDefaults;
        if (_userAgent != nil) {
            [NSNotificationCenter.defaultCenter addObserver:self
                                                   selector:@selector(SIPUserAgentAudioStateDidChange:)
                                                       name:AKSIPUserAgentAudioStateDidChangeNotification
                                                     object:_userAgent];
        }
    }
    return self;
}

- (void)dealloc {
    [self removeCallControlObservations];
    [_activeCallViewController invalidateCallTimer];
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                 name:AKSIPUserAgentAudioStateDidChangeNotification
                                               object:_userAgent];
    AKSIPCall *call = _call;
    if (call.delegate == self) {
        call.delegate = nil;
    }

    // The call owns its recording resources. Its completion captures only the
    // recording URLs, so this path never creates a weak reference to a controller
    // whose deallocation has already begun.
    [call stopRecording];
    [self unsubscribeFromWindowFloatingChanges];
}

- (NSString *)description {
    return [[self call] description];
}

- (void)awakeFromNib {
    self.window.movableByWindowBackground = YES;
    [self updateWindowFloating];
    [self subscribeToWindowFloatingChanges];
    [self updateWindowTitle];
    if ([self.windowNibName isEqualToString:@"Call"]) {
        // Preserve the former footer's conditional account binding in native
        // chrome while the remote number is now always present in the body.
        [self.window bind:NSTitleBinding toObject:self withKeyPath:@"compactWindowTitle" options:nil];
        self.window.autorecalculatesKeyViewLoop = YES;
    }
    NSRect frame = [[[self window] contentView] frame];
    frame.origin.x = 0.0;
    CGFloat minYBorderThickness = [[self window] contentBorderThicknessForEdge:NSMinYEdge];
    frame.origin.y = minYBorderThickness;
    frame.size.height -= minYBorderThickness;
    NSView *emptyCallInfoView = [[NSView alloc] initWithFrame:frame];
    [self.window.contentView addSubview:emptyCallInfoView];
    self.callInfoView = emptyCallInfoView;
}

- (void)setCallInfoViewResizingWindow:(NSView *)newView {
    if ([self.windowNibName isEqualToString:@"Call"]) newView.autoresizingMask = NSViewNotSizable;
    // Compute view size delta.
    NSSize currentCallInfoViewSize = [[self callInfoView] frame].size;
    NSSize newViewSize = [newView frame].size;
    CGFloat deltaWidth = newViewSize.width - currentCallInfoViewSize.width;
    CGFloat deltaHeight = newViewSize.height - currentCallInfoViewSize.height;
    
    if (currentCallInfoViewSize.width > 0.0 && currentCallInfoViewSize.height > 0.0 &&
        (fabs(deltaWidth) > 0.1 || fabs(deltaHeight) > 0.1)) {
        // Compute new window size.
        NSRect windowFrame = [[self window] frame];
        windowFrame.size.height += deltaHeight;
        windowFrame.origin.y -= deltaHeight;
        windowFrame.size.width += deltaWidth;
        
        windowFrame = [self frameKeepingCallVisible:windowFrame];
        // Set new window frame.
        [[self window] setFrame:windowFrame display:YES animate:YES];
    }
    
    CGFloat minYBorderThickness = [[self window] contentBorderThicknessForEdge:NSMinYEdge];
    if (minYBorderThickness > 0.0) {
        CGRect newViewFrame = [newView frame];
        newViewFrame.origin.y = minYBorderThickness;
        newView.frame = newViewFrame;
    }
    
    // Swap to the new view.
    if (self.callInfoView == nil) {
        [self.window.contentView addSubview:newView];
    } else {
        [self.window.contentView replaceSubview:self.callInfoView with:newView];
    }
    self.callInfoView = newView;

    // Installing the controls can add the backdrop during replaceSubview's
    // viewDidMoveToWindow callbacks. Restore its order after the swap finishes
    // so it cannot cover the pane or intercept its ordinary mouse clicks.
    NSView *contentView = self.window.contentView;
    for (NSView *subview in [contentView.subviews copy]) {
        if ([subview isKindOfClass:AKWindowMaterialView.class]) {
            [contentView addSubview:subview positioned:NSWindowBelow relativeTo:newView];
        }
    }

    [[self window] makeFirstResponder:newView];
}

- (void)acceptCall {
    [[self call] answer];
    [self removeUserNotification];
}

- (void)hangUpCall {
    if (self.hangUpPending || self.call == nil || self.call.state == kAKSIPCallDisconnectedState) return;
    self.hangUpPending = YES;
    [self refreshCallControls];
    [self.activeCallViewController disallowHangUp];
    AKSIPCall *call = self.call;
    NSUInteger generation = self.callControlGeneration;
    [call requestHangUpWithCompletion:^(BOOL accepted) {
        if (self.call != call || self.callControlGeneration != generation) return;
        self.hangUpPending = NO;
        [self refreshCallControls];
        if (!accepted && call.state != kAKSIPCallDisconnectedState) {
            self.closeAfterHangUp = NO;
            [self.activeCallViewController allowHangUp];
            [self setIntermediateStatus:NSLocalizedString(@"Could not end call. Try again.", @"Rejected local hangup.")];
            return;
        }
        self.callActive = NO;
        [self stopRecording];
        [self.activeCallViewController stopCallTimer];
        // Keep the delegate until the disconnect callback has collected history.
        [self setStatus:NSLocalizedString(@"call ended", @"Call ended.")];
        [self showEndedCallView];
        [self.activeCallViewController showHangUp];
        [self.activeCallViewController disallowHangUp];
        self.incomingCallViewController.acceptCallButton.enabled = NO;
        self.incomingCallViewController.declineCallButton.enabled = NO;
        [self removeUserNotification];
        if (self.closeAfterHangUp) {
            self.closeAfterHangUp = NO;
            [self.window close];
        } else if ([self.defaults boolForKey:UserDefaultsKeys.autoCloseCallWindow] &&
                   ![self isKindOfClass:CallTransferController.class]) {
            [self performSelector:@selector(closeCallWindow) withObject:nil afterDelay:kCallWindowAutoCloseTime];
        }
    }];
}

- (void)redial {
    NSString *destination = self.canonicalDestination ?: (self.redialURI.host.length ? self.redialURI.description : self.redialURI.user);
    if (destination.length == 0) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(closeCallWindow) object:nil];
    if ([DialPlanCoordinator.shared routeDestination:destination phoneLabel:self.phoneLabelFromAddressBook ?: @"" displayName:self.nameFromAddressBook ?: self.redialURI.displayName ?: @""]) {
        [self.window close];
    }
}

- (void)toggleCallHold {
    AKSIPCall *call = self.call;
    NSUInteger generation = self.callControlGeneration;
    [self requestToggleCallHoldWithCompletion:^(BOOL accepted) {
        if (self.call != call || self.closed || self.callControlGeneration != generation) return;
        if (!accepted) [self setIntermediateStatus:NSLocalizedString(@"Could not change hold. Try again.", @"Rejected local hold.")];
    }];
}

- (void)requestToggleCallHoldWithCompletion:(void (^)(BOOL))completion {
    if (!self.callControlsEnabled || self.holdChangePending || self.call == nil ||
        self.call.state != kAKSIPCallConfirmedState || self.call.isOnRemoteHold) { completion(NO); return; }
    AKSIPCall *call = self.call;
    NSUInteger generation = self.callControlGeneration;
    self.holdChangePending = YES;
    [self refreshCallControls];
    [call requestToggleHoldWithCompletion:^(BOOL accepted) {
        if (self.call != call || self.closed || self.callControlGeneration != generation) { completion(NO); return; }
        self.holdChangePending = NO;
        [self refreshCallControls];
        completion(accepted && self.call.state == kAKSIPCallConfirmedState);
    }];
}

- (void)toggleMicrophoneMute {
    if (!self.callControlsEnabled || self.muteChangePending || self.call == nil ||
        self.call.state != kAKSIPCallConfirmedState) return;
    AKSIPCall *call = self.call;
    NSUInteger generation = self.callControlGeneration;
    self.muteChangePending = YES;
    [self refreshCallControls];
    [call requestToggleMicrophoneMuteWithCompletion:^(BOOL accepted) {
        if (self.call != call || self.closed || self.callControlGeneration != generation) return;
        self.muteChangePending = NO;
        [self refreshCallControls];
        if (!accepted) {
            [self setIntermediateStatus:NSLocalizedString(@"Could not change mute. Try again.", @"Mute failed.")];
        } else if (call.isMicrophoneMuted && !self.isCallOnHold) {
            [self.activeCallViewController stopCallTimer];
            self.status = NSLocalizedString(@"mic muted", @"Microphone muted status text.");
        } else {
            [self setIntermediateStatus:call.isMicrophoneMuted ? NSLocalizedString(@"mic muted", @"Microphone muted status text.")
                                                              : NSLocalizedString(@"mic unmuted", @"Microphone unmuted status text.")];
        }
    }];
}

- (void)refreshRecordingPresentation {
    [_activeCallViewController refreshRecordingPresentation];
}

- (void)startAutomaticRecordingIfNeeded {
    AKSIPCall *call = self.call;
    if (call.isRecording && call.recordingURL != nil) {
        self.recordingCapturedURL = call.recordingURL;
        self.recordingDestinationFolderURL = [call.recordingURL URLByDeletingLastPathComponent];
        self.recordingStatus = AKCallRecordingStatusCapturing;
        [self refreshRecordingPresentation];
        return;
    }
    if (![self.defaults boolForKey:UserDefaultsKeys.automaticallyRecordCalls]) {
        if (!self.recordingStartPending) self.recordingStatus = AKCallRecordingStatusDisabled;
        [self refreshRecordingPresentation];
        return;
    }
    if (!self.isCallActive || call.state != kAKSIPCallConfirmedState || call == nil ||
        self.recordingStartPending ||
        (self.recordingStatus == AKCallRecordingStatusFailed &&
         self.recordingStartResult != AKRecordingStartResultAudioFailure)) return;
    if (self.userAgent.hasAudioFailure) {
        self.recordingStartResult = AKRecordingStartResultAudioFailure;
        self.recordingStatus = AKCallRecordingStatusFailed;
        [self refreshRecordingPresentation];
        return;
    }

    // Admit once before reserving a filename or acquiring a folder grant.
    self.recordingStartPending = YES;
    NSUInteger generation = ++self.recordingAttemptGeneration;
    self.recordingStatus = AKCallRecordingStatusStarting;
    self.recordingCapturedURL = nil;
    self.recordingDestinationFolderURL = nil;
    self.recordingDestinationReason = AKRecordingDestinationReasonNone;
    self.recordingFallbackReason = AKRecordingDestinationReasonNone;
    self.recordingUsesFallback = NO;
    self.recordingFolderSelectionFailed = NO;
    [self refreshRecordingPresentation];
    NSURL *accessedDirectoryURL = nil;
    NSURL *recordingURL = [self newRecordingURLAccessingDirectory:&accessedDirectoryURL];
    if (recordingURL == nil) {
        self.recordingStartPending = NO;
        self.recordingStartResult = AKRecordingStartResultInvalidDestination;
        self.recordingStatus = AKCallRecordingStatusFailed;
        [self refreshRecordingPresentation];
        return;
    }
    self.recordingDestinationFolderURL = [recordingURL URLByDeletingLastPathComponent];
    [self refreshRecordingPresentation];
    // The call consumes the reservation and scope on every result. Stale UI
    // completions never stop a possibly newer session on the same call.
    __weak typeof(self) weakSelf = self;
    [call startRecordingToURL:recordingURL accessedDirectoryURL:accessedDirectoryURL resultCompletion:^(AKRecordingStartResult result) {
        CallController *controller = weakSelf;
        if (controller == nil || controller.call != call ||
            controller.recordingAttemptGeneration != generation || !controller.isCallActive) return;
        controller.recordingStartPending = NO;
        controller.recordingStartResult = result;
        if (result == AKRecordingStartResultSuccess && call.isRecording && call.recordingURL != nil) {
            controller.recordingCapturedURL = call.recordingURL;
            controller.recordingDestinationFolderURL = [call.recordingURL URLByDeletingLastPathComponent];
            controller.recordingStatus = AKCallRecordingStatusCapturing;
        } else {
            controller.recordingCapturedURL = nil;
            controller.recordingStatus = AKCallRecordingStatusFailed;
            if (result == AKRecordingStartResultSuccess) controller.recordingStartResult = AKRecordingStartResultStaleCall;
        }
        [controller refreshRecordingPresentation];
    }];
}

- (void)stopRecording {
    ++self.recordingAttemptGeneration;
    self.recordingStartPending = NO;
    self.recordingStatus = AKCallRecordingStatusDisabled;
    self.recordingCapturedURL = nil;
    self.recordingDestinationFolderURL = nil;
    self.recordingDestinationReason = AKRecordingDestinationReasonNone;
    self.recordingFallbackReason = AKRecordingDestinationReasonNone;
    self.recordingUsesFallback = NO;
    self.recordingFolderSelectionFailed = NO;
    [self refreshRecordingPresentation];
    // Recorder IDs are cleared synchronously. Each call's asynchronous encoder
    // owns its own destination access, independent of this reusable window.
    [self.call stopRecording];
}

- (IBAction)retryRecording:(id)sender {
    if (self.recordingStartPending || self.call.isRecording) return;
    self.recordingStatus = AKCallRecordingStatusDisabled;
    [self startAutomaticRecordingIfNeeded];
}

- (IBAction)chooseRecordingFolder:(id)sender {
    if (self.recordingFolderPanelPending) return;
    self.recordingFolderPanelPending = YES;
    AKSIPCall *call = self.call;
    NSUInteger generation = self.recordingAttemptGeneration;
    __weak typeof(self) weakSelf = self;
    [self presentRecordingFolderPanelWithCompletion:^(NSURL *URL) {
        CallController *controller = weakSelf;
        if (controller == nil) return;
        controller.recordingFolderPanelPending = NO;
        if (URL == nil || controller.call != call || controller.recordingAttemptGeneration != generation) return;
        NSError *error = nil;
        NSData *bookmark = [controller recordingFolderBookmarkForURL:URL error:&error];
        if (bookmark == nil) {
            controller.recordingFolderSelectionFailed = YES;
            if (!controller.call.isRecording && !controller.recordingStartPending) {
                controller.recordingStatus = AKCallRecordingStatusFailed;
                controller.recordingStartResult = AKRecordingStartResultInvalidDestination;
                controller.recordingDestinationReason = AKRecordingDestinationReasonAccessDenied;
            }
            [controller refreshRecordingPresentation];
            return;
        }
        // A bookmark is changed only after this explicit native-panel action.
        [controller.defaults setObject:bookmark forKey:UserDefaultsKeys.recordingFolderBookmark];
        controller.recordingFolderSelectionFailed = NO;
        if (controller.isCallActive) {
            [controller retryRecording:nil];
        }
        [controller refreshRecordingPresentation];
    }];
}

- (void)presentRecordingFolderPanelWithCompletion:(void (^)(NSURL *))completion {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    panel.prompt = NSLocalizedString(@"Choose", @"Choose recordings folder panel button.");
    panel.message = NSLocalizedString(@"Choose a folder for new call recordings.", @"Choose recordings folder panel message.");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        completion(response == NSModalResponseOK ? panel.URL : nil);
    }];
}

- (NSData *)recordingFolderBookmarkForURL:(NSURL *)URL error:(NSError **)error {
    return [URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
        includingResourceValuesForKeys:nil relativeToURL:nil error:error];
}

- (IBAction)revealRecordingFolder:(id)sender {
    if (self.recordingDestinationFolderURL != nil) [self revealRecordingDirectoryURL:self.recordingDestinationFolderURL];
}

- (void)revealRecordingDirectoryURL:(NSURL *)URL {
    [NSWorkspace.sharedWorkspace openURL:URL];
}

- (NSString *)recordingExplanationForDestinationReason:(AKRecordingDestinationReason)reason {
    switch (reason) {
        case AKRecordingDestinationReasonInvalidBookmark: return NSLocalizedString(@"The saved folder permission could not be resolved.", @"Recording folder fallback reason.");
        case AKRecordingDestinationReasonAccessDenied: return NSLocalizedString(@"The selected folder could not be accessed.", @"Recording folder fallback reason.");
        case AKRecordingDestinationReasonCreationFailed: return NSLocalizedString(@"The selected folder could not be created or used.", @"Recording folder fallback reason.");
        case AKRecordingDestinationReasonReservationFailed: return NSLocalizedString(@"A new recording file could not be reserved.", @"Recording destination failure.");
        case AKRecordingDestinationReasonUnavailable: return NSLocalizedString(@"The recordings folder is unavailable.", @"Recording destination failure.");
        case AKRecordingDestinationReasonNone: return @"";
    }
}

- (NSString *)recordingDestinationExplanation {
    return [self recordingExplanationForDestinationReason:self.recordingDestinationReason];
}

- (NSString *)recordingSummary {
    if (self.recordingUsesFallback && self.recordingDestinationFolderURL != nil) {
        return [NSString stringWithFormat:NSLocalizedString(@"Fallback folder: %@. %@", @"Recording fallback destination and reason."),
                self.recordingDestinationFolderURL.path, [self recordingExplanationForDestinationReason:self.recordingFallbackReason]];
    }
    switch (self.recordingStatus) {
        case AKCallRecordingStatusDisabled: return NSLocalizedString(@"Automatic recording is off", @"Recording state.");
        case AKCallRecordingStatusStarting: return NSLocalizedString(@"Starting recording…", @"Recording state.");
        case AKCallRecordingStatusFailed: return NSLocalizedString(@"Recording failed to start", @"Recording state.");
        case AKCallRecordingStatusCapturing: return NSLocalizedString(@"Recording in progress", @"Recording state.");
    }
}

- (NSString *)recordingDetail {
    NSString *detail = @"";
    if (self.recordingStatus == AKCallRecordingStatusCapturing) {
        detail = [NSString stringWithFormat:NSLocalizedString(@"Recording in progress. New audio will be saved to %@.", @"Actual recording destination."), self.recordingDestinationFolderURL.path ?: @""];
    } else if (self.recordingStatus == AKCallRecordingStatusStarting) {
        detail = NSLocalizedString(@"Recording is starting. Audio capture has not yet been confirmed.", @"Pending recording explanation.");
    } else if (self.recordingStatus == AKCallRecordingStatusFailed) {
        switch (self.recordingStartResult) {
            case AKRecordingStartResultAudioFailure: detail = NSLocalizedString(@"Call audio is unavailable. Recording can resume after audio recovers.", @"Recording start failure."); break;
            case AKRecordingStartResultPrivateStorageFailure: detail = NSLocalizedString(@"Private recording recovery storage could not be prepared. No recording was created by this attempt.", @"Recording start failure."); break;
            case AKRecordingStartResultRecorderCreationFailure: detail = NSLocalizedString(@"The audio recorder could not be created. No recording was created by this attempt.", @"Recording start failure."); break;
            case AKRecordingStartResultConnectionFailure: detail = NSLocalizedString(@"The recorder could not connect to call audio. No recording was created by this attempt.", @"Recording start failure."); break;
            case AKRecordingStartResultBusy: detail = NSLocalizedString(@"A recording operation is already in progress. Try again when it finishes.", @"Recording start failure."); break;
            case AKRecordingStartResultStaleCall: detail = NSLocalizedString(@"The call changed before recording could start. No recording was created by this attempt.", @"Recording start failure."); break;
            default: detail = self.recordingDestinationExplanation.length ? self.recordingDestinationExplanation : NSLocalizedString(@"The recording destination could not be prepared. No recording was created by this attempt.", @"Recording start failure."); break;
        }
        detail = [detail stringByAppendingString:NSLocalizedString(@" Retry uses your current recording settings. Earlier audio cannot be recovered.", @"Recording retry explanation.")];
    }
    if (self.recordingFolderSelectionFailed) detail = [detail stringByAppendingString:NSLocalizedString(@" The chosen folder permission could not be saved. Choose another folder.", @"Recording folder bookmark failure.")];
    return detail;
}

- (NSURL *)newRecordingURLAccessingDirectory:(NSURL **)accessedDirectoryURL {
    *accessedDirectoryURL = nil;
    BOOL usesCustomDirectory = [self.defaults dataForKey:UserDefaultsKeys.recordingFolderBookmark] != nil;
    NSURL *directoryURL = [self selectedRecordingDirectoryURL];
    if (usesCustomDirectory && directoryURL == nil) {
        self.recordingDestinationReason = AKRecordingDestinationReasonInvalidBookmark;
        self.recordingFallbackReason = AKRecordingDestinationReasonInvalidBookmark;
        self.recordingUsesFallback = YES;
        directoryURL = [self defaultRecordingDirectoryURL];
    } else if (usesCustomDirectory) {
        if ([directoryURL startAccessingSecurityScopedResource]) {
            *accessedDirectoryURL = directoryURL;
        } else {
            self.recordingDestinationReason = AKRecordingDestinationReasonAccessDenied;
            self.recordingFallbackReason = AKRecordingDestinationReasonAccessDenied;
            self.recordingUsesFallback = YES;
            directoryURL = [self defaultRecordingDirectoryURL];
        }
    }
    if (directoryURL == nil) {
        self.recordingDestinationReason = AKRecordingDestinationReasonUnavailable;
        return nil;
    }

    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                                withIntermediateDirectories:YES attributes:nil error:&error]) {
        [*accessedDirectoryURL stopAccessingSecurityScopedResource];
        *accessedDirectoryURL = nil;
        if (!usesCustomDirectory || self.recordingUsesFallback) {
            self.recordingDestinationReason = AKRecordingDestinationReasonCreationFailed;
            return nil;
        }
        self.recordingDestinationReason = AKRecordingDestinationReasonCreationFailed;
        self.recordingFallbackReason = AKRecordingDestinationReasonCreationFailed;
        self.recordingUsesFallback = YES;
        directoryURL = [self defaultRecordingDirectoryURL];
        if (directoryURL == nil ||
            ![NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                                     withIntermediateDirectories:YES attributes:nil error:&error]) return nil;
    }
    self.recordingDestinationFolderURL = directoryURL;

    NSString *party = self.displayedName.length > 0 ? self.displayedName : self.call.remoteURI.user;
    if (party.length == 0) {
        party = @"Unknown";
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. "];
    NSArray<NSString *> *parts = [party componentsSeparatedByCharactersInSet:allowed.invertedSet];
    party = [parts componentsJoinedByString:@"-"];
    while ([party containsString:@"--"]) {
        party = [party stringByReplacingOccurrencesOfString:@"--" withString:@"-"];
    }
    if (party.length > 60) {
        party = [party substringToIndex:60];
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH.mm.ss";
    NSString *timestamp = [formatter stringFromDate:NSDate.date];
    NSString *format = [self.defaults stringForKey:UserDefaultsKeys.recordingFormat];
    NSString *extension = [format isEqualToString:@"mp3"] ? @"mp3" : ([format isEqualToString:@"source"] ? @"wav" : @"ogg");
    NSString *filenameStem = [NSString stringWithFormat:@"%@ - %@ - %@",
                              timestamp,
                              self.call.isIncoming ? @"Incoming" : @"Outgoing",
                              party];
    NSURL *reservedURL = [self reserveRecordingURLInDirectory:directoryURL filenameStem:filenameStem extension:extension error:&error];
    if (reservedURL == nil) {
        self.recordingDestinationReason = AKRecordingDestinationReasonReservationFailed;
        [*accessedDirectoryURL stopAccessingSecurityScopedResource];
        *accessedDirectoryURL = nil;
    }
    return reservedURL;
}

- (NSURL *)reserveRecordingURLInDirectory:(NSURL *)directoryURL filenameStem:(NSString *)stem
                               extension:(NSString *)extension error:(NSError **)error {
    return AKReserveRecordingURL(directoryURL, stem, extension, error);
}

- (NSURL *)selectedRecordingDirectoryURL {
    NSData *bookmark = [self.defaults dataForKey:UserDefaultsKeys.recordingFolderBookmark];
    if (bookmark == nil) return [self defaultRecordingDirectoryURL];
    BOOL stale = NO;
    // Do not replace a failed custom resolution with Downloads here: only the
    // caller knows whether a security-scope request belongs to a custom URL.
    NSURL *URL = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope
                                    relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
    if (URL != nil && stale) {
        NSData *refreshed = [URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                        includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
        if (refreshed != nil) [self.defaults setObject:refreshed forKey:UserDefaultsKeys.recordingFolderBookmark];
    }
    return URL;
}

- (NSURL *)defaultRecordingDirectoryURL {
    NSURL *downloadsURL = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory
                                                               inDomains:NSUserDomainMask].firstObject;
    return [downloadsURL URLByAppendingPathComponent:@"jps Telephone Recordings" isDirectory:YES];
}

- (void)setIntermediateStatus:(NSString *)newIntermediateStatus {
    if ([self intermediateStatusTimer] != nil) {
        [[self intermediateStatusTimer] invalidate];
    }
    
    [[self activeCallViewController] stopCallTimer];
    [self setStatus:newIntermediateStatus];
    [self setIntermediateStatusTimer:
     [NSTimer scheduledTimerWithTimeInterval:3.0
                                      target:self
                                    selector:@selector(intermediateStatusTimerTick:)
                                    userInfo:nil
                                     repeats:NO]];
}

- (void)intermediateStatusTimerTick:(NSTimer *)theTimer {
    if ([[self call] isOnLocalHold]) {
        [self setStatus:NSLocalizedString(@"on hold", @"Call on local hold status text.")];
    } else if ([[self call] isOnRemoteHold]) {
        [self setStatus:
         NSLocalizedString(@"on remote hold", @"Call on remote hold status text.")];
    } else if ([[self call] isMicrophoneMuted]) {
        [self setStatus:
         NSLocalizedString(@"mic muted", @"Microphone muted status text.")];
    } else if ([[self call] isActive]) {
        [self setStatus:NSLocalizedString(@"Connected", @"Connected call status.")];
        [[self activeCallViewController] startCallTimer];
    }
    
    [self setIntermediateStatusTimer:nil];
}

- (void)closeCallWindow {
    if ([[self window] isVisible]) {
        [[self window] performClose:self];
    }
}

- (void)prepareForCall {
    self.window.styleMask &= ~NSWindowStyleMaskClosable;
    [self showActiveCallView];
    [self.activeCallViewController showProgress];
    [self.activeCallViewController disallowHangUp];
    [self refreshCallControls];
}

- (void)showActiveCallView {
    [self showViewController:self.activeCallViewController];
    [self refreshCallControls];
}

- (void)showEndedCallView {
    [_activeCallViewController invalidateCallTimer];
    [self refreshCallControls];
    self.window.styleMask |= NSWindowStyleMaskClosable;
    [self showViewController:self.endedCallViewController];
}

- (void)showIncomingCallView {
    [self showViewController:self.incomingCallViewController];
}

- (void)showViewController:(NSViewController *)viewController {
    if ([self shouldShowViewController:viewController]) {
        if (viewController != _activeCallViewController) {
            [_activeCallViewController invalidateCallTimer];
            [_activeCallViewController closeKeypad];
        }
        [self setCallInfoViewResizingWindow:viewController.view];
    }
}

- (BOOL)shouldShowViewController:(NSViewController *)viewController {
    return ![self.callInfoView isEqual:viewController.view];
}

- (void)removeOrShowUserNotificationOnDisconnectIfNeeded {
    if (![NSApp isActive]) {
        if (self.isCallUnhandled) {
            // Missed calls are shown in call history.
            [self removeUserNotification];
        } else {
            // Notify about an ended call when the app is not visible.
            [self showUserNotification];
        }
    }
}

- (void)removeUserNotification {
    NSUserNotificationCenter *center = NSUserNotificationCenter.defaultUserNotificationCenter;
    for (NSUserNotification *notification in center.deliveredNotifications) {
        if ([notification.identifier isEqualToString:self.identifier]) {
            [center removeDeliveredNotification:notification];
            break;
        }
    }
}

- (void)showUserNotification {
    NSString *notificationTitle;
    if ([[self nameFromAddressBook] length] > 0) {
        notificationTitle = [self nameFromAddressBook];
    } else if ([[self enteredCallDestination] length] > 0) {
        AKTelephoneNumberFormatter *telephoneNumberFormatter = [[AKTelephoneNumberFormatter alloc] init];
        if ([[self enteredCallDestination] ak_isTelephoneNumber] && [self.defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
            notificationTitle = [telephoneNumberFormatter stringForObjectValue:[self enteredCallDestination]];
        } else {
            notificationTitle = [self enteredCallDestination];
        }
    } else {
        AKSIPURIFormatter *SIPURIFormatter = [[AKSIPURIFormatter alloc] init];
        [SIPURIFormatter setFormatsTelephoneNumbers:[self.defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]];
        [SIPURIFormatter setTelephoneNumberFormatterSplitsLastFourDigits:
         [self.defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
        notificationTitle = [SIPURIFormatter stringForObjectValue:[[self call] remoteURI]];
    }
    NSUserNotification *userNotification = [[NSUserNotification alloc] init];
    userNotification.identifier = self.identifier;
    userNotification.title = notificationTitle;
    userNotification.informativeText = self.status;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
}

- (void)updateWindowTitle {
    self.window.title = [self.windowNibName isEqualToString:@"Call"] ? self.compactWindowTitle
                          : (self.title.length > 0 ? self.title : NSLocalizedString(@"Call", @"Window title."));
}


#pragma mark -
#pragma mark NSWindow delegate methods

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (self.isCallActive) {
        self.closeAfterHangUp = YES;
        [self hangUpCall];
        return NO;
    }
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    self.closed = YES;
    [self.intermediateStatusTimer invalidate];
    self.intermediateStatusTimer = nil;
    self.callControlGeneration++;
    self.holdChangePending = NO;
    self.muteChangePending = NO;
    [self removeCallControlObservations];
    [_activeCallViewController invalidateCallTimer];
    [self refreshCallControls];
    if (self.isCallActive) [self hangUpCall];
    [self.delegate callControllerWillClose:self];
    [_incomingCallViewController removeObservations];
    [_activeCallViewController removeObservations];
    [_endedCallViewController removeObservations];
    if ([self.windowNibName isEqualToString:@"Call"]) [self.window unbind:NSTitleBinding];
}

- (NSRect)window:(NSWindow *)window willPositionSheet:(NSWindow *)sheet usingRect:(NSRect)rect {
    rect.origin.y = [self.window contentRectForFrameRect:self.window.frame].size.height;
    return rect;
}


#pragma mark -
#pragma mark AKSIPCallDelegate

- (void)SIPUserAgentAudioStateDidChange:(NSNotification *)notification {
    if (self.userAgent == nil || notification.object != self.userAgent) {
        return;
    }
    [self refreshCallControls];
    if (self.userAgent.hasAudioFailure) {
        // Finalize the existing recording, but leave SIP signaling and the call
        // timer alone. A silent recording must not appear to keep running.
        [self stopRecording];
        if (self.isCallActive && [self.defaults boolForKey:UserDefaultsKeys.automaticallyRecordCalls]) {
            self.recordingStatus = AKCallRecordingStatusFailed;
            self.recordingStartResult = AKRecordingStartResultAudioFailure;
            [self refreshRecordingPresentation];
        }
        [self setStatus:self.statusWithoutAudioFailure];
        return;
    }
    [self setStatus:self.statusWithoutAudioFailure];
    // Teardown also clears the failure latch. Restore the cached status without
    // asking native call/media state after the user agent has stopped.
    if (!self.userAgent.isStarted || !self.isCallActive || self.call == nil ||
        self.call.state == kAKSIPCallDisconnectedState) {
        return;
    }

    if (self.call.isOnLocalHold) {
        [self setStatus:NSLocalizedString(@"on hold", @"Call on local hold status text.")];
    } else if (self.call.isOnRemoteHold) {
        [self setStatus:NSLocalizedString(@"on remote hold", @"Call on remote hold status text.")];
    } else if (self.call.isMicrophoneMuted) {
        [self setStatus:NSLocalizedString(@"mic muted", @"Microphone muted status text.")];
    } else if (self.call.state == kAKSIPCallConfirmedState) {
        [_activeCallViewController callTimerTick:nil];
    }
    // Only a subsequent native active-media notification may resume recording.
}

- (void)SIPCallCalling:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
}

- (void)SIPCallIncoming:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
}

- (void)SIPCallConnecting:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
}

- (void)SIPCallEarly:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
    if (![[self call] isIncoming]) {
        NSNumber *sipEventCode = [notification userInfo][@"AKSIPEventCode"];
        if ([sipEventCode isEqualToNumber:@(PJSIP_SC_RINGING)]) {
            [self.activeCallViewController showHangUp];
            [self setStatus:NSLocalizedString(@"ringing", @"Remote party ringing.")];
        }
    }
}

- (void)SIPCallDidConfirm:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
    [self setCallStartTime:[NSDate timeIntervalSinceReferenceDate]];
    [self showActiveCallView];
    [self.activeCallViewController showHangUp];
    [self setStatus:@"00:00"];
    [[self activeCallViewController] startCallTimer];
    [self startAutomaticRecordingIfNeeded];
}

- (void)SIPCallDidDisconnect:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self setCallActive:NO];
    [self stopRecording];
    [[self activeCallViewController] stopCallTimer];
    
    switch ([[self call] lastStatus]) {
        case PJSIP_SC_OK:
            [self setStatus:NSLocalizedString(@"call ended", @"Call ended.")];
            break;
            
        case PJSIP_SC_NOT_FOUND:
            [self setStatus:NSLocalizedString(@"Address Not Found", @"Address not found.")];
            break;
            
        case PJSIP_SC_REQUEST_TERMINATED:
            [self setStatus:NSLocalizedString(@"call ended", @"Call ended.")];
            break;
            
        case PJSIP_SC_BUSY_HERE:
        case PJSIP_SC_BUSY_EVERYWHERE:
            [self setStatus:NSLocalizedString(@"busy", @"Busy.")];
            break;
            
        case PJSIP_SC_DECLINE:
            [self setStatus:NSLocalizedString(@"call declined", @"Call declined.")];
            break;
            
        default:
            // Preserve provider diagnostic text for non-standard response codes.
            [self setStatus:LocalizedStringForSIPResponseCode([[self call] lastStatus])
                ?: [[self call] lastStatusText]];
            break;
    }

    [self showEndedCallView];
    
    // Disable the redial button to re-enable it after some delay to prevent accidental clicking on in instead of
    // clicking on the hang-up button. Don't forget to re-enable it below!
    [[[self endedCallViewController] redialButton] setEnabled:NO];
    
    [self.activeCallViewController showHangUp];
    [self.activeCallViewController disallowHangUp];
    [[[self incomingCallViewController] acceptCallButton] setEnabled:NO];
    [[[self incomingCallViewController] declineCallButton] setEnabled:NO];
    
    [NSTimer scheduledTimerWithTimeInterval:kRedialButtonReenableTime
                                     target:[self endedCallViewController]
                                   selector:@selector(enableRedialButtonTick:)
                                   userInfo:nil
                                    repeats:NO];
    
    [self removeOrShowUserNotificationOnDisconnectIfNeeded];
    
    // Optionally close disconnected call window.
    BOOL shouldCloseWindow = [self.defaults boolForKey:UserDefaultsKeys.autoCloseCallWindow];
    BOOL shouldCloseMissedWindow = [self.defaults boolForKey:UserDefaultsKeys.autoCloseMissedCallWindow];
    BOOL missed = [self isCallUnhandled];
    
    if (![self isKindOfClass:[CallTransferController class]]) {
        if ((!missed && shouldCloseWindow) || (missed && shouldCloseMissedWindow)) {
            [self performSelector:@selector(closeCallWindow) withObject:nil afterDelay:kCallWindowAutoCloseTime];
        }
    }
}

- (void)SIPCallMediaDidBecomeActive:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
    if (!self.userAgent.hasAudioFailure) {
        [self startAutomaticRecordingIfNeeded];
        [self.call refreshRecordingConnections];
    }
    // A local audio failure must not suppress the signaling transition out of
    // hold. The persistent audio warning is applied separately by setStatus:.
    if ([self isCallOnHold]) {  // Call is being taken off hold.
        [self setCallOnHold:NO];
        
        [self setIntermediateStatus:NSLocalizedString(@"off hold", @"Call has been taken off hold status text.")];
    }
}

- (void)SIPCallDidLocalHold:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
    [self setCallOnHold:YES];
    [[self activeCallViewController] stopCallTimer];
    [self setStatus:NSLocalizedString(@"on hold", @"Call on local hold status text.")];
}

- (void)SIPCallDidRemoteHold:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
    [self setCallOnHold:YES];
    [[self activeCallViewController] stopCallTimer];
    [self setStatus:NSLocalizedString(@"on remote hold", @"Call on remote hold status text.")];
}

- (void)SIPCallTransferStatusDidChange:(NSNotification *)notification {
    if (notification.object != self.call || self.closed) return;
    [self refreshCallControls];
    NSDictionary *userInfo = [notification userInfo];
    BOOL isFinal = [userInfo[@"AKFinalTransferNotification"] boolValue];
    
    if (isFinal && [[self call] transferStatus] == PJSIP_SC_OK) {
        [self hangUpCall];
        [self setStatus:NSLocalizedString(@"call transferred", @"Call transferred.")];
    }
}

#pragma mark - Window floating

- (void)updateWindowFloating {
    self.window.level = [self.defaults boolForKey:UserDefaultsKeys.keepCallWindowOnTop] ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

- (void)subscribeToWindowFloatingChanges {
    [self.defaults addObserver:self forKeyPath:UserDefaultsKeys.keepCallWindowOnTop options:0 context:NULL];
}

- (void)unsubscribeFromWindowFloatingChanges {
    [self.defaults removeObserver:self forKeyPath:UserDefaultsKeys.keepCallWindowOnTop];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == AKCallControlHoldObservationContext) {
        // NONE/ERROR media changes can clear cached hold flags without a named
        // hold/active notification. Observe only this call's main-owned cache.
        if (object == self.call && !self.closed) [self refreshCallControls];
    } else if (object == self.defaults && [keyPath isEqualToString:UserDefaultsKeys.keepCallWindowOnTop]) {
        [self updateWindowFloating];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
