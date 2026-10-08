//
//  CallTransferController.m
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

#import "CallTransferController.h"

#import "AKSIPCall.h"

#import "AccountController.h"
#import "ActiveCallTransferViewController.h"
#import "CallController+Protected.h"
#import "EndedCallTransferViewController.h"


@interface CallTransferController ()

// Source call controller.
@property(nonatomic, weak) CallController *sourceCallController;

// Active account transfer view controller.
@property(nonatomic, strong) ActiveAccountTransferViewController *activeAccountTransferViewController;

// A Boolean value indicating whether the source call has been transferred.
@property(nonatomic, assign) BOOL sourceCallTransferred;
@property(nonatomic, strong) AKSIPCall *observedSourceCall;
@property(nonatomic) BOOL introducedSourceHold;
@property(nonatomic) BOOL sourceHoldRequestPending;
@property(nonatomic) BOOL restoreSourceHoldWhenConfirmed;
- (void)sourceHoldDidConfirm:(NSNotification *)notification;

@end


@implementation CallTransferController

- (void)setSourceCallController:(CallController *)callController {
    _sourceCallController = callController;
    [self refreshSourceCallBinding];
}

- (void)refreshSourceCallBinding {
    AKSIPCall *current = self.sourceCallController.call;
    if (self.observedSourceCall == current) return;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    if (self.observedSourceCall != nil) {
        [nc removeObserver:self name:AKSIPCallTransferStatusDidChangeNotification object:self.observedSourceCall];
        [nc removeObserver:self name:AKSIPCallDidLocalHoldNotification object:self.observedSourceCall];
    }
    self.observedSourceCall = current;
    self.sourceCallTransferred = NO;
    self.introducedSourceHold = NO;
    self.sourceHoldRequestPending = NO;
    self.restoreSourceHoldWhenConfirmed = NO;
    if (current != nil) {
        [nc addObserver:self selector:@selector(sourceCallControllerSIPCallTransferStatusDidChange:)
                   name:AKSIPCallTransferStatusDidChangeNotification object:current];
        [nc addObserver:self selector:@selector(sourceHoldDidConfirm:)
                   name:AKSIPCallDidLocalHoldNotification object:current];
    }
}

- (void)beginTransferSetup {
    [self refreshSourceCallBinding];
    self.restoreSourceHoldWhenConfirmed = NO;
    if (self.sourceHoldRequestPending) return;
    self.introducedSourceHold = !self.sourceCallController.isCallOnHold && !self.sourceCallController.call.isOnLocalHold;
    if (!self.introducedSourceHold) return;
    AKSIPCall *source = self.observedSourceCall;
    self.sourceHoldRequestPending = YES;
    [self.sourceCallController requestToggleCallHoldWithCompletion:^(BOOL accepted) {
        if (self.observedSourceCall != source) return;
        if (!accepted) {
            self.sourceHoldRequestPending = NO;
            self.introducedSourceHold = NO;
            self.restoreSourceHoldWhenConfirmed = NO;
            [self.sourceCallController setIntermediateStatus:NSLocalizedString(@"Could not change hold. Try again.", @"Rejected transfer setup hold.")];
        } else if (source.isOnLocalHold) {
            [self sourceHoldDidConfirm:nil];
        }
    }];
}

