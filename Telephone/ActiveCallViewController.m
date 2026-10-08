//
//  ActiveCallViewController.m
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

#import "ActiveCallViewController.h"
#import "AKLiquidGlass.h"

#import "AKSIPCall.h"

#import "CallController.h"
#import "CallTransferController.h"
#import "EndedCallViewController.h"


@interface ActiveCallViewController () <NSMenuItemValidation, NSPopoverDelegate>

@property(nonatomic, getter=isShowingProgress) BOOL showingProgress;
@property(nonatomic) NSTrackingArea *trackingArea;

@property(nonatomic, weak) IBOutlet NSTextField *displayedNameField;
@property(nonatomic, weak) IBOutlet NSTextField *statusField;
@property(nonatomic, weak) IBOutlet NSTextField *recordingIndicatorField;

@property(nonatomic) IBOutlet NSProgressIndicator *callProgressIndicator;
@property(nonatomic) IBOutlet NSButton *hangUpButton;
@property(nonatomic) NSArray<NSButton *> *visibleCallControls;
@property(nonatomic) NSTextField *numberField;
@property(nonatomic) NSTextField *durationField;
@property(nonatomic) NSPopover *keypadPopover;
@property(nonatomic) NSTextField *keypadDigitsField;
@property(nonatomic) BOOL updatesDurationStatus;

@end

@implementation ActiveCallViewController

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    [self.enteredDTMF setString:@""];
    self.keypadDigitsField.stringValue = @"";
}

- (instancetype)initWithNibName:(NSString *)nibName callController:(CallController *)callController {
    self = [super initWithNibName:nibName bundle:nil];
    
    if (self != nil) {
        _enteredDTMF = [[NSMutableString alloc] init];
        [self setCallController:callController];
    }
    return self;
}

- (instancetype)init {
    NSString *reason = @"Initialize ActiveCallViewController with initWithCallController:";
    @throw [NSException exceptionWithName:@"AKBadInitCall" reason:reason userInfo:nil];
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Transfer subclasses retain their dedicated sheet layout and actions.
    if (![self.nibName isEqualToString:@"ActiveCallView"]) {
        return;
    }
    NSButton *mute = [AKCallActionButton buttonWithTitle:@"" target:self action:@selector(toggleMicrophoneMute:)];
    NSButton *hold = [AKCallActionButton buttonWithTitle:@"" target:self action:@selector(toggleCallHold:)];
    NSButton *transfer = [AKCallActionButton buttonWithTitle:@"" target:self action:@selector(showCallTransferSheet:)];
    NSButton *keypad = [AKCallActionButton buttonWithTitle:@"" target:self action:@selector(showKeypad:)];
    AKStyleCallButton(mute, NSLocalizedString(@"Mute", @"Mute. Call menu item."), @"mic", NO);
    AKStyleCallButton(hold, NSLocalizedString(@"Hold", @"Hold. Call menu item."), @"pause.fill", NO);
    AKStyleCallButton(transfer, NSLocalizedString(@"Transfer", @"Call transfer button."), @"phone.arrow.right", NO);
    AKStyleCallButton(keypad, NSLocalizedString(@"Keypad", @"Call keypad button."), @"circle.grid.3x3.fill", NO);
    AKStyleCallButton(self.hangUpButton, NSLocalizedString(@"End Call", @"End Call. Call menu item."), @"phone.down.fill", YES);
    // The End icon has its own stable slot even while connecting; only its
    // existing enabled lifecycle changes. It no longer shares the spinner slot.
    self.hangUpButton.hidden = NO;
    [mute setButtonType:NSButtonTypePushOnPushOff];
    [hold setButtonType:NSButtonTypePushOnPushOff];
    [keypad setButtonType:NSButtonTypePushOnPushOff];
    mute.imagePosition = hold.imagePosition = keypad.imagePosition = NSImageOnly;
    self.visibleCallControls = @[mute, hold, transfer, keypad];
    self.numberField = [NSTextField labelWithString:@""];
    [self.numberField bind:NSValueBinding toObject:self withKeyPath:@"callController.title" options:nil];
    self.durationField = [NSTextField labelWithString:@""];
    [self.durationField bind:NSValueBinding toObject:self withKeyPath:@"callController.presentationDuration" options:nil];
    AKInstallCallPresentation(self.view, self.displayedNameField, self.numberField, self.statusField,
                              @[mute, hold, transfer, keypad, self.hangUpButton],
                              self.recordingIndicatorField, self.callProgressIndicator, self.durationField);
    [self refreshVisibleCallControls];
    [self refreshPresentation];
}

