//
//  AccountWindowController.m
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

#import "AccountWindowController.h"

#import "AccountViewController.h"

#import "Telephone-Swift.h"
#import "AKLiquidGlass.h"

static NSMenuItem *MenuItemWithAction(NSMenu *menu, SEL action);

@interface AccountWindowController ()

@property(nonatomic, readonly) NSString *accountDescription;
@property(nonatomic, readonly) NSString *SIPAddress;
@property(nonatomic, readonly) AccountViewController *accountViewController;
@property(nonatomic, readonly, weak) id<AccountWindowControllerDelegate> delegate;

@property(nonatomic, weak) IBOutlet NSImageView *accountStateImageView;
@property(nonatomic, weak) IBOutlet NSPopUpButton *accountStatePopUp;
@property(nonatomic, weak) IBOutlet NSMenuItem *availableStateItem;
@property(nonatomic, weak) IBOutlet NSMenuItem *unavailableStateItem;
@property(nonatomic, weak) IBOutlet NSMenuItem *offlineStateItem;
@property(nonatomic) NSSize expandedContentSize;
@property(nonatomic) BOOL adjustingFrame;

@end

@implementation AccountWindowController

- (BOOL)allowsCallDestinationInput {
    return self.accountViewController.allowsCallDestinationInput;
}

- (instancetype)initWithAccountDescription:(NSString *)accountDescription
                                SIPAddress:(NSString *)SIPAddress
                     accountViewController:(AccountViewController *)accountViewController
                                  delegate:(id<AccountWindowControllerDelegate>)delegate {

    NSParameterAssert(accountDescription);
    NSParameterAssert(SIPAddress);
    NSParameterAssert(accountViewController);
    NSParameterAssert(delegate);
    if ((self = [super initWithWindowNibName:@"Account"])) {
        _accountDescription = [accountDescription copy];
        _SIPAddress = [SIPAddress copy];
        _accountViewController = accountViewController;
        _delegate = delegate;
    }
    return self;
}

- (void)awakeFromNib {
    self.shouldCascadeWindows = NO;
}

- (void)windowDidLoad {
    // Retain the nib's menu controls before removing its former toolbar.
    NSPopUpButton *availability = self.accountStatePopUp;
    NSImageView *stateImage = self.accountStateImageView;
    self.window.toolbar = nil;
    self.window.title = self.accountDescription;
    self.window.excludedFromWindowsMenu = YES;

    [self.window.contentView addSubview:self.accountViewController.view];
    self.accountViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *views = @{@"view": self.accountViewController.view};
    [self.window.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:views]];
    [self.window.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:views]];

    NSView *availabilityView = [self compactAvailabilityViewWithPopUp:availability image:stateImage];
    [self.accountViewController installCompactDialerWithAvailabilityView:availabilityView
                                                                  target:self
                                                           historyAction:@selector(toggleCallHistory:)
                                                              moreAction:@selector(showDialerActions:)];
    [self.accountViewController setHistoryExpanded:NO];

    // A new geometry key avoids restoring the old permanently expanded body.
    // Retain its position and use its dimensions when history is next expanded.
    NSString *frameName = [self.SIPAddress stringByAppendingString:@".CompactDialer"];
    BOOL restoredCompactFrame = [self.window setFrameUsingName:frameName];
    if (!restoredCompactFrame) {
        [self.window setFrameUsingName:self.SIPAddress];
    }
    NSSize restoredSize = self.window.contentView.bounds.size;
    self.expandedContentSize = NSMakeSize(MAX(368, restoredSize.width), MAX(268, restoredSize.height));
    self.window.frameAutosaveName = frameName;
    self.window.contentMinSize = NSMakeSize(368, 104);
    [self resizeForHistoryExpanded:NO width:restoredCompactFrame ? MAX(368, restoredSize.width) : 368];

    [self showOfflineStateAnimated:NO];
}

