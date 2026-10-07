#import <XCTest/XCTest.h>

#import "GeneralPreferencesViewController.h"
#import "AccountPreferencesViewController.h"
#import "NetworkPreferencesViewController.h"
#import "SoundPreferencesViewController.h"
#import "AKLiquidGlass.h"
#import "PreferencesController.h"

@interface AKGlassControlContainer (MaterialLifecycleTests)
- (void)rebuildSurface;
@end

@interface PreferencesControllerLifecycleTests : XCTestCase
@end

@implementation PreferencesControllerLifecycleTests

- (void)assertSettingsIconsVisibleInSidebar:(NSTableView *)sidebar {
    NSClipView *clip = sidebar.enclosingScrollView.contentView;
    // A44pt clip alone is insufficient: a wider document can centre every
    // otherwise valid icon completely outside the visible navigation rail.
    XCTAssertEqualWithAccuracy(sidebar.frame.size.width, clip.bounds.size.width, 0.5);
    for (NSInteger row = 0; row < sidebar.numberOfRows; row++) {
        NSTableCellView *cell = [sidebar viewAtColumn:0 row:row makeIfNecessary:YES];
        [cell layoutSubtreeIfNeeded];
        XCTAssertNotNil(cell.imageView.image);
        NSRect icon = [cell.imageView convertRect:cell.imageView.bounds toView:clip];
        XCTAssertTrue(NSContainsRect(NSInsetRect(clip.bounds, -0.5, -0.5), icon),
                      @"Section icon%ld is clipped: %@", (long)row, NSStringFromRect(icon));
        XCTAssertEqualWithAccuracy(NSMidX(icon), NSMidX(clip.bounds), 0.5);
        NSRect iconInTable = [cell.imageView convertRect:cell.imageView.bounds toView:sidebar];
        XCTAssertEqual([sidebar rowAtPoint:NSMakePoint(NSMidX(iconInTable), NSMidY(iconInTable))], row);
    }
}

- (void)assertControlsFitInsideView:(NSView *)view {
    XCTAssertFalse(view.hasAmbiguousLayout);
    for (NSView *subview in view.subviews) {
        // A pane can appear to fit even after Auto Layout breaks an obsolete
        // required width. Verify the native alignment size fulfills every
        // explicit required fixed-size constraint, including ancestor-owned
        // ones. AppKit's intrinsic-content subclasses encode hugging and
        // compression separately, despite reporting a required outer priority.
        NSSize alignmentSize = [subview alignmentRectForFrame:subview.frame].size;
        for (NSView *owner = subview; owner != nil; owner = owner.superview) {
            for (NSLayoutConstraint *constraint in owner.constraints) {
                if ([constraint isMemberOfClass:NSLayoutConstraint.class] &&
                    constraint.active && constraint.firstItem == subview && constraint.secondItem == nil &&
                    constraint.relation == NSLayoutRelationEqual && constraint.priority == NSLayoutPriorityRequired) {
                    if (constraint.firstAttribute == NSLayoutAttributeWidth) {
                        XCTAssertEqualWithAccuracy(alignmentSize.width, constraint.constant, 0.5, @"%@", constraint);
                    } else if (constraint.firstAttribute == NSLayoutAttributeHeight) {
                        XCTAssertEqualWithAccuracy(alignmentSize.height, constraint.constant, 0.5, @"%@", constraint);
                    }
                }
            }
        }
        if ([subview isKindOfClass:NSControl.class] ||
            [subview isKindOfClass:NSScrollView.class] ||
            [subview isKindOfClass:NSTabView.class]) {
            // AppKit control frames can extend beyond their alignment rect by
            // a few points for native borders and focus rings.
            XCTAssertTrue(NSContainsRect(NSInsetRect(view.bounds, -3, -3), subview.frame),
                          @"%@ exceeds pane bounds: %@", subview.class, NSStringFromRect(subview.frame));
        }
        if ([subview isKindOfClass:NSTabView.class]) {
            NSTabView *tabs = (NSTabView *)subview;
            NSTabViewItem *selected = tabs.selectedTabViewItem;
            for (NSTabViewItem *item in tabs.tabViewItems) {
                [tabs selectTabViewItem:item];
                [item.view layoutSubtreeIfNeeded];
                [self assertControlsFitInsideView:item.view];
            }
            [tabs selectTabViewItem:selected];
        }
    }
}