- (void)refreshVisibleCallControls {
    for (NSButton *button in self.visibleCallControls) {
        NSMenuItem *validationItem = [[NSMenuItem alloc] initWithTitle:button.title
                                                             action:button.action
                                                      keyEquivalent:@""];
        button.enabled = [self validateMenuItem:validationItem];
        button.title = validationItem.title;
        button.imagePosition = NSImageOnly;
        button.toolTip = validationItem.title;
        button.accessibilityLabel = validationItem.title;
        if (button.action == @selector(toggleMicrophoneMute:)) {
            BOOL selected = self.callController.call.isMicrophoneMuted;
            button.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
            button.image = [NSImage imageWithSystemSymbolName:selected ? @"mic.slash" : @"mic" accessibilityDescription:nil];
            button.accessibilityValue = @(selected);
        } else if (button.action == @selector(toggleCallHold:)) {
            BOOL selected = self.callController.call.isOnLocalHold;
            button.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
            button.image = [NSImage imageWithSystemSymbolName:selected ? @"play.fill" : @"pause.fill" accessibilityDescription:nil];
            button.accessibilityValue = @(selected);
        }
    }
}

- (void)removeObservations {
    [self.keypadPopover close];
    [self.numberField unbind:NSValueBinding];
    [self.durationField unbind:NSValueBinding];
    [[self displayedNameField] unbind:NSValueBinding];
    [[self statusField] unbind:NSValueBinding];
 }

- (void)refreshPresentation {
    if (![self.nibName isEqualToString:@"ActiveCallView"]) return;
    self.statusField.stringValue = self.callController.presentationStatus;
    self.numberField.toolTip = self.callController.title;
    self.displayedNameField.toolTip = self.callController.displayedName;
    AKUpdateCallPresentation(self.view, self.statusField);
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    [self closeKeypad];
}

- (void)closeKeypad {
    [self.keypadPopover close];
}

- (IBAction)showKeypad:(NSButton *)sender {
    if (self.callController.call.state != kAKSIPCallConfirmedState) return;
    if (self.keypadPopover.isShown) {
        [self.keypadPopover close];
        return;
    }
    [self prepareKeypad];
    self.keypadDigitsField.stringValue = self.enteredDTMF;
    [self.keypadPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSMinYEdge];
    [self.keypadPopover.contentViewController.view.window makeFirstResponder:self.keypadPopover.contentViewController.view];
    sender.accessibilityValue = @YES;
    sender.state = NSControlStateValueOn;
}

- (void)prepareKeypad {
    if (self.keypadPopover == nil) {
        NSViewController *controller = [NSViewController new];
        AKActiveCallView *view = [[AKActiveCallView alloc] initWithFrame:NSMakeRect(0, 0, 180, 264)];
        view.delegate = self;
        controller.view = view;
        self.keypadDigitsField = [NSTextField labelWithString:self.enteredDTMF];
        self.keypadDigitsField.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
        self.keypadDigitsField.lineBreakMode = NSLineBreakByTruncatingHead;
        self.keypadDigitsField.selectable = YES;
        self.keypadDigitsField.accessibilityLabel = NSLocalizedString(@"DTMF digits", @"Entered call keypad digits accessibility label.");
        self.keypadDigitsField.frame = NSMakeRect(12, 236, 156, 16);
        [view addSubview:self.keypadDigitsField];
        NSArray<NSString *> *digits = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"*", @"0", @"#"];
        for (NSUInteger i = 0; i < digits.count; i++) {
            NSButton *digit = [NSButton buttonWithTitle:digits[i] target:self action:@selector(sendKeypadDigit:)];
            digit.frame = NSMakeRect(12 + (i % 3) * 56, 180 - (i / 3) * 56, 44, 44);
            digit.bezelStyle = NSBezelStyleRounded;
            digit.font = [NSFont systemFontOfSize:17];
            digit.accessibilityLabel = digits[i];
            [view addSubview:digit];
        }
        self.keypadPopover = [NSPopover new];
        self.keypadPopover.behavior = NSPopoverBehaviorTransient;
        self.keypadPopover.delegate = self;
        self.keypadPopover.contentViewController = controller;
    }
}

- (void)popoverDidClose:(NSNotification *)notification {
    for (NSButton *button in self.visibleCallControls) {
        if (button.action == @selector(showKeypad:)) {
            button.accessibilityValue = @NO;
            button.state = NSControlStateValueOff;
        }
    }
}

- (IBAction)sendKeypadDigit:(NSButton *)sender {
    if (self.callController.call.state == kAKSIPCallConfirmedState) {
        [self activeCallView:(AKActiveCallView *)self.view didReceiveText:sender.title];
    }
}

- (IBAction)hangUpCall:(id)sender {
    [[self callController] hangUpCall];
}

- (IBAction)toggleCallHold:(id)sender {
    [[self callController] toggleCallHold];
    [self refreshVisibleCallControls];
}

- (IBAction)toggleMicrophoneMute:(id)sender {
    [[self callController] toggleMicrophoneMute];
    [self refreshVisibleCallControls];
}

- (IBAction)showCallTransferSheet:(id)sender {
    CallTransferController *callTransferController = [[self callController] callTransferController];
    [callTransferController beginTransferSetup];
    [[[self callController] window] beginSheet:[callTransferController window] completionHandler:nil];
}

- (void)startCallTimer {
    self.updatesDurationStatus = YES;
    [self refreshVisibleCallControls];
    if ([self callTimer] != nil && [[self callTimer] isValid]) {
        return;
    }
    
    [self setCallTimer:
     [NSTimer scheduledTimerWithTimeInterval:0.2
                                      target:self
                                    selector:@selector(callTimerTick:)
                                    userInfo:nil
                                     repeats:YES]];
}

