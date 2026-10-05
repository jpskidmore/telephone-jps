#import <XCTest/XCTest.h>

#import "GeneralPreferencesViewController.h"
#import "AKLiquidGlass.h"
#import "PreferencesController.h"

@interface AKGlassControlContainer (MaterialLifecycleTests)
- (void)rebuildSurface;
@end

@interface PreferencesControllerLifecycleTests : XCTestCase
@end

@implementation PreferencesControllerLifecycleTests

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
    XCTAssertEqualObjects(generalRow.textField.stringValue, controller.generalToolbarItem.label);

    NSView *form = controller.generalPreferencesViewController.view;
    XCTAssertEqual(form.window, window);
    XCTAssertGreaterThan(form.subviews.count, 5);
    XCTAssertGreaterThan(form.frame.size.width, 100);
    XCTAssertGreaterThan(form.frame.size.height, 100);
    XCTAssertEqualObjects(window.title, NSLocalizedString(@"Settings", @"Settings window title."));
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