- (void)testInitialSettingsWindowLoadsItsSidebarAndGeneralForm {
    // Use the production window, Accounts sizing form and General nibs. No
    // SIP/audio dependencies are needed. A nonempty table data source can select
    // its first row immediately, before windowDidLoad returns.
    PreferencesController *controller = [[PreferencesController alloc] initWithWindowNibName:@"Preferences"];
    __block NSWindow *window;
    XCTAssertNoThrow(window = controller.window);
    XCTAssertNotNil(window);
    if (window == nil) {
        return;
    }
    [window.contentView layoutSubtreeIfNeeded];

    NSTableView *sidebar = [controller valueForKey:@"settingsSidebar"];
    XCTAssertEqual(sidebar.numberOfRows, 4);
    XCTAssertEqual(sidebar.selectedRow, 0);
    NSTableCellView *generalRow = [sidebar viewAtColumn:0 row:0 makeIfNecessary:YES];
    // Icon-only navigation still exposes each section's native name to
    // VoiceOver and pointer users, without consuming a text column.
    XCTAssertNil(generalRow.textField);
    XCTAssertNotNil(generalRow.imageView.image);
    XCTAssertEqualObjects(generalRow.accessibilityLabel, controller.generalToolbarItem.label);
    XCTAssertEqualObjects(generalRow.toolTip, controller.generalToolbarItem.label);
    [self assertSettingsIconsVisibleInSidebar:sidebar];

    NSView *form = controller.generalPreferencesViewController.view;
    XCTAssertEqual(form.window, window);
    XCTAssertGreaterThan(form.subviews.count, 5);
    XCTAssertGreaterThan(form.frame.size.width, 100);
    XCTAssertGreaterThan(form.frame.size.height, 100);
    XCTAssertEqualObjects(window.title, controller.generalPreferencesViewController.title);
    // Accounts determines the shared window dimensions. General retains its
    // compact controls and sits centred inside that larger detail area.
    // Compare content geometry so native titlebar height can vary by OS.
    XCTAssertEqualWithAccuracy(sidebar.enclosingScrollView.frame.size.width, 44, 0.5);
    NSSize accountsSize = controller.accountPreferencesViewController.view.fittingSize;
    XCTAssertEqualWithAccuracy(window.contentView.frame.size.width, ceil(accountsSize.width) + 44, 0.5);
    XCTAssertEqualWithAccuracy(window.contentView.frame.size.height, ceil(accountsSize.height), 0.5);
    NSView *detail = [controller valueForKey:@"settingsDetailView"];
    XCTAssertEqualWithAccuracy(NSMidX(form.frame), NSMidX(detail.bounds), 0.5);
    XCTAssertEqualWithAccuracy(NSMidY(form.frame), NSMidY(detail.bounds), 0.5);
    XCTAssertLessThanOrEqual(form.frame.size.height, 240);
    XCTAssertFalse(form.hasAmbiguousLayout);
    [self assertControlsFitInsideView:form];
    XCTAssertTrue([window.contentView isKindOfClass:[AKWindowMaterialView class]]);
    AKWindowMaterialView *backdrop = (AKWindowMaterialView *)window.contentView;
    BOOL reduced = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    XCTAssertEqual(backdrop.blendingMode, NSVisualEffectBlendingModeBehindWindow);
    XCTAssertEqual(backdrop.material, reduced ? NSVisualEffectMaterialWindowBackground : NSVisualEffectMaterialUnderWindowBackground);
    XCTAssertEqual(window.isOpaque, reduced);
    XCTAssertEqualObjects(window.backgroundColor, NSColor.windowBackgroundColor);
    // Reapplying accessibility options must retain the opaque native titlebar
    // without changing the body material or making the normal window opaque.
    [NSWorkspace.sharedWorkspace.notificationCenter postNotificationName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                                   object:nil];
    XCTAssertEqualObjects(window.backgroundColor, NSColor.windowBackgroundColor);
    XCTAssertEqual(window.isOpaque, reduced);
    XCTAssertEqual(backdrop.material, reduced ? NSVisualEffectMaterialWindowBackground : NSVisualEffectMaterialUnderWindowBackground);
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskTitled) != 0);
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskClosable) != 0);
    XCTAssertFalse((window.styleMask & NSWindowStyleMaskFullSizeContentView) != 0);
    XCTAssertEqual(window.titleVisibility, NSWindowTitleVisible);
    XCTAssertFalse(window.titlebarAppearsTransparent);
    NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
    XCTAssertNotNil(closeButton);
    XCTAssertEqual(closeButton.window, window);
    XCTAssertTrue(closeButton.isEnabled);
    XCTAssertFalse(closeButton.isHiddenOrHasHiddenAncestor);
    XCTAssertGreaterThan(closeButton.alphaValue, 0);
    XCTAssertLessThanOrEqual(NSMaxY([form convertRect:form.bounds toView:nil]), NSMaxY(window.contentLayoutRect));
    // The form must stay below the actual close control, rather than occupying
    // the titlebar's clickable area even when the content material is clear.
    XCTAssertLessThanOrEqual(NSMaxY([form convertRect:form.bounds toView:nil]),
                             NSMinY([closeButton convertRect:closeButton.bounds toView:nil]));
}