- (void)stopCallTimer {
    self.updatesDurationStatus = NO;
    // Connected duration continues during hold/mute and intermediate feedback.
    if (self.callController.isCallActive && self.callController.call.state == kAKSIPCallConfirmedState) {
        [self refreshVisibleCallControls];
        return;
    }
    if ([self callTimer] != nil) {
        [[self callTimer] invalidate];
        [self setCallTimer:nil];
    }
    // Hold and mute suspend the status timer. Refresh here so controls still
    // reflect native local/remote hold notifications while that timer is idle.
    [self refreshVisibleCallControls];
}

- (void)callTimerTick:(NSTimer *)theTimer {
    [self refreshVisibleCallControls];
    [self.callController willChangeValueForKey:@"presentationDuration"];
    [self.callController didChangeValueForKey:@"presentationDuration"];
    if (!self.updatesDurationStatus) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSInteger seconds = (NSInteger)(now - ([[self callController] callStartTime]));
    
    if (seconds < 3600) {
        [[self callController] setStatus:[NSString stringWithFormat:@"%02ld:%02ld",
                                          (seconds / 60) % 60, seconds % 60]];
    } else {
        [[self callController]
         setStatus:[NSString stringWithFormat:@"%02ld:%02ld:%02ld",
                    (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60]];
    }
}

- (void)showProgress {
    if (!self.isShowingProgress) {
        [self.callProgressIndicator startAnimation:self];
        [self addTrackingArea];
        self.showingProgress = YES;
    }
    [self showCallProgressIndicator];
    [self refreshVisibleCallControls];
}

- (void)showHangUp {
    if (self.isShowingProgress) {
        [self.callProgressIndicator stopAnimation:nil];
        [self removeTrackingArea];
        self.showingProgress = NO;
    }
    [self showHangUpButton];
    [self refreshVisibleCallControls];
}

- (void)showCallProgressIndicator {
    // The cancel action remains discoverable while a call connects. Its
    // enabled state continues to be controlled by the original call lifecycle.
    self.hangUpButton.hidden = self.visibleCallControls == nil;
    self.callProgressIndicator.hidden = NO;
}

- (void)showHangUpButton {
    self.callProgressIndicator.hidden = YES;
    self.hangUpButton.hidden = NO;
}

- (void)addTrackingArea {
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.callProgressIndicator.frame
                                                     options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                                                       owner:self
                                                    userInfo:nil];
    [self.view addTrackingArea:self.trackingArea];
}

- (void)removeTrackingArea {
    [self.view removeTrackingArea:self.trackingArea];
    self.trackingArea = nil;
}

- (void)allowHangUp {
    self.hangUpButton.enabled = YES;
}

- (void)disallowHangUp {
    self.hangUpButton.enabled = NO;
}

- (void)setRecordingIndicatorVisible:(BOOL)visible {
    self.recordingIndicatorField.hidden = !visible;
}


#pragma mark -
#pragma mark NSResponder overrides

- (void)mouseEntered:(NSEvent *)theEvent {
    [self showHangUpButton];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [self showCallProgressIndicator];
}


#pragma mark -
#pragma mark AKActiveCallViewDelegate protocol

- (void)activeCallView:(AKActiveCallView *)sender didReceiveText:(NSString *)aString {
    NSCharacterSet *DTMFCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789*#abcdrABCDR"];
    
    BOOL isDTMFValid = YES;
    for (NSUInteger i = 0; i < [aString length]; ++i) {
        unichar digit = [aString characterAtIndex:i];
        if (![DTMFCharacterSet characterIsMember:digit]) {
            isDTMFValid = NO;
            break;
        }
    }
    
    if (isDTMFValid && aString.length > 0 && self.callController.call.state == kAKSIPCallConfirmedState) {
        [self.enteredDTMF appendString:aString];
        [self.callController.call sendDTMFDigits:aString];
        // Identity always remains in Caller; keypad has a separate named echo.
        [self prepareKeypad];
        self.keypadDigitsField.stringValue = self.enteredDTMF;
    }
}


#pragma mark -
#pragma mark NSMenuItemValidation protocol

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(toggleMicrophoneMute:)) {
        if ([[[self callController] call] isMicrophoneMuted]) {
            [menuItem setTitle:NSLocalizedString(@"Unmute", @"Unmute. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Mute", @"Mute. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState) {
            return YES;
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(toggleCallHold:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            [[[self callController] call] isOnLocalHold]) {
            [menuItem setTitle:NSLocalizedString(@"Resume", @"Resume. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Hold", @"Hold. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(showCallTransferSheet:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(hangUpCall:)) {
        [menuItem setTitle:NSLocalizedString(@"End Call", @"End Call. Call menu item.")];

        return self.hangUpButton.isEnabled;
    } else if ([menuItem action] == @selector(showKeypad:)) {
        return self.callController.call.state == kAKSIPCallConfirmedState;
    }
    
    return YES;
}

@end
