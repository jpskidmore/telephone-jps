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
@property(nonatomic) NSSize settingsContentSize;
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
    self.networkToolbarItem.toolTip = NSLocalizedString(@"Network settings for all accounts.", @"App-wide Network section scope.");
}

- (void)windowDidLoad {
    [super windowDidLoad];
    // Retain the nib's action items so deep links and unsaved-network prompts
    // continue to use exactly the same section-selection path.
    self.navigationToolbar = self.toolbar;
    self.settingsItems = @[self.generalToolbarItem, self.accountsToolbarItem,
                           self.soundToolbarItem, self.networkToolbarItem];
    self.window.toolbar = nil;
    // Keep a dedicated native titlebar for the window title and close control.
    // The material belongs to the content area below the system window chrome.
    self.window.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
    self.window.toolbarStyle = NSWindowToolbarStyleAutomatic;
    self.window.titleVisibility = NSWindowTitleVisible;
    self.window.titlebarAppearsTransparent = NO;
    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
    self.window.autorecalculatesKeyViewLoop = YES;
    // The Accounts form is the largest pane. Determine the shared content
    // size once so navigating Settings never moves or resizes the window.
    NSSize accountsSize = self.accountPreferencesViewController.view.fittingSize;
    self.settingsContentSize = NSMakeSize(ceil(accountsSize.width) + 44, ceil(accountsSize.height));
    [self buildSettingsSidebar];
    [self.window setContentSize:self.settingsContentSize];
    [self displaySettingsController:self.generalPreferencesViewController];
    [self selectSidebarItem:self.generalToolbarItem];
}

- (void)buildSettingsSidebar {
    // NSTableView can select its first row synchronously when a data source is
    // attached. Suppress navigation until the complete detail hierarchy exists.
    self.updatingSidebarSelection = YES;
    self.settingsContainerController = [[NSViewController alloc] init];
    AKWindowMaterialView *container = [[AKWindowMaterialView alloc] initWithFrame:NSMakeRect(0, 0, self.settingsContentSize.width, self.settingsContentSize.height)];
    container.usesOpaqueTitlebarBackground = YES;
    self.settingsContainerController.view = container;
    self.contentViewController = self.settingsContainerController;

    AKGlassControlContainer *sidebar = [[AKGlassControlContainer alloc] initWithFrame:NSZeroRect sidebar:YES];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:sidebar];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hasVerticalScroller = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsSidebar = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"SettingsSection"];
    column.minWidth = 44;
    column.maxWidth = 44;
    column.width = 44;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.settingsSidebar addTableColumn:column];
    self.settingsSidebar.headerView = nil;
    // Plain native rows have no source-list side insets. The document must
    // match this narrow icon rail so its centred symbols stay inside the clip.
    self.settingsSidebar.style = NSTableViewStylePlain;
    self.settingsSidebar.rowSizeStyle = NSTableViewRowSizeStyleCustom;
    self.settingsSidebar.rowHeight = 36;
    self.settingsSidebar.intercellSpacing = NSMakeSize(0, 4);
    self.settingsSidebar.backgroundColor = NSColor.clearColor;
    self.settingsSidebar.allowsEmptySelection = NO;
    self.settingsSidebar.allowsMultipleSelection = NO;
    self.settingsSidebar.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.settingsSidebar.accessibilityLabel = NSLocalizedString(@"Settings sections", @"Settings navigation accessibility label.");
    scroll.documentView = self.settingsSidebar;
    [sidebar.contentView addSubview:scroll];

    self.settingsDetailView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.settingsDetailView.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsDetailView.accessibilityElement = YES;
    self.settingsDetailView.accessibilityRole = NSAccessibilityGroupRole;
    [container addSubview:self.settingsDetailView];
    NSLayoutGuide *contentGuide = self.window.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:44],
        [scroll.leadingAnchor constraintEqualToAnchor:sidebar.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:sidebar.contentView.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:sidebar.contentView.topAnchor constant:8],
        [scroll.bottomAnchor constraintEqualToAnchor:sidebar.contentView.bottomAnchor constant:-8],
        [self.settingsDetailView.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [self.settingsDetailView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.settingsDetailView.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
        [self.settingsDetailView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];
    self.settingsSidebar.dataSource = self;
    self.settingsSidebar.delegate = self;
    [self.settingsSidebar reloadData];
    self.updatingSidebarSelection = NO;
}

- (void)displaySettingsController:(NSViewController *)controller {
    if (self.selectedSettingsController != controller) {
        [NSLayoutConstraint deactivateConstraints:self.settingsPaneConstraints ?: @[]];
        [self.selectedSettingsController.view removeFromSuperview];
        [self.selectedSettingsController removeFromParentViewController];
        // Native labels separate related options without adding another glass
        // surface or another stop in the keyboard focus loop.
        for (NSView *view in controller.view.subviews) {
            if ([view.identifier isEqualToString:@"SettingsSectionHeading"] &&
                [view isKindOfClass:NSTextField.class]) {
                NSTextField *heading = (NSTextField *)view;
                heading.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
                heading.accessibilityLabel = heading.stringValue;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
                if (@available(macOS 26.0, *)) {
                    heading.accessibilityRole = NSAccessibilityHeadingRole;
                } else {
                    heading.accessibilityRole = NSAccessibilityStaticTextRole;
                }
#else
                heading.accessibilityRole = NSAccessibilityStaticTextRole;
#endif
            }
        }
        CGFloat paneHeight = ceil(controller.view.fittingSize.height);
        BOOL accountsPane = controller == self.accountPreferencesViewController;
        self.selectedSettingsController = controller;
        [self.settingsContainerController addChildViewController:controller];
        [self.settingsDetailView addSubview:controller.view];
        controller.view.translatesAutoresizingMaskIntoConstraints = NO;
        // Accounts occupies the complete detail area. Other forms share its
        // width, with their titled sections anchored near the top and leading
        // edge, while the window itself keeps the same Accounts-sized frame.
        self.settingsPaneConstraints = @[
            [controller.view.leadingAnchor constraintEqualToAnchor:self.settingsDetailView.leadingAnchor],
            [controller.view.topAnchor constraintEqualToAnchor:self.settingsDetailView.topAnchor constant:accountsPane ? 0 : 12],
            [controller.view.widthAnchor constraintEqualToAnchor:self.settingsDetailView.widthAnchor],
            [controller.view.heightAnchor constraintEqualToConstant:paneHeight]
        ];
        [NSLayoutConstraint activateConstraints:self.settingsPaneConstraints];
    }
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.settingsSidebar sizeToFit];
    self.window.title = controller.title ?: NSLocalizedString(@"Settings", @"Settings window title.");
    self.settingsDetailView.accessibilityLabel = self.window.title;
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
        [cell addSubview:image];
        cell.imageView = image;
        [NSLayoutConstraint activateConstraints:@[
            [image.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
            [image.widthAnchor constraintEqualToConstant:18],
            [image.heightAnchor constraintEqualToConstant:18],
            [image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    NSToolbarItem *item = self.settingsItems[row];
    cell.imageView.image = item.image;
    cell.toolTip = item.toolTip ?: item.label;
    cell.accessibilityElement = YES;
    cell.accessibilityRole = NSAccessibilityCellRole;
    cell.accessibilityLabel = item.label;
    cell.accessibilityHelp = item.toolTip;
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
    [self displaySettingsController:controller];
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