- (void)sourceHoldDidConfirm:(NSNotification *)notification {
    self.sourceHoldRequestPending = NO;
    if (self.restoreSourceHoldWhenConfirmed && self.introducedSourceHold && self.sourceCallController.isCallActive && self.observedSourceCall.isOnLocalHold) {
        self.restoreSourceHoldWhenConfirmed = NO;
        self.introducedSourceHold = NO;
        [self.sourceCallController toggleCallHold];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (instancetype)initWithSourceCallController:(CallController *)callController userAgent:(AKSIPUserAgent *)userAgent {
    AccountController *accountController = callController.accountController;
    if ((self = [self initWithWindowNibName:@"CallTransfer"
                          accountController:accountController
                                  userAgent:userAgent
                                   delegate:accountController])) {
        [self setSourceCallController:callController];
        _activeAccountTransferViewController = [[ActiveAccountTransferViewController alloc] initWithAccountController:accountController];
    }
    return self;
}

- (void)windowDidLoad {
    [self showInitialState:self];
}

- (void)transferCall {
    [[[self sourceCallController] call] attendedTransferToCall:[self call]];
}

- (IBAction)closeSheet:(id)sender {
    if (self.introducedSourceHold && self.sourceCallController.isCallActive) {
        if (self.sourceCallController.isCallOnHold || self.observedSourceCall.isOnLocalHold) {
            [self.sourceCallController toggleCallHold];
            self.introducedSourceHold = NO;
        } else if (self.sourceHoldRequestPending) {
            // Closing before the asynchronous hold acknowledgement must still
            // undo the hold this sheet introduced when its media callback arrives.
            self.restoreSourceHoldWhenConfirmed = YES;
        }
    } else {
        self.introducedSourceHold = NO;
    }
    [[[self window] sheetParent] endSheet:[self window]];
}

- (IBAction)showInitialState:(id)sender {
    if ([self isCallActive]) {
        [self hangUpCall];
    }
    
    if (![[self sourceCallController] isCallActive]) {
        [self closeSheet:self];
    }
    
    [self showActiveAccountTransferView];
    [self makeCallDestinationFieldFirstResponder];
}

- (void)showActiveAccountTransferView {
    [self setCallInfoViewResizingWindow:[[self activeAccountTransferViewController] view]];
}

- (void)makeCallDestinationFieldFirstResponder {
    if ([self.activeAccountTransferViewController.callDestinationField acceptsFirstResponder]) {
        [self.window makeFirstResponder:self.activeAccountTransferViewController.callDestinationField];
    }
}


#pragma mark -
#pragma mark CallController methods

- (CallTransferController *)callTransferController {
    return nil;
}

- (IncomingCallViewController *)incomingCallViewController {
    return nil;
}

// Substitutes ActiveCallTransferViewController.
- (ActiveCallViewController *)activeCallViewController {
    if (_activeCallViewController == nil) {
        _activeCallViewController
            = [[ActiveCallTransferViewController alloc] initWithNibName:@"ActiveCallTransferView" callController:self];
        [_activeCallViewController setRepresentedObject:[self call]];
    }
    return _activeCallViewController;
}

- (ActiveCallTransferViewController *)activeCallTransferViewController {
    return (ActiveCallTransferViewController *)self.activeCallViewController;
}

// Substitutes EndedCallTransferViewController.
- (EndedCallViewController *)endedCallViewController {
    if (_endedCallViewController == nil) {
        _endedCallViewController
            = [[EndedCallTransferViewController alloc] initWithNibName:@"EndedCallTransferView" callController:self];
        [_endedCallViewController setRepresentedObject:[self call]];
    }
    return _endedCallViewController;
}

- (void)acceptCall {
    // Do nothing.
}

- (void)prepareForCall {
    [super prepareForCall];
    [self.activeCallTransferViewController disallowTransfer];
}


#pragma mark -
#pragma mark AKSIPCall notifications

- (void)SIPCallEarly:(NSNotification *)notification {
    [super SIPCallEarly:notification];
    [self.activeCallTransferViewController disallowTransfer];
}

- (void)SIPCallDidConfirm:(NSNotification *)notification {
    [super SIPCallDidConfirm:notification];
    [self.activeCallTransferViewController allowTransfer];
}

- (void)SIPCallDidDisconnect:(NSNotification *)notification {
    [super SIPCallDidDisconnect:notification];
    if ([self sourceCallTransferred]) {
        [self closeSheet:self];
    }
}

- (void)SIPCallMediaDidBecomeActive:(NSNotification *)notification {
    [super SIPCallMediaDidBecomeActive:notification];
    [self.activeCallTransferViewController allowTransfer];
}

- (void)SIPCallDidLocalHold:(NSNotification *)notification {
    [super SIPCallDidLocalHold:notification];
    [self.activeCallTransferViewController callDidHold];
}

- (void)SIPCallDidRemoteHold:(NSNotification *)notification {
    [super SIPCallDidRemoteHold:notification];
    [self.activeCallTransferViewController disallowTransfer];
}


#pragma mark -
#pragma mark Source Call Controller's call notification

- (void)sourceCallControllerSIPCallTransferStatusDidChange:(NSNotification *)notification {
    AKSIPCall *sourceCall = [notification object];
    NSDictionary *userInfo = [notification userInfo];
    BOOL isFinal = [userInfo[@"AKFinalTransferNotification"] boolValue];
    
    if (isFinal && [sourceCall transferStatus] == PJSIP_SC_OK) {
        [self setSourceCallTransferred:YES];
        if (![self isCallActive]) {
            [self closeSheet:self];
        }
    }
}

@end