- (NSView *)compactAvailabilityViewWithPopUp:(NSPopUpButton *)popUp image:(NSImageView *)image {
    NSView *oldParent = popUp.superview;
    [oldParent removeConstraints:oldParent.constraints];
    [popUp removeFromSuperview];
    [image removeFromSuperview];
    // The old toolbar box is now empty; in the new nib it is a temporary view.
    [oldParent.superview removeFromSuperview];
    NSView *group = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 44, 44)];
    group.translatesAutoresizingMaskIntoConstraints = NO;
    popUp.translatesAutoresizingMaskIntoConstraints = NO;
    popUp.imagePosition = NSImageOnly;
    popUp.imageScaling = NSImageScaleProportionallyDown;
    popUp.title = @"";
    popUp.accessibilityLabel = NSLocalizedString(@"Availability", @"Account availability accessibility label.");
    image.translatesAutoresizingMaskIntoConstraints = NO;
    image.accessibilityElement = NO;
    image.hidden = YES;
    [group addSubview:popUp];
    [group addSubview:image];
    [NSLayoutConstraint activateConstraints:@[
        [popUp.leadingAnchor constraintEqualToAnchor:group.leadingAnchor],
        [popUp.trailingAnchor constraintEqualToAnchor:group.trailingAnchor],
        [popUp.topAnchor constraintEqualToAnchor:group.topAnchor],
        [popUp.bottomAnchor constraintEqualToAnchor:group.bottomAnchor],
        [image.widthAnchor constraintEqualToConstant:16],
        [image.heightAnchor constraintEqualToConstant:16],
        [image.centerXAnchor constraintEqualToAnchor:group.centerXAnchor constant:-3],
        [image.centerYAnchor constraintEqualToAnchor:group.centerYAnchor]
    ]];
    return group;
}

- (void)displayAvailability:(NSString *)title symbol:(NSString *)symbol color:(NSColor *)color {
    self.accountStatePopUp.title = @"";
    self.accountStatePopUp.toolTip = title;
    self.accountStatePopUp.accessibilityValue = title;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    image.size = NSMakeSize(16, 16);
    // A pull-down draws its first item's image. Using its native image keeps
    // the entire hit region clickable rather than overlaying a separate view.
    self.accountStatePopUp.itemArray.firstObject.image = image;
    self.accountStatePopUp.contentTintColor = color;
    self.accountStateImageView.image = image;
    self.accountStateImageView.contentTintColor = color;
}

- (void)resizeForHistoryExpanded:(BOOL)expanded width:(CGFloat)width {
    NSRect previous = self.window.frame;
    NSSize contentSize = expanded ? self.expandedContentSize : NSMakeSize(width, 104);
    contentSize.width = MAX(368, contentSize.width);
    contentSize.height = expanded ? MAX(268, contentSize.height) : 104;
    self.adjustingFrame = YES;
    self.window.contentMaxSize = NSMakeSize(CGFLOAT_MAX, expanded ? CGFLOAT_MAX : 104);
    NSRect frame = [self.window frameRectForContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    frame.origin = NSMakePoint(NSMinX(previous), NSMaxY(previous) - NSHeight(frame));
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    if (screen != nil) {
        frame = [self.window constrainFrameRect:frame toScreen:screen];
    }
    // Keeping the top edge stable anchors the dial row; no custom animation
    // overrides the user's Reduce Motion preference.
    [self.window setFrame:frame display:YES];
    [self.window.contentView layoutSubtreeIfNeeded];
    for (NSView *view in self.window.contentView.subviews) {
        if ([view isKindOfClass:[AKWindowMaterialView class]]) {
            ((AKWindowMaterialView *)view).usesOpaqueTitlebarBackground = YES;
        }
    }
    self.adjustingFrame = NO;
}

- (IBAction)toggleCallHistory:(id)sender {
    BOOL expanded = !self.accountViewController.historyExpanded;
    CGFloat width = self.window.contentView.bounds.size.width;
    if (!expanded) {
        self.expandedContentSize = self.window.contentView.bounds.size;
    } else {
        self.expandedContentSize = NSMakeSize(width, self.expandedContentSize.height);
    }
    [self.accountViewController setHistoryExpanded:expanded];
    [self resizeForHistoryExpanded:expanded width:width];
}

- (IBAction)showDialerActions:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"More actions", @"Compact dialer actions menu.")];
    NSString *historyTitle = self.accountViewController.historyExpanded
        ? NSLocalizedString(@"Hide full call history", @"Collapse compact dialer history.")
        : NSLocalizedString(@"Show full call history", @"Expand compact dialer history.");
    NSMenuItem *history = [[NSMenuItem alloc] initWithTitle:historyTitle action:@selector(toggleCallHistory:) keyEquivalent:@""];
    history.target = self;
    [menu addItem:history];
    for (NSMenuItem *item in self.accountViewController.callHistoryActionsMenu.itemArray) {
        [menu addItem:[item copy]];
    }
    NSArray<NSMenuItem *> *accounts = [NSApp.windowsMenu.itemArray filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            NSMenuItem *item = object;
            return item.action == NSSelectorFromString(@"toggleAccountWindow:") && item.representedObject != nil;
        }]];
    if (accounts.count > 0) {
        [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *heading = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Accounts", @"Accounts preferences window title.")
                                                      action:NULL keyEquivalent:@""];
        heading.enabled = NO;
        [menu addItem:heading];
        for (NSMenuItem *account in accounts) {
            [menu addItem:[account copy]];
        }
    }
    NSMenuItem *settings = MenuItemWithAction(NSApp.mainMenu, NSSelectorFromString(@"showPreferencePanel:"));
    if (settings != nil) {
        [menu addItem:NSMenuItem.separatorItem];
        [menu addItem:[settings copy]];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds)) inView:sender];
}

