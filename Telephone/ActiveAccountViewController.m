//
//  ActiveAccountViewController.m
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

#import "ActiveAccountViewController.h"
#import <objc/runtime.h>

@import UseCases;

#import "AKSIPURI.h"
#import "AKSIPURIFormatter.h"
#import "AKTelephoneNumberFormatter.h"

#import "AccountController.h"

#import "Telephone-Swift.h"
#import "AKLiquidGlass.h"


NSString * const kURI = @"URI";
NSString * const kPhoneLabel = @"PhoneLabel";
static void *CompactDialerValueObservation = &CompactDialerValueObservation;
static const void *SelectedTokenDestination = &SelectedTokenDestination;

static NSUInteger DestinationIndexForToken(id token) {
    if (![token isKindOfClass:NSArray.class] || [token count] == 0) { return NSNotFound; }
    NSNumber *stored = objc_getAssociatedObject(token, SelectedTokenDestination);
    NSUInteger index = stored ? stored.unsignedIntegerValue : 0;
    return index < [token count] ? index : NSNotFound;
}

static NSDictionary *DestinationForToken(id token) {
    NSUInteger index = DestinationIndexForToken(token);
    if (index == NSNotFound || ![token[index] isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *destination = token[index];
    return [destination[kURI] isKindOfClass:AKSIPURI.class] ? destination : nil;
}

// On macOS 26, NSTokenField can invalidate its own intrinsic content size while
// AppKit is already calculating that size. This creates an endless constraints
// update cycle and AppKit terminates the application. The call destination field
// has a fixed height in its XIB, so it does not need an intrinsic size.
@interface AKFixedSizeTokenField : NSTokenField
@end

@implementation AKFixedSizeTokenField

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

@end

// Icon controls use their full 44-point frame as their layout and hit region.
// Older linked SDKs otherwise add native rounded-button alignment insets.
@interface AKCompactDialerButton : NSButton
@end

@implementation AKCompactDialerButton
- (NSEdgeInsets)alignmentRectInsets {
    return NSEdgeInsetsMake(0, 0, 0, 0);
}
@end

@interface ActiveAccountViewController ()
@property(nonatomic) NSButton *dialButton;
@property(nonatomic) NSButton *historyButton;
@property(nonatomic) NSTextField *offlineLabel;
@property(nonatomic, readwrite, strong) NSButton *pendingCallsButton;
@property(nonatomic) NSLayoutConstraint *pendingCallsWidth;
@property(nonatomic) BOOL observesDestinationValues;
@property(nonatomic) NSView *compactLastKeyView;
@end

@implementation ActiveAccountViewController

- (void)dealloc {
    if (self.observesDestinationValues) {
        [self.callDestinationField removeObserver:self forKeyPath:@"stringValue" context:CompactDialerValueObservation];
        [self.callDestinationField removeObserver:self forKeyPath:@"objectValue" context:CompactDialerValueObservation];
    }
}

- (id)firstCallDestinationToken {
    id value = self.callDestinationField.objectValue;
    return [value isKindOfClass:NSArray.class] && [value count] > 0 ? value[0] : nil;
}

- (NSUInteger)callDestinationURIIndex {
    NSUInteger index = DestinationIndexForToken([self firstCallDestinationToken]);
    return index == NSNotFound ? 0 : index;
}

- (void)setCallDestinationURIIndex:(NSUInteger)index {
    id token = [self firstCallDestinationToken];
    if ([token isKindOfClass:NSArray.class] && index < [token count]) {
        objc_setAssociatedObject(token, SelectedTokenDestination, @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (AKSIPURI *)callDestinationURI {
    AKSIPURI *uri = [DestinationForToken([self firstCallDestinationToken])[kURI] copy];
    return uri.user.length > 0 ? uri : nil;
}

- (BOOL)allowsCallDestinationInput {
    return !self.callDestinationField.isHidden;
}

- (NSView *)keyView {
    return self.callDestinationField;
}

- (instancetype)initWithAccountController:(AccountController *)accountController {
    NSParameterAssert(accountController);
    if ((self = [super initWithNibName:@"ActiveAccountView" bundle:nil])) {
        _accountController = accountController;
        self.contactCompletions = accountController.contactCompletions;
    }
    return self;
}

- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle {
    return [super initWithNibName:name bundle:bundle];
}

- (void)awakeFromNib {
    // Exclude comma from the callDestination tokenizing character set.
    [[self callDestinationField] setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@""]];
    
    [[self callDestinationField] setCompletionDelay:0.4];
}

- (void)installCompactDialerWithAvailabilityView:(NSView *)availability
                                         target:(id)target
                                  historyAction:(SEL)historyAction
                                     moreAction:(SEL)moreAction {
    NSTokenField *field = self.callDestinationField;
    NSView *historyKeyView = field.nextKeyView;
    [self.view removeConstraints:self.view.constraints];
    [field removeFromSuperview];
    field.accessibilityLabel = NSLocalizedString(@"Call destination", @"Dialer destination accessibility label.");
    field.placeholderString = NSLocalizedString(@"Number or contact", @"Compact dialer destination placeholder.");

    AKGlassControlContainer *bar = [[AKGlassControlContainer alloc] initWithFrame:NSZeroRect sidebar:NO];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:4],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-4],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6],
        [bar.heightAnchor constraintEqualToConstant:44]
    ]];

    self.dialButton = [self compactButtonWithSymbol:@"phone.fill"
                                            title:NSLocalizedString(@"Call", @"Call button.")
                                           target:self action:@selector(dialFromButton:)];
    self.dialButton.contentTintColor = NSColor.controlAccentColor;
    self.historyButton = [self compactButtonWithSymbol:@"clock.arrow.circlepath"
                                                title:NSLocalizedString(@"Show full call history", @"Expand compact dialer history.")
                                               target:target action:historyAction];
    [self.historyButton setButtonType:NSButtonTypePushOnPushOff];
    NSButton *more = [self compactButtonWithSymbol:@"ellipsis"
                                             title:NSLocalizedString(@"More actions", @"Compact dialer actions menu.")
                                            target:target action:moreAction];
    // Keep the 3.5 destination field centred with the icon controls. Route
    // details remain available through Call's tooltip and accessibility help.
    NSStackView *row = [NSStackView stackViewWithViews:@[availability, field, self.dialButton, self.historyButton, more]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 4;
    row.detachesHiddenViews = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.contentView addSubview:row];

    // Waiting calls are temporary, actionable feedback. Use the existing space
    // below the centred field without moving it or changing the 56-point dial
    // section. The link belongs to that section, so its full frame is hittable
    // even where it extends below the rounded bar.
    self.pendingCallsButton = [NSButton buttonWithTitle:@"" target:nil action:NULL];
    self.pendingCallsButton.identifier = @"CompactPendingCallsButton";
    self.pendingCallsButton.bordered = NO;
    self.pendingCallsButton.font = [NSFont systemFontOfSize:11];
    self.pendingCallsButton.controlSize = NSControlSizeSmall;
    self.pendingCallsButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.pendingCallsButton.hidden = YES;
    [self.view addSubview:self.pendingCallsButton];
    self.pendingCallsWidth = [self.pendingCallsButton.widthAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.pendingCallsButton.trailingAnchor constraintEqualToAnchor:field.trailingAnchor constant:-4],
        [self.pendingCallsButton.topAnchor constraintEqualToAnchor:field.bottomAnchor constant:1],
        [self.pendingCallsButton.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor],
        [self.pendingCallsButton.heightAnchor constraintEqualToConstant:13],
        self.pendingCallsWidth
    ]];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:bar.contentView.leadingAnchor constant:4],
        [row.trailingAnchor constraintEqualToAnchor:bar.contentView.trailingAnchor constant:-4],
        [row.topAnchor constraintEqualToAnchor:bar.contentView.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:bar.contentView.bottomAnchor],
        [availability.widthAnchor constraintEqualToConstant:44],
        [availability.heightAnchor constraintEqualToConstant:44],
        [field.widthAnchor constraintGreaterThanOrEqualToConstant:160]
    ]];
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.offlineLabel = [NSTextField labelWithString:NSLocalizedString(@"Offline", @"Account registration Offline menu item.")];
    self.offlineLabel.textColor = NSColor.secondaryLabelColor;
    self.offlineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.offlineLabel.accessibilityElement = NO;
    [bar.contentView addSubview:self.offlineLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.offlineLabel.leadingAnchor constraintEqualToAnchor:field.leadingAnchor constant:4],
        [self.offlineLabel.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
        [self.offlineLabel.trailingAnchor constraintLessThanOrEqualToAnchor:field.trailingAnchor]
    ]];
    self.offlineLabel.hidden = !field.isHidden;
    self.dialButton.enabled = !field.isHidden && field.stringValue.length > 0;
    if (!self.observesDestinationValues) {
        [field addObserver:self forKeyPath:@"stringValue" options:0 context:CompactDialerValueObservation];
        [field addObserver:self forKeyPath:@"objectValue" options:0 context:CompactDialerValueObservation];
        self.observesDestinationValues = YES;
    }
    field.nextKeyView = self.dialButton;
    self.dialButton.nextKeyView = self.historyButton;
    self.historyButton.nextKeyView = more;
    for (NSView *control in availability.subviews) {
        if ([control isKindOfClass:[NSPopUpButton class]]) {
            more.nextKeyView = control;
            control.nextKeyView = historyKeyView;
            self.compactLastKeyView = control;
        }
    }
    if ([availability isKindOfClass:NSPopUpButton.class]) {
        more.nextKeyView = availability;
        availability.nextKeyView = historyKeyView;
        self.compactLastKeyView = availability;
    }
    if (self.compactLastKeyView == nil) self.compactLastKeyView = more;
}