- (void)testEachProductionPaneFitsWithoutChangingWindowGeometry {
    // Registration-domain defaults do not write settings to disk. Empty
    // network strings let the production nib initialize without a SIP agent.
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"STUNServerHost": @"", @"OutboundProxyHost": @"",
        @"RingingSound": @"", @"Accounts": @[]
    }];
    PreferencesController *controller = [[PreferencesController alloc] initWithWindowNibName:@"Preferences"];
    NSWindow *window = controller.window;
    [window setFrameOrigin:NSMakePoint(-20000, -20000)];
    NSRect fixedFrame = window.frame;
    NSArray<NSToolbarItem *> *sections = @[
        controller.accountsToolbarItem, controller.soundToolbarItem,
        controller.networkToolbarItem, controller.generalToolbarItem
    ];
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        window.appearance = [NSAppearance appearanceNamed:appearance];
        for (NSToolbarItem *section in sections) {
            XCTAssertNoThrow([controller changeView:section]);
            [window.contentView layoutSubtreeIfNeeded];
            NSViewController *pane = [controller valueForKey:@"selectedSettingsController"];
            NSView *detail = [controller valueForKey:@"settingsDetailView"];
            XCTAssertEqual(pane.view.window, window);
            XCTAssertEqualObjects(window.title, pane.title);
            XCTAssertTrue(NSEqualRects(window.frame, fixedFrame), @"Switching to%@ moved or resized Settings", pane.title);
            XCTAssertTrue(NSContainsRect(NSInsetRect(detail.bounds, -0.5, -0.5), pane.view.frame));
            XCTAssertEqualWithAccuracy(NSMidX(pane.view.frame), NSMidX(detail.bounds), 0.5);
            XCTAssertEqualWithAccuracy(NSMidY(pane.view.frame), NSMidY(detail.bounds), 0.5);
            [self assertSettingsIconsVisibleInSidebar:[controller valueForKey:@"settingsSidebar"]];
            [self assertControlsFitInsideView:pane.view];
        }
    }
    // These controls are easy to lose when compacting the pane: retain the
    // native account tabs/list, four independent audio selectors, recording
    // format/folder controls, and both network host/port pairs.
    XCTAssertNotNil(controller.accountPreferencesViewController.accountsTable);
    NSPopUpButton *format = [controller.generalPreferencesViewController valueForKey:@"recordingFormatPopUpButton"];
    XCTAssertEqual(format.numberOfItems, 3);
    XCTAssertNotNil([controller.generalPreferencesViewController valueForKey:@"recordingFolderPathField"]);
    for (NSString *key in @[@"soundInputPopUp", @"soundOutputPopUp", @"ringtoneOutputPopUp", @"ringtonePopUp"]) {
        XCTAssertNotNil([controller.soundPreferencesViewController valueForKey:key]);
    }
    XCTAssertNotNil(controller.networkPreferencesViewController.STUNServerHostField);
    XCTAssertNotNil(controller.networkPreferencesViewController.STUNServerPortField);
    XCTAssertNotNil(controller.networkPreferencesViewController.outboundProxyHostField);
    XCTAssertNotNil(controller.networkPreferencesViewController.outboundProxyPortField);
}

