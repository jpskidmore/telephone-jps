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
@property(nonatomic) NSButton *recordingStatusButton;
@property(nonatomic) NSPopover *recordingPopover;
@property(nonatomic) NSTextField *recordingSummaryField;
@property(nonatomic) NSTextField *recordingDetailField;
@property(nonatomic) NSButton *recordingRetryButton;
@property(nonatomic) NSButton *recordingChooseFolderButton;
@property(nonatomic) NSButton *recordingRevealFolderButton;

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
    [self installRecordingStatusButton];
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
    [self.recordingPopover close];
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
    [self refreshRecordingPresentation];
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
    if (notification.object == self.recordingPopover) {
        self.recordingStatusButton.accessibilityValue = @NO;
        return;
    }
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
    // Retained for callers using the old indicator API. The current call card
    // presents its confirmed attempt state through refreshRecordingPresentation.
    self.recordingIndicatorField.hidden = !visible;
    if (self.recordingStatusButton != nil) {
        self.recordingIndicatorField.hidden = YES;
        [self refreshRecordingPresentation];
    }
}

- (void)installRecordingStatusButton {
    if (self.recordingIndicatorField == nil || self.recordingStatusButton != nil) return;
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(showRecordingDetails:)];
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    button.alignment = NSTextAlignmentRight;
    button.identifier = @"RecordingStatus";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor constraintEqualToAnchor:self.recordingIndicatorField.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:self.recordingIndicatorField.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:self.recordingIndicatorField.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:self.recordingIndicatorField.bottomAnchor]
    ]];
    self.recordingIndicatorField.hidden = YES;
    self.recordingStatusButton = button;
    [self refreshRecordingPresentation];
}

- (void)refreshRecordingPresentation {
    if (self.recordingStatusButton == nil) return;
    AKCallRecordingStatus state = self.callController.recordingStatus;
    self.recordingStatusButton.hidden = state == AKCallRecordingStatusDisabled;
    if (state == AKCallRecordingStatusDisabled) [self.recordingPopover close];
    NSString *title = @"";
    NSColor *color = NSColor.secondaryLabelColor;
    switch (state) {
        case AKCallRecordingStatusDisabled: break;
        case AKCallRecordingStatusStarting:
            title = NSLocalizedString(@"Starting", @"Compact recording start indicator."); break;
        case AKCallRecordingStatusFailed:
            title = NSLocalizedString(@"Failed", @"Compact recording failure indicator.");
            color = NSColor.systemOrangeColor; break;
        case AKCallRecordingStatusCapturing:
            title = self.callController.recordingUsesFallback ? @"REC*" : @"REC";
            color = NSColor.systemRedColor; break;
    }
    self.recordingStatusButton.attributedTitle = [[NSAttributedString alloc] initWithString:title
        attributes:@{NSForegroundColorAttributeName:color, NSFontAttributeName:self.recordingStatusButton.font}];
    NSString *explanation = [NSString stringWithFormat:@"%@\n%@", self.callController.recordingSummary, self.callController.recordingDetail];
    self.recordingStatusButton.toolTip = explanation;
    self.recordingStatusButton.accessibilityLabel = self.callController.recordingSummary;
    self.recordingStatusButton.accessibilityHelp = self.callController.recordingDetail;
    self.recordingSummaryField.stringValue = self.callController.recordingSummary;
    self.recordingDetailField.stringValue = self.callController.recordingDetail;
    self.recordingRetryButton.enabled = state == AKCallRecordingStatusFailed && self.callController.isCallActive;
    self.recordingChooseFolderButton.enabled = state != AKCallRecordingStatusStarting;
    self.recordingRevealFolderButton.enabled = self.callController.recordingDestinationFolderURL != nil;
    if (self.recordingPopover.isShown) {
        [self.recordingPopover.contentViewController.view layoutSubtreeIfNeeded];
        NSSize size = self.recordingPopover.contentViewController.view.fittingSize;
        self.recordingPopover.contentSize = NSMakeSize(360, MAX(130, size.height));
    }
}

- (void)prepareRecordingDetails {
    if (self.recordingPopover != nil) return;
    self.recordingSummaryField = [NSTextField wrappingLabelWithString:@""];
    self.recordingSummaryField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    self.recordingSummaryField.selectable = YES;
    self.recordingSummaryField.accessibilityLabel = NSLocalizedString(@"Recording status and folder", @"Recording details accessibility label.");
    self.recordingDetailField = [NSTextField wrappingLabelWithString:@""];
    self.recordingDetailField.font = [NSFont systemFontOfSize:12];
    self.recordingDetailField.selectable = YES;
    self.recordingRetryButton = [NSButton buttonWithTitle:NSLocalizedString(@"Retry", @"Recording retry button.") target:self action:@selector(retryRecording:)];
    self.recordingChooseFolderButton = [NSButton buttonWithTitle:NSLocalizedString(@"Choose Folder…", @"Recording choose folder button.") target:self action:@selector(chooseRecordingFolder:)];
    self.recordingRevealFolderButton = [NSButton buttonWithTitle:NSLocalizedString(@"Reveal Folder", @"Recording reveal folder button.") target:self action:@selector(revealRecordingFolder:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[self.recordingRetryButton, self.recordingChooseFolderButton, self.recordingRevealFolderButton]];
    actions.spacing = 6;
    NSStackView *stack = [NSStackView stackViewWithViews:@[self.recordingSummaryField, self.recordingDetailField, actions]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSViewController *controller = [NSViewController new];
    controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 190)];
    [controller.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:controller.view.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor constant:-12],
        [stack.widthAnchor constraintEqualToConstant:336],
        [self.recordingSummaryField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.recordingDetailField.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
    ]];
    self.recordingPopover = [NSPopover new];
    self.recordingPopover.behavior = NSPopoverBehaviorTransient;
    self.recordingPopover.delegate = self;
    self.recordingPopover.contentViewController = controller;
}

- (IBAction)showRecordingDetails:(NSButton *)sender {
    if (self.recordingPopover.isShown) { [self.recordingPopover close]; return; }
    [self prepareRecordingDetails];
    [self refreshRecordingPresentation];
    [self.recordingPopover.contentViewController.view layoutSubtreeIfNeeded];
    NSSize size = self.recordingPopover.contentViewController.view.fittingSize;
    self.recordingPopover.contentSize = NSMakeSize(360, MAX(130, size.height));
    [self.recordingPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSMinYEdge];
    sender.accessibilityValue = @YES;
}

- (IBAction)retryRecording:(id)sender { [self.callController retryRecording:sender]; }
- (IBAction)chooseRecordingFolder:(id)sender {
    [self.recordingPopover close];
    [self.callController chooseRecordingFolder:sender];
}
- (IBAction)revealRecordingFolder:(id)sender { [self.callController revealRecordingFolder:sender]; }


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
