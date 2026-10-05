//
//  PreferencesController.m
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

#import "PreferencesController.h"
#import "AKLiquidGlass.h"

#import "AccountPreferencesViewController.h"
#import "GeneralPreferencesViewController.h"
#import "NetworkPreferencesViewController.h"
#import "SoundPreferencesViewController.h"

@interface PreferencesController () <NSTableViewDelegate, NSTableViewDataSource>
@property(nonatomic) NSViewController *settingsContainerController;
@property(nonatomic) NSViewController *selectedSettingsController;
@property(nonatomic) NSView *settingsDetailView;
@property(nonatomic) NSTableView *settingsSidebar;
@property(nonatomic) NSToolbar *navigationToolbar;
@property(nonatomic) NSArray<NSToolbarItem *> *settingsItems;
@property(nonatomic) NSArray<NSLayoutConstraint *> *settingsPaneConstraints;
@property(nonatomic) BOOL updatingSidebarSelection;
@end

@implementation PreferencesController

@synthesize generalPreferencesViewController = _generalPreferencesViewController;
@synthesize accountPreferencesViewController = _accountPreferencesViewController;
@synthesize soundPreferencesViewController = _soundPreferencesViewController;
@synthesize networkPreferencesViewController = _networkPreferencesViewController;

- (void)setDelegate:(id)aDelegate {
    if (_delegate == aDelegate) {
        return;
    }
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    if (_delegate != nil)
        [nc removeObserver:_delegate name:nil object:self];
    
    if (aDelegate != nil) {
        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidRemoveAccount:)]) {
            [nc addObserver:aDelegate
                   selector:@selector(preferencesControllerDidRemoveAccount:)
                       name:AKPreferencesControllerDidRemoveAccountNotification
                     object:self];
        }
        
        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidChangeAccountEnabled:)]) {
            [nc addObserver:aDelegate
                   selector:@selector(preferencesControllerDidChangeAccountEnabled:)
                       name:AKPreferencesControllerDidChangeAccountEnabledNotification
                     object:self];
        }
        
        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidSwapAccounts:)]) {
            [nc addObserver:aDelegate
                   selector:@selector(preferencesControllerDidSwapAccounts:)
                       name:AKPreferencesControllerDidSwapAccountsNotification
                     object:self];
        }
        
        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidChangeNetworkSettings:)]) {
            [nc addObserver:aDelegate
                   selector:@selector(preferencesControllerDidChangeNetworkSettings:)
                       name:AKPreferencesControllerDidChangeNetworkSettingsNotification
                     object:self];
        }
    }
    
    _delegate = aDelegate;
}

- (GeneralPreferencesViewController *)generalPreferencesViewController {
    if (_generalPreferencesViewController == nil) {
        _generalPreferencesViewController = [[GeneralPreferencesViewController alloc] init];
    }
    return _generalPreferencesViewController;
}

- (AccountPreferencesViewController *)accountPreferencesViewController {
    if (_accountPreferencesViewController == nil) {
        _accountPreferencesViewController = [[AccountPreferencesViewController alloc] init];
        [_accountPreferencesViewController setPreferencesController:self];
    }
    return _accountPreferencesViewController;
}

- (SoundPreferencesViewController *)soundPreferencesViewController {
    if (![self isSoundPreferencesViewControllerLoaded]) {
        _soundPreferencesViewController
            = [[SoundPreferencesViewController alloc] initWithEventTarget:_soundPreferencesViewEventTarget
                                                                userAgent:self.userAgent];
    }
    return _soundPreferencesViewController;
}

- (NetworkPreferencesViewController *)networkPreferencesViewController {
    if (_networkPreferencesViewController == nil) {
        _networkPreferencesViewController
            = [[NetworkPreferencesViewController alloc] initWithPreferencesController:self userAgent:self.userAgent];
    }
    return _networkPreferencesViewController;
}

- (BOOL)isSoundPreferencesViewControllerLoaded {
    return _soundPreferencesViewController != nil;
}

- (instancetype)initWithDelegate:(id<PreferencesControllerDelegate>)delegate
                       userAgent:(AKSIPUserAgent *)userAgent
 soundPreferencesViewEventTarget:(SoundPreferencesViewEventTarget *)soundPreferencesViewEventTarget {
    if ((self = [super initWithWindowNibName:@"Preferences"])) {
        self.delegate = delegate;
        _userAgent = userAgent;
        _soundPreferencesViewEventTarget = soundPreferencesViewEventTarget;
    }
    return self;
}

- (void)dealloc {
    [self setDelegate:nil];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.generalToolbarItem.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil];
    self.accountsToolbarItem.image = [NSImage imageWithSystemSymbolName:@"at" accessibilityDescription:nil];
    self.soundToolbarItem.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2" accessibilityDescription:nil];
    self.networkToolbarItem.image = [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:nil];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    // Retain the nib's action items so deep links and unsaved-network prompts
    // continue to use exactly the same section-selection path.
    self.navigationToolbar = self.toolbar;
    self.settingsItems = @[self.generalToolbarItem, self.accountsToolbarItem,
                           self.soundToolbarItem, self.networkToolbarItem];
    self.window.toolbar = nil;
    self.window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    self.window.titlebarAppearsTransparent = YES;
    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    self.window.autorecalculatesKeyViewLoop = YES;
    [self buildSettingsSidebar];
    [self displaySettingsController:self.generalPreferencesViewController animate:NO];
    [self selectSidebarItem:self.generalToolbarItem];
}

