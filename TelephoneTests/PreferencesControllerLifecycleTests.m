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
    // Use the production window and General nibs. No SIP/audio dependencies are
    // needed to open General. Attaching a nonempty table data source can select
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

    NSView *form = controller.generalPreferencesViewController.view;
    XCTAssertEqual(form.window, window);
    XCTAssertGreaterThan(form.subviews.count, 5);
    XCTAssertGreaterThan(form.frame.size.width, 100);
    XCTAssertGreaterThan(form.frame.size.height, 100);
    XCTAssertEqualObjects(window.title, controller.generalPreferencesViewController.title);
    // The rail occupies only 44 logical points, and the selected pane controls
    // the content height. Compare content geometry, allowing native titlebar
    // height to vary between supported macOS versions.
    XCTAssertEqualWithAccuracy(sidebar.enclosingScrollView.frame.size.width, 44, 0.5);
    XCTAssertEqualWithAccuracy(window.contentView.frame.size.width, form.frame.size.width + 44, 0.5);
    XCTAssertEqualWithAccuracy(window.contentView.frame.size.height, form.frame.size.height, 0.5);
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

- (void)testEachProductionPaneFitsAndWindowShrinksBackToGeneral {
    // Registration-domain defaults do not write settings to disk. Empty
    // network strings let the production nib initialize without a SIP agent.
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"STUNServerHost": @"", @"OutboundProxyHost": @"",
        @"RingingSound": @"", @"Accounts": @[]
    }];
    PreferencesController *controller = [[PreferencesController alloc] initWithWindowNibName:@"Preferences"];
    NSWindow *window = controller.window;
    [window setFrameOrigin:NSMakePoint(-20000, -20000)];
    CGFloat generalHeight = window.contentView.frame.size.height;
    NSArray<NSToolbarItem *> *sections = @[
        controller.accountsToolbarItem, controller.soundToolbarItem,
        controller.networkToolbarItem, controller.generalToolbarItem
    ];
    for (NSToolbarItem *section in sections) {
        XCTAssertNoThrow([controller changeView:section]);
        [window.contentView layoutSubtreeIfNeeded];
        NSViewController *pane = [controller valueForKey:@"selectedSettingsController"];
        XCTAssertEqual(pane.view.window, window);
        XCTAssertEqualObjects(window.title, pane.title);
        XCTAssertEqualWithAccuracy(window.contentView.frame.size.width, pane.view.frame.size.width + 44, 0.5);
        XCTAssertEqualWithAccuracy(window.contentView.frame.size.height, pane.view.frame.size.height, 0.5);
        [self assertControlsFitInsideView:pane.view];
    }
    XCTAssertEqualWithAccuracy(window.contentView.frame.size.height, generalHeight, 0.5);
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
