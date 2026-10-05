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
    XCTAssertTrue((window.styleMask & NSWindowStyleMaskFullSizeContentView) != 0);
    NSLayoutGuide *contentGuide = window.contentLayoutGuide;
    XCTAssertLessThanOrEqual(NSMaxY([form convertRect:form.bounds toView:window.contentView]), NSMaxY(contentGuide.layoutFrame));
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