- (NSButton *)compactButtonWithSymbol:(NSString *)symbol title:(NSString *)title target:(id)target action:(SEL)action {
    NSButton *button = [AKCompactDialerButton buttonWithTitle:@"" target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = title;
    button.accessibilityLabel = title;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:44],
        [button.heightAnchor constraintEqualToConstant:44]
    ]];
    return button;
}

- (void)updateHistoryExpanded:(BOOL)expanded {
    self.historyButton.state = expanded ? NSControlStateValueOn : NSControlStateValueOff;
    NSString *title = expanded
        ? NSLocalizedString(@"Hide full call history", @"Collapse compact dialer history.")
        : NSLocalizedString(@"Show full call history", @"Expand compact dialer history.");
    self.historyButton.toolTip = title;
    self.historyButton.accessibilityLabel = title;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    self.dialButton.enabled = self.allowsCallDestinationInput && self.callDestinationField.stringValue.length > 0;
    [self refreshCallRoutePreview];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == CompactDialerValueObservation) {
        self.dialButton.enabled = self.allowsCallDestinationInput && self.callDestinationField.stringValue.length > 0;
        [self refreshCallRoutePreview];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)refreshCallRoutePreview {
    if (self.callRoutePreviewHandler == nil) return;
    NSString *preview = self.callRoutePreviewHandler(self.callDestinationURI, self.callDestinationField.stringValue);
    self.dialButton.toolTip = preview.length ? preview : @"Call";
    self.dialButton.accessibilityHelp = self.dialButton.toolTip;
    self.dialButton.cell.accessibilityHelp = self.dialButton.toolTip;
}

