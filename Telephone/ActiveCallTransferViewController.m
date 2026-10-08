//
//  ActiveCallTransferViewController.m
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

#import "ActiveCallTransferViewController.h"

#import "AKSIPCall.h"

#import "CallTransferController.h"


@interface ActiveCallTransferViewController () <NSMenuItemValidation>

@property(nonatomic, getter=isWaitingForHold) BOOL waitingForHold;
@property(nonatomic) NSTimer *holdAcceptanceTimer;
@property(nonatomic) NSUInteger holdRequestGeneration;
@property(nonatomic) BOOL holdRequestPending;

@property(nonatomic, weak) IBOutlet NSButton *cancelButton;
@property(nonatomic, weak) IBOutlet NSButton *transferButton;

@end

@implementation ActiveCallTransferViewController

- (void)setRepresentedObject:(id)representedObject {
    super.representedObject = representedObject;
    self.waitingForHold = NO;
    self.holdRequestPending = NO;
    self.holdRequestGeneration++;
    [self.holdAcceptanceTimer invalidate];
    self.holdAcceptanceTimer = nil;
}

- (IBAction)transferCall:(id)sender {
    if (self.holdRequestPending || self.isWaitingForHold) return;
    if (self.callController.call.state != kAKSIPCallConfirmedState || self.callController.call.isOnRemoteHold) return;
    if (self.callController.isCallOnHold) {
        [(CallTransferController *)self.callController transferCall];
        return;
    }
    AKSIPCall *call = self.callController.call;
    NSUInteger generation = self.holdRequestGeneration;
    self.holdRequestPending = YES;
    [self disallowTransfer];
    [self.callController requestToggleCallHoldWithCompletion:^(BOOL accepted) {
        if (self.callController.call != call || self.holdRequestGeneration != generation) return;
        self.holdRequestPending = NO;
        self.waitingForHold = accepted;
        if (!accepted) {
            [self allowTransfer];
            [self.callController setIntermediateStatus:NSLocalizedString(@"Could not hold call. Try again.", @"Transfer hold failed.")];
        } else if (self.callController.isCallOnHold) {
            [self callDidHold];
        } else {
            self.holdAcceptanceTimer = [NSTimer scheduledTimerWithTimeInterval:12 target:self
                selector:@selector(holdAcceptanceDidTimeOut:) userInfo:nil repeats:NO];
        }
    }];
}

- (void)callDidHold {
    if (self.isWaitingForHold && self.callController.call.state == kAKSIPCallConfirmedState) {
        [(CallTransferController *)self.callController transferCall];
        self.waitingForHold = NO;
        [self.holdAcceptanceTimer invalidate];
        self.holdAcceptanceTimer = nil;
    }
}

- (void)holdAcceptanceDidTimeOut:(NSTimer *)timer {
    self.holdAcceptanceTimer = nil;
    if (!self.isWaitingForHold) return;
    self.waitingForHold = NO;
    self.holdRequestPending = NO;
    self.holdRequestGeneration++;
    if (self.callController.call.state == kAKSIPCallConfirmedState && !self.callController.call.isOnRemoteHold) {
        [self allowTransfer];
        [self.callController setIntermediateStatus:NSLocalizedString(@"Hold was not confirmed. Try again.", @"Transfer hold timed out.")];
    }
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    self.waitingForHold = NO;
    self.holdRequestPending = NO;
    self.holdRequestGeneration++;
    [self.holdAcceptanceTimer invalidate];
    self.holdAcceptanceTimer = nil;
}

- (void)allowTransfer {
    self.transferButton.enabled = YES;
}

- (void)disallowTransfer {
    self.transferButton.enabled = NO;
}

- (IBAction)showCallTransferSheet:(id)sender {
    // Do nothing.
}

- (void)allowHangUp {
    [super allowHangUp];
    self.cancelButton.enabled = YES;
}

- (void)disallowHangUp {
    [super disallowHangUp];
    self.cancelButton.enabled = NO;
}


#pragma mark -
#pragma mark NSMenuItemValidation protocol

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(showCallTransferSheet:)) {
        return NO;
    }
    
    return [super validateMenuItem:menuItem];
}

@end