- (void)buildSettingsSidebar {
    // NSTableView can select its first row synchronously when a data source is
    // attached. Suppress navigation until the complete detail hierarchy exists.
    self.updatingSidebarSelection = YES;
    self.settingsContainerController = [[NSViewController alloc] init];
    NSView *container = [[AKWindowMaterialView alloc] initWithFrame:NSMakeRect(0, 0, 708, 360)];
    self.settingsContainerController.view = container;
    self.contentViewController = self.settingsContainerController;

    AKGlassControlContainer *sidebar = [[AKGlassControlContainer alloc] initWithFrame:NSZeroRect sidebar:YES];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:sidebar];
    NSTextField *heading = [NSTextField labelWithString:NSLocalizedString(@"Settings", @"Settings sidebar heading.")];
    heading.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    heading.textColor = NSColor.secondaryLabelColor;
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar.contentView addSubview:heading];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hasVerticalScroller = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsSidebar = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"SettingsSection"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.settingsSidebar addTableColumn:column];
    self.settingsSidebar.headerView = nil;
    self.settingsSidebar.style = NSTableViewStyleSourceList;
    self.settingsSidebar.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    self.settingsSidebar.backgroundColor = NSColor.clearColor;
    self.settingsSidebar.allowsEmptySelection = NO;
    self.settingsSidebar.allowsMultipleSelection = NO;
    self.settingsSidebar.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.settingsSidebar.accessibilityLabel = NSLocalizedString(@"Settings sections", @"Settings navigation accessibility label.");
    scroll.documentView = self.settingsSidebar;
    [sidebar.contentView addSubview:scroll];

    self.settingsDetailView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.settingsDetailView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.settingsDetailView];
    NSLayoutGuide *contentGuide = self.window.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [sidebar.topAnchor constraintEqualToAnchor:contentGuide.topAnchor constant:12],
        [sidebar.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
        [sidebar.widthAnchor constraintEqualToConstant:176],
        [heading.leadingAnchor constraintEqualToAnchor:sidebar.contentView.leadingAnchor constant:16],
        [heading.topAnchor constraintEqualToAnchor:sidebar.contentView.topAnchor constant:16],
        [heading.trailingAnchor constraintLessThanOrEqualToAnchor:sidebar.contentView.trailingAnchor constant:-16],
        [scroll.leadingAnchor constraintEqualToAnchor:sidebar.contentView.leadingAnchor constant:6],
        [scroll.trailingAnchor constraintEqualToAnchor:sidebar.contentView.trailingAnchor constant:-6],
        [scroll.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:10],
        [scroll.bottomAnchor constraintEqualToAnchor:sidebar.contentView.bottomAnchor constant:-12],
        [self.settingsDetailView.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:12],
        [self.settingsDetailView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.settingsDetailView.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
        [self.settingsDetailView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];
    self.settingsSidebar.dataSource = self;
    self.settingsSidebar.delegate = self;
    [self.settingsSidebar reloadData];
    self.updatingSidebarSelection = NO;
}

- (void)displaySettingsController:(NSViewController *)controller animate:(BOOL)animate {
    NSSize paneSize = controller.view.frame.size;
    if (self.selectedSettingsController != controller) {
        [NSLayoutConstraint deactivateConstraints:self.settingsPaneConstraints ?: @[]];
        [self.selectedSettingsController.view removeFromSuperview];
        [self.selectedSettingsController removeFromParentViewController];
        self.selectedSettingsController = controller;
        [self.settingsContainerController addChildViewController:controller];
        [self.settingsDetailView addSubview:controller.view];
        controller.view.translatesAutoresizingMaskIntoConstraints = NO;
        self.settingsPaneConstraints = @[
            [controller.view.leadingAnchor constraintEqualToAnchor:self.settingsDetailView.leadingAnchor],
            [controller.view.topAnchor constraintEqualToAnchor:self.settingsDetailView.topAnchor],
            [controller.view.widthAnchor constraintEqualToConstant:paneSize.width],
            [controller.view.heightAnchor constraintEqualToConstant:paneSize.height]
        ];
        [NSLayoutConstraint activateConstraints:self.settingsPaneConstraints];
    }
    // Resize without the legacy helper, which replaces window.contentView.
    CGFloat titlebarHeight = NSHeight(self.window.contentView.bounds) - NSHeight(self.window.contentLayoutRect);
    NSSize contentSize = NSMakeSize(paneSize.width + 200, MAX(paneSize.height, 360) + titlebarHeight);
    NSRect frame = self.window.frame;
    CGFloat heightDelta = contentSize.height - self.window.contentView.frame.size.height;
    frame.size.width += contentSize.width - self.window.contentView.frame.size.width;
    frame.size.height += heightDelta;
    frame.origin.y -= heightDelta;
    [self.window setFrame:frame display:YES animate:animate && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion];
    self.window.title = NSLocalizedString(@"Settings", @"Settings window title.");
    [self.window recalculateKeyViewLoop];
}

- (void)selectSidebarItem:(NSToolbarItem *)item {
    self.updatingSidebarSelection = YES;
    self.toolbar.selectedItemIdentifier = item.itemIdentifier;
    NSUInteger index = [self.settingsItems indexOfObject:item];
    if (index != NSNotFound) {
        [self.settingsSidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    }
    self.updatingSidebarSelection = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.settingsItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"SettingsSection" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"SettingsSection";
        NSImageView *image = [[NSImageView alloc] initWithFrame:NSZeroRect];
        image.translatesAutoresizingMaskIntoConstraints = NO;
        image.contentTintColor = NSColor.controlAccentColor;
        image.accessibilityElement = NO;
        NSTextField *label = [NSTextField labelWithString:@""];
        label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:image];
        [cell addSubview:label];
        cell.imageView = image;
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [image.widthAnchor constraintEqualToConstant:18],
            [image.heightAnchor constraintEqualToConstant:18],
            [image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [label.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:8],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    NSToolbarItem *item = self.settingsItems[row];
    cell.textField.stringValue = item.label;
    cell.imageView.image = item.image;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (!self.updatingSidebarSelection && self.settingsSidebar.selectedRow >= 0) {
        BOOL keepSidebarFocus = self.window.firstResponder == self.settingsSidebar;
        [self changeView:self.settingsItems[self.settingsSidebar.selectedRow]];
        if (keepSidebarFocus && self.window.attachedSheet == nil) {
            [self.window makeFirstResponder:self.settingsSidebar];
        }
    }
}

- (IBAction)changeView:(id)sender {
    if ([self isNetworkPreferencesViewCurrent] &&
        ![sender isEqual:self.networkToolbarItem] &&
        [self.networkPreferencesViewController areNetworkSettingsChanged:sender]) {
        [self selectSidebarItem:self.networkToolbarItem];
        return;
    }
    
    NSViewController *controller;
    NSString *title;
    NSView *firstResponder;
    
    if ([sender isEqual:self.generalToolbarItem]) {
        controller = self.generalPreferencesViewController;
        title = self.generalPreferencesViewController.title;
        firstResponder = nil;
    } else if ([sender isEqual:self.accountsToolbarItem]) {
        controller = self.accountPreferencesViewController;
        title = self.accountPreferencesViewController.title;
        firstResponder = self.accountPreferencesViewController.accountsTable;
    } else if ([sender isEqual:self.soundToolbarItem]) {
        controller = self.soundPreferencesViewController;
        title = self.soundPreferencesViewController.title;
        firstResponder = nil;
    } else if ([sender isEqual:self.networkToolbarItem]) {
        controller = self.networkPreferencesViewController;
        title = self.networkPreferencesViewController.title;
        firstResponder = nil;
    } else {
        controller = nil;
        title = NSLocalizedString(@"Telephone Preferences", @"Preferences default window title.");
        firstResponder = nil;
    }

    if (controller == nil) {
        self.window.title = title;
        return;
    }
    [self displaySettingsController:controller animate:YES];
    [self selectSidebarItem:sender];
    if ([firstResponder acceptsFirstResponder]) {
        [self.window makeFirstResponder:firstResponder];
    }
}

- (void)showWindowCentered {
    if (!self.window.isVisible) {
        [self.window center];
    }
    [self showWindow:self];
}

- (void)showAccounts {
    self.toolbar.selectedItemIdentifier = self.accountsToolbarItem.itemIdentifier;
    [self changeView:self.accountsToolbarItem];
}

- (void)showSound {
    [self showWindowCentered];
    self.toolbar.selectedItemIdentifier = self.soundToolbarItem.itemIdentifier;
    [self changeView:self.soundToolbarItem];
}

- (BOOL)isNetworkPreferencesViewCurrent {
    return self.selectedSettingsController == self.networkPreferencesViewController;
}


#pragma mark - SoundIOPreferences

- (void)updateSoundIO {
    if ([self isSoundPreferencesViewControllerLoaded]) {
        [self.soundPreferencesViewController updateSoundIO];
    }
}


#pragma mark -
#pragma mark NSToolbar delegate

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)aToolbar {
    return @[[[self generalToolbarItem] itemIdentifier],
            [[self accountsToolbarItem] itemIdentifier],
            [[self soundToolbarItem] itemIdentifier],
            [[self networkToolbarItem] itemIdentifier]];
}


#pragma mark -
#pragma mark NSWindow delegate

- (BOOL)windowShouldClose:(id)window {
    if ([self isNetworkPreferencesViewCurrent] &&
        [[self networkPreferencesViewController] areNetworkSettingsChanged:window]) {
        return NO;
    }
    return YES;
}

@end