#pragma mark -

- (void)showAvailableState {
    [self displayAvailability:NSLocalizedString(@"Available", @"Account registration Available menu item.")
                       symbol:@"checkmark.circle.fill" color:NSColor.systemGreenColor];

    self.availableStateItem.state = NSControlStateValueOn;
    self.unavailableStateItem.state = NSControlStateValueOff;
    self.offlineStateItem.state = NSControlStateValueOff;

    [self.accountViewController showActiveState];
}

- (void)showUnavailableState {
    [self displayAvailability:NSLocalizedString(@"Unavailable", @"Account registration Unavailable menu item.")
                       symbol:@"minus.circle.fill" color:NSColor.systemOrangeColor];

    self.availableStateItem.state = NSControlStateValueOff;
    self.unavailableStateItem.state = NSControlStateValueOn;
    self.offlineStateItem.state = NSControlStateValueOff;

    [self.accountViewController showActiveState];
}

- (void)showOfflineStateAnimated:(BOOL)animated {
    [self displayAvailability:NSLocalizedString(@"Offline", @"Account registration Offline menu item.")
                       symbol:@"xmark.circle.fill" color:NSColor.secondaryLabelColor];

    self.availableStateItem.state = NSControlStateValueOff;
    self.unavailableStateItem.state = NSControlStateValueOff;
    self.offlineStateItem.state = NSControlStateValueOn;

    [self.accountViewController showInactiveStateAnimated:animated];
}

- (void)showOfflineState {
    [self showOfflineStateAnimated:YES];
}

- (void)showConnectingState {
    [self displayAvailability:NSLocalizedString(@"Connecting...", @"Account registration Connecting... menu item.")
                       symbol:@"arrow.triangle.2.circlepath" color:NSColor.secondaryLabelColor];
}

- (void)makeCallToDestination:(NSString *)destination {
    [self.accountViewController makeCallToDestination:destination];
}

- (IBAction)changeAccountState:(NSPopUpButton *)sender {
    if ([sender.selectedItem isEqual:self.offlineStateItem]) {
        [self.delegate accountWindowController:self didChangeAccountState:AccountWindowControllerAccountStateOffline];
    } else if ([sender.selectedItem isEqual:self.availableStateItem]) {
        [self.delegate accountWindowController:self didChangeAccountState:AccountWindowControllerAccountStateAvailable];
    } else if ([sender.selectedItem isEqual:self.unavailableStateItem]) {
        [self.delegate accountWindowController:self didChangeAccountState:AccountWindowControllerAccountStateUnavailable];
    }
}

- (void)showAlert:(NSAlert *)alert {
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)beginSheet:(NSWindow *)sheet {
    [self.window beginSheet:sheet completionHandler:nil];
}

- (void)showWindowWithoutMakingKey {
    [self.window orderFront:self];
}

- (void)hideWindow {
    [self.window orderOut:self];
}

- (BOOL)isWindowKey {
    return self.window.isKeyWindow;
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWindow {
    [self.window orderWindow:place relativeTo:otherWindow];
}

- (NSInteger)windowNumber {
    return self.window.windowNumber;
}

#pragma mark - NSWindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
    if (!self.adjustingFrame && self.accountViewController.historyExpanded) {
        self.expandedContentSize = self.window.contentView.bounds.size;
    }
}

- (BOOL)windowShouldClose:(id)sender {
    [self.window orderOut:self];
    return NO;
}

@end

static NSMenuItem *MenuItemWithAction(NSMenu *menu, SEL action) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == action) {
            return item;
        }
        NSMenuItem *nested = MenuItemWithAction(item.submenu, action);
        if (nested != nil) {
            return nested;
        }
    }
    return nil;
}