- (void)setPendingCallCount:(NSUInteger)count target:(id)target action:(SEL)action {
    NSButton *button = self.pendingCallsButton;
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Waiting %lu", @"Compact waiting call count."), (unsigned long)count];
    BOOL changed = ![button.title isEqualToString:title];
    button.title = title;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName:button.font, NSForegroundColorAttributeName:NSColor.controlAccentColor,
        NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle)}];
    button.target = target; button.action = action;
    button.hidden = count == 0; button.enabled = count > 0;
    button.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Calls waiting for registration: %lu", @"Waiting call count purpose."), (unsigned long)count];
    button.cell.accessibilityLabel = button.accessibilityLabel;
    button.toolTip = NSLocalizedString(@"Show destinations and cancel individual waiting calls", @"Waiting calls button help.");
    button.accessibilityHelp = button.toolTip;
    self.pendingCallsWidth.constant = count ? MIN(80, MAX(54, ceil(button.attributedTitle.size.width) + 4)) : 0;
    self.callDestinationField.nextKeyView = count ? button : self.dialButton;
    button.nextKeyView = self.dialButton;
    if (changed && count) NSAccessibilityPostNotification(button, NSAccessibilityValueChangedNotification);
}

- (IBAction)dialFromButton:(NSButton *)sender {
    // Commit the field editor so the existing token delegate resolves Contacts
    // and SIP destinations before invoking precisely the same action as Return.
    if (self.allowsCallDestinationInput && [self.view.window makeFirstResponder:sender]) {
        [self makeCall:sender];
    }
}

- (IBAction)makeCall:(id)sender {
    if (![self canMakeCall]) {
        return;
    }
    
    NSDictionary *callDestinationDict = DestinationForToken([self firstCallDestinationToken]);
    NSString *phoneLabel = callDestinationDict[kPhoneLabel];
    
    AKSIPURI *uri = [self callDestinationURI];
    if (uri != nil) {
        if (self.callDestinationHandler) self.callDestinationHandler(uri, phoneLabel ?: @"");
        else [[self accountController] makeCallToURI:uri phoneLabel:phoneLabel];
    }
}