- (void)testNetworkSectionsExposeTheirDifferentScopes {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"STUNServerHost": @"", @"OutboundProxyHost": @"", @"Accounts": @[]
    }];
    PreferencesController *controller = [[PreferencesController alloc] initWithWindowNibName:@"Preferences"];
    NSWindow *window = controller.window;
    AccountPreferencesViewController *account = controller.accountPreferencesViewController;
    NSView *connectionView = account.proxyHostField.superview;
    NSTabViewItem *connectionItem;
    for (NSView *view in account.view.subviews) {
        if ([view isKindOfClass:NSTabView.class]) {
            for (NSTabViewItem *item in ((NSTabView *)view).tabViewItems) {
                if (item.view == connectionView) {
                    connectionItem = item;
                }
            }
        }
    }
    // Inspect actual localised native tabs and their original proxy/transport
    // controls, rather than testing a disconnected string constant.
    XCTAssertNotNil(connectionItem);
    XCTAssertEqualObjects(connectionItem.label, @"Connection");
    NSString *accountScope = NSLocalizedString(@"Connection settings for the selected account.", nil);
    XCTAssertEqualObjects(connectionItem.toolTip, accountScope);
    XCTAssertEqualObjects(connectionView.accessibilityLabel, accountScope);
    XCTAssertNotNil(account.UDPButton);
    XCTAssertNotNil(account.TCPButton);
    XCTAssertNotNil(account.TLSButton);
    XCTAssertNotNil(account.IPv4Button);
    XCTAssertNotNil(account.IPv6Button);

    [controller changeView:controller.networkToolbarItem];
    XCTAssertEqualObjects(window.title, NSLocalizedString(@"Network — All Accounts", nil));
    NSTableView *sidebar = [controller valueForKey:@"settingsSidebar"];
    NSTableCellView *networkRow = [sidebar viewAtColumn:0 row:3 makeIfNecessary:YES];
    NSString *globalScope = NSLocalizedString(@"Network settings for all accounts.", nil);
    XCTAssertEqualObjects(networkRow.toolTip, globalScope);
    XCTAssertEqualObjects(networkRow.accessibilityHelp, globalScope);
    XCTAssertNotEqualObjects(connectionItem.label, networkRow.accessibilityLabel);
    XCTAssertEqualObjects(((NSView *)[controller valueForKey:@"settingsDetailView"]).accessibilityLabel, window.title);
}

- (void)testNativeCloseControlClosesAndReopensSettings {
    PreferencesController *controller = [[PreferencesController alloc] initWithWindowNibName:@"Preferences"];
    NSWindow *window = controller.window;
    NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
    XCTAssertNotNil(closeButton);
    [window setFrameOrigin:NSMakePoint(-20000, -20000)];
    [controller showWindow:self];
    XCTAssertTrue(window.isVisible);

    // Exercise the system button's action, including the existing window
    // delegate close path, rather than calling NSWindow.close directly.
    [closeButton performClick:self];
    XCTAssertFalse(window.isVisible);

    [controller showWindow:self];
    XCTAssertTrue(window.isVisible);
    XCTAssertEqual(controller.generalPreferencesViewController.view.window, window);
    XCTAssertEqual(((NSTableView *)[controller valueForKey:@"settingsSidebar"]).selectedRow, 0);
    [window orderOut:self];
}

- (void)testMaterialRebuildPreservesFocusedFieldAndSelection {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-20000, -20000, 400, 140)
                                                 styleMask:NSWindowStyleMaskTitled
                                                   backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    AKGlassControlContainer *container = [[AKGlassControlContainer alloc] initWithFrame:window.contentView.bounds sidebar:YES];
    window.contentView = container;
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 300, 24)];
    field.stringValue = @"Focus and selection survive";
    [container.contentView addSubview:field];
    XCTAssertTrue([window makeFirstResponder:field]);
    NSTextView *editor = (NSTextView *)field.currentEditor;
    XCTAssertNotNil(editor);
    editor.selectedRange = NSMakeRange(6, 3);

    [container rebuildSurface];

    XCTAssertEqualObjects(field.stringValue, @"Focus and selection survive");
    XCTAssertEqual(field.currentEditor, window.firstResponder);
    XCTAssertTrue(NSEqualRanges(((NSTextView *)field.currentEditor).selectedRange, NSMakeRange(6, 3)));
    [window close];
}

@end