- (BOOL)canMakeCall {
    return DestinationForToken([self firstCallDestinationToken]) != nil;
}

- (IBAction)changeCallDestinationURIIndex:(id)sender {
    id token = [sender isKindOfClass:NSMenuItem.class] ? [sender representedObject] : [self firstCallDestinationToken];
    NSInteger index = [sender tag];
    if ([token isKindOfClass:NSArray.class] && index >= 0 && (NSUInteger)index < [token count]) {
        objc_setAssociatedObject(token, SelectedTokenDestination, @(index), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Refresh the existing represented objects without parsing or changing another token.
        self.callDestinationField.objectValue = self.callDestinationField.objectValue;
    }
}

- (void)allowCallDestinationInput {
    self.offlineLabel.hidden = YES;
    self.dialButton.enabled = self.callDestinationField.stringValue.length > 0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        self.callDestinationField.animator.hidden = NO;
    } completionHandler:^{
        if (self.callDestinationField.acceptsFirstResponder) {
            [self.view.window makeFirstResponder:self.callDestinationField];
        }
    }];
}

- (void)disallowCallDestinationInput {
    self.callDestinationField.hidden = YES;
    self.offlineLabel.hidden = NO;
    self.dialButton.enabled = NO;
}

- (void)updateNextKeyView:(NSView *)view {
    (self.compactLastKeyView ?: self.keyView).nextKeyView = view;
}


#pragma mark -
#pragma mark NSTokenField delegate

// AppKit's synchronous delegate only filters an immutable actor-built value.
// No directory fetch or permission request is allowed while typing.
- (NSArray *)tokenField:(NSTokenField *)tokenField
        completionsForSubstring:(NSString *)substring
        indexOfToken:(NSInteger)tokenIndex
        indexOfSelectedItem:(NSInteger *)selectedIndex {
    NSArray *completions = [self.contactCompletions completionsForSubstring:substring] ?: @[];
    tokenField.tokenStyle = completions.count > 0 ? NSTokenStyleRounded : NSTokenStyleNone;
    return completions;
}

// Converts input text to the array of dictionaries containing AKSIPURIs and phone labels (mobile, home, etc).
// Dictionary keys are kURI and kPhoneLabel. If there is no @ sign, the input is treated as a user part of the URI and
// host part will be nil.
- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    AKSIPURIFormatter *SIPURIFormatter = [[AKSIPURIFormatter alloc] init];
    [SIPURIFormatter setFormatsTelephoneNumbers:[defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]];
    [SIPURIFormatter setTelephoneNumberFormatterSplitsLastFourDigits:
     [defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
    
    NSCharacterSet *whitespaceCharset = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmedString = [editingString stringByTrimmingCharactersInSet:whitespaceCharset];
    
    AKSIPURI *theURI = [SIPURIFormatter SIPURIFromString:trimmedString];
    if (theURI == nil || [[theURI user] length] == 0) {
        return nil;
    }
    
    AKSIPURI *literalURI = [theURI copy];
    JPSDiallerContactMatch *match = [self.contactCompletions firstContactMatchingUser:theURI.user
                                                                       SIPAddress:theURI.SIPAddress
                                                                      displayName:theURI.displayName ?: @""];
    NSMutableArray *callDestinations = [[NSMutableArray alloc] init];
    NSUInteger destinationIndex = 0;
    if (match != nil) {
        if (match.displayName.length > 0) theURI.displayName = match.displayName;
        AKTelephoneNumberFormatter *telephoneNumberFormatter = [[AKTelephoneNumberFormatter alloc] init];
        for (JPSDiallerContactDestination *destination in match.destinations) {
            AKSIPURI *uri = [SIPURIFormatter SIPURIFromString:destination.address];
            // A malformed directory value cannot turn selection into an exception.
            if (uri == nil || uri.user.length == 0) continue;
            uri.displayName = theURI.displayName;
            [callDestinations addObject:@{kURI: uri, kPhoneLabel: destination.label}];
            if (destination.isSIPEmail) {
                if ([destination.address caseInsensitiveCompare:theURI.SIPAddress] == NSOrderedSame)
                    destinationIndex = callDestinations.count - 1;
            } else if ([destination.address rangeOfString:@"@"].location == NSNotFound && theURI.host.length == 0) {
                if ([[telephoneNumberFormatter telephoneNumberFromString:destination.address]
                     isEqualToString:[telephoneNumberFormatter telephoneNumberFromString:theURI.user]])
                    destinationIndex = callDestinations.count - 1;
            } else if ([destination.address isEqualToString:theURI.SIPAddress]) {
                destinationIndex = callDestinations.count - 1;
            }
        }
        // Revocation/store changes may arrive while formatters are running.
        // Keep the user's literal destination and discard stale enrichment.
        if (![self.contactCompletions isCurrentMatch:match]) {
            [callDestinations removeAllObjects];
            [callDestinations addObject:@{kURI: literalURI, kPhoneLabel: @""}];
            destinationIndex = 0;
        }
    } else {
        [callDestinations addObject:@{kURI: theURI, kPhoneLabel: @""}];
    }

    NSArray *token = [callDestinations copy];
    objc_setAssociatedObject(token, SelectedTokenDestination, @(destinationIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return token;
}

- (NSString *)tokenField:(NSTokenField *)tokenField displayStringForRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    AKSIPURI *uri = DestinationForToken(representedObject)[kURI];
    if (uri == nil) { return nil; }
    
    NSString *returnString = nil;
    
    if ([[uri displayName] length] > 0) {
        returnString = [uri displayName];
        
    } else if ([[uri host] length] > 0) {
        NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
        
        returnString = [uri SIPAddress];
        
    } else {
        NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([[uri user] ak_isTelephoneNumber] && [defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
            AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
            [formatter setSplitsLastFourDigits:[defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
            returnString = [formatter stringForObjectValue:[uri user]];
            
        } else {
            returnString = [uri user];
        }
    }
    
    return returnString;
}

- (NSString *)tokenField:(NSTokenField *)tokenField editingStringForRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    AKSIPURI *uri = DestinationForToken(representedObject)[kURI];
    if (uri == nil) { return nil; }
    
    NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
    
    NSString *returnString = nil;
    
    if ([[uri displayName] length] > 0) {
        if ([[uri host] length] > 0) {
            returnString = [NSString stringWithFormat:@"%@ <%@>", [uri displayName], [uri SIPAddress]];
        } else {
            returnString =  [NSString stringWithFormat:@"%@ <%@>", [uri displayName], [uri user]];
        }
    } else if ([[uri host] length] > 0) {
        returnString =  [uri SIPAddress];
        
    } else {
        returnString =  [uri user];
    }
    
    return returnString;
}

- (BOOL)tokenField:(NSTokenField *)tokenField hasMenuForRepresentedObject:(id)representedObject {
    AKSIPURI *uri = DestinationForToken(representedObject)[kURI];
    
    if ([representedObject isKindOfClass:[NSArray class]] && [[uri displayName] length] > 0) {
        return YES;
    } else {
        return NO;
    }
}

- (NSMenu *)tokenField:(NSTokenField *)tokenField menuForRepresentedObject:(id)representedObject {
    if (DestinationForToken(representedObject) == nil) { return nil; }
    NSMenu *tokenMenu = [[NSMenu alloc] init];
    
    for (NSUInteger i = 0; i < [representedObject count]; ++i) {
        if (![representedObject[i] isKindOfClass:NSDictionary.class]) { continue; }
        AKSIPURI *uri = representedObject[i][kURI];
        if (![uri isKindOfClass:AKSIPURI.class]) { continue; }
        
        NSString *phoneLabel = representedObject[i][kPhoneLabel];
        
        NSMenuItem *menuItem = [[NSMenuItem alloc] init];
        
        AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
        [formatter setSplitsLastFourDigits:
         [[NSUserDefaults standardUserDefaults] boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
        
        if ([[uri host] length] > 0) {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@", phoneLabel, [uri SIPAddress]]];
            
        } else if ([[uri user] ak_isTelephoneNumber]) {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@",
                                phoneLabel, [formatter stringForObjectValue:[uri user]]]];
        } else {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@", phoneLabel, [uri user]]];
        }
        
        [menuItem setTag:i];
        [menuItem setAction:@selector(changeCallDestinationURIIndex:)];
        menuItem.target = self;
        menuItem.representedObject = representedObject;
        
        [tokenMenu addItem:menuItem];
    }
    
    [[tokenMenu itemWithTag:DestinationIndexForToken(representedObject)] setState:NSControlStateValueOn];
    
    return tokenMenu;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index {
    if (index > 0 && [tokenField tokenStyle] == NSTokenStyleRounded) {
        return @[];
    } else {
        return tokens;
    }
}

@end
