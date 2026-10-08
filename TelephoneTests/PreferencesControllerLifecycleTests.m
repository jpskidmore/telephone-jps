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

- (void)assertSectionHeadings:(NSArray<NSString *> *)titles inView:(NSView *)view {
    NSMutableArray<NSTextField *> *headings = [NSMutableArray array];
    NSMutableArray<NSBox *> *separators = [NSMutableArray array];
    for (NSView *subview in view.subviews) {
        if ([subview.identifier isEqualToString:@"SettingsSectionHeading"]) {
            XCTAssertTrue([subview isKindOfClass:NSTextField.class]);
            [headings addObject:(NSTextField *)subview];
        } else if ([subview.identifier isEqualToString:@"SettingsSectionSeparator"]) {
            XCTAssertTrue([subview isKindOfClass:NSBox.class]);
            [separators addObject:(NSBox *)subview];
        }
    }
    XCTAssertEqual(headings.count, titles.count);
    XCTAssertEqual(separators.count, titles.count);
    for (NSUInteger index = 0; index < headings.count && index < titles.count; index++) {
        NSTextField *heading = headings[index];
        XCTAssertEqualObjects(heading.stringValue, titles[index]);
        XCTAssertEqualObjects(heading.accessibilityLabel, titles[index]);
        XCTAssertFalse(heading.isEditable);
        XCTAssertFalse(heading.isSelectable);
        XCTAssertFalse(heading.acceptsFirstResponder);
        NSRect headingAlignment = [heading alignmentRectForFrame:heading.frame];
        XCTAssertEqualWithAccuracy(NSMinX(headingAlignment), 16, 0.5);
        XCTAssertGreaterThanOrEqual(heading.frame.size.width + 0.5, heading.intrinsicContentSize.width);
        XCTAssertTrue(NSContainsRect(view.bounds, heading.frame));
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
        if (@available(macOS 26.0, *)) {
            XCTAssertEqualObjects(heading.accessibilityRole, NSAccessibilityHeadingRole);
        } else {
            XCTAssertEqualObjects(heading.accessibilityRole, NSAccessibilityStaticTextRole);
        }
#else
        XCTAssertEqualObjects(heading.accessibilityRole, NSAccessibilityStaticTextRole);
#endif
        if (index < separators.count) {
            NSBox *line = separators[index];
            NSRect lineAlignment = [line alignmentRectForFrame:line.frame];
            XCTAssertEqual(line.boxType, NSBoxSeparator);
            XCTAssertGreaterThan(line.frame.size.width, 100);
            XCTAssertEqualWithAccuracy(NSMinX(lineAlignment), NSMaxX(headingAlignment) + 10, 0.5);
            XCTAssertEqualWithAccuracy(NSMaxX(lineAlignment), NSMaxX(view.bounds) - 16, 0.5);
        }
    }
    if (headings.count == 2) {
        XCTAssertEqualWithAccuracy(NSMaxY(view.bounds) - NSMaxY(headings[0].frame), 10, 0.5);
        XCTAssertGreaterThan(NSMinY(headings[0].frame), NSMaxY(headings[1].frame));
    }
}

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
    XCTAssertEqual(sidebar.numberOfRows, 5);
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
    // Accounts determines the shared window dimensions. General's titled
    // sections occupy the detail width near the top and leading edge.
    // Compare content geometry so native titlebar height can vary by OS.
    XCTAssertEqualWithAccuracy(sidebar.enclosingScrollView.frame.size.width, 44, 0.5);
    NSSize accountsSize = controller.accountPreferencesViewController.view.fittingSize;
    XCTAssertEqualWithAccuracy(window.contentView.frame.size.width, ceil(accountsSize.width) + 44, 0.5);
    XCTAssertEqualWithAccuracy(window.contentView.frame.size.height, ceil(accountsSize.height), 0.5);
    NSView *detail = [controller valueForKey:@"settingsDetailView"];
    XCTAssertEqualWithAccuracy(NSMinX(form.frame), NSMinX(detail.bounds), 0.5);
    XCTAssertEqualWithAccuracy(form.frame.size.width, detail.bounds.size.width, 0.5);
    XCTAssertEqualWithAccuracy(NSMaxY(detail.bounds) - NSMaxY(form.frame), 12, 0.5);
    XCTAssertLessThanOrEqual(form.frame.size.height, detail.bounds.size.height - 12);
    [self assertSectionHeadings:@[@"Calling", @"Recording"] inView:form];
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
            XCTAssertEqualWithAccuracy(NSMinX(pane.view.frame), NSMinX(detail.bounds), 0.5);
            XCTAssertEqualWithAccuracy(pane.view.frame.size.width, detail.bounds.size.width, 0.5);
            BOOL accounts = pane == controller.accountPreferencesViewController;
            XCTAssertEqualWithAccuracy(NSMaxY(detail.bounds) - NSMaxY(pane.view.frame), accounts ? 0 : 12, 0.5);
            if (accounts) {
                XCTAssertEqualWithAccuracy(pane.view.frame.size.height, detail.bounds.size.height, 0.5);
                [self assertSectionHeadings:@[] inView:pane.view];
            } else if (pane == controller.generalPreferencesViewController) {
                [self assertSectionHeadings:@[@"Calling", @"Recording"] inView:pane.view];
            } else if (pane == controller.soundPreferencesViewController) {
                [self assertSectionHeadings:@[@"Devices & ringtone", @"Call audio"] inView:pane.view];
                NSPopUpButton *input = [pane valueForKey:@"soundInputPopUp"];
                XCTAssertEqualWithAccuracy(NSMinX([input alignmentRectForFrame:input.frame]), 160, 0.5);
            } else if (pane == controller.networkPreferencesViewController) {
                [self assertSectionHeadings:@[@"SIP & discovery", @"Outbound proxy"] inView:pane.view];
                NSTextField *host = controller.networkPreferencesViewController.STUNServerHostField;
                XCTAssertEqualWithAccuracy(NSMinX([host alignmentRectForFrame:host.frame]), 144, 0.5);
            }
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
    NSArray<NSToolbarItem *> *items = [controller valueForKey:@"settingsItems"];
    NSUInteger networkIndex = [items indexOfObject:controller.networkToolbarItem];
    XCTAssertNotEqual(networkIndex, NSNotFound);
    NSTableCellView *networkRow = [sidebar viewAtColumn:0 row:networkIndex makeIfNecessary:YES];
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

#import "AccountSetupController.h"
#import "AuthenticationFailureController.h"
#import "ActiveAccountViewController.h"
#import "AKSIPURI.h"
#import "AKKeychain.h"
#import <Security/Security.h>

@interface ActiveAccountViewController (V30TokenDelegateSeams) <NSTokenFieldDelegate>
@end

@interface AKKeychain (V30SecuritySeams)
+ (OSStatus)addSecurityItem:(NSDictionary *)item;
+ (OSStatus)updateSecurityItem:(NSDictionary *)query attributes:(NSDictionary *)attributes;
@end
static OSStatus V30AddStatus, V30UpdateStatus;
static NSUInteger V30AddCalls, V30UpdateCalls;
@interface V30Keychain : AKKeychain @end
@implementation V30Keychain
+ (OSStatus)addSecurityItem:(NSDictionary *)item { V30AddCalls++; return V30AddStatus; }
+ (OSStatus)updateSecurityItem:(NSDictionary *)query attributes:(NSDictionary *)attributes { V30UpdateCalls++; return V30UpdateStatus; }
@end

@interface V30AccountMemory : NSObject
@property(nonatomic) NSArray *accounts;
@property(nonatomic) NSUInteger writes;
@end
@implementation V30AccountMemory
- (NSArray *)arrayForKey:(NSString *)key { return self.accounts; }
- (void)setObject:(id)value forKey:(NSString *)key { self.accounts = value; self.writes++; }
@end

@interface V30Setup : AccountSetupController
@property(nonatomic) V30AccountMemory *memory;
@property(nonatomic) BOOL allowsSave;
@property(nonatomic) NSUInteger saves, errors, closes;
@end
@implementation V30Setup
- (NSUserDefaults *)accountDefaults { return (id)self.memory; }
- (BOOL)savePassword:(NSString *)password service:(NSString *)service account:(NSString *)account error:(NSError **)error {
    self.saves++;
    if (!self.allowsSave && error) { *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUserCanceled userInfo:nil]; }
    return self.allowsSave;
}
- (void)presentAccountSaveError:(NSError *)error { self.errors++; }
- (IBAction)closeSheet:(id)sender { self.closes++; }
@end

@interface V30Auth : AuthenticationFailureController
@property(nonatomic) NSUInteger errors, saves, closes;
@end
@implementation V30Auth
- (void)awakeFromNib {} // No stored password reads in this isolated form fixture.
- (BOOL)savePassword:(NSString *)password service:(NSString *)service account:(NSString *)account error:(NSError **)error {
    self.saves++;
    if (error) { *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecReadOnly userInfo:nil]; }
    return NO;
}
- (void)presentCredentialError:(NSString *)message field:(NSTextField *)field {
    self.errors++; field.accessibilityHelp = message;
}
- (IBAction)closeSheet:(id)sender { self.closes++; }
@end

@interface V30SelectedTable : NSTableView
@property(nonatomic) NSUInteger reloads;
@end
@implementation V30SelectedTable
- (NSInteger)selectedRow { return 0; }
- (void)reloadData { self.reloads++; }
@end

@interface V30AccountEditor : AccountPreferencesViewController
@property(nonatomic) V30AccountMemory *memory;
@property(nonatomic) BOOL allowsSave;
@property(nonatomic) NSUInteger errors, reads, saves;
@end
@implementation V30AccountEditor
- (NSUserDefaults *)accountDefaults { return (id)self.memory; }
- (NSString *)savedPasswordForService:(NSString *)service account:(NSString *)account { self.reads++; return @"unchanged"; }
- (BOOL)savePassword:(NSString *)password service:(NSString *)service account:(NSString *)account error:(NSError **)error {
    self.saves++;
    if (!self.allowsSave && error) { *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecReadOnly userInfo:nil]; }
    return self.allowsSave;
}
- (void)presentAccountEditError:(NSString *)message field:(NSTextField *)field {
    self.errors++; self.accountEnabledCheckBox.state = NSControlStateValueOff; field.accessibilityHelp = message;
}
@end

@interface V30SoundRetry : SoundPreferencesViewController
@property(nonatomic) NSUInteger retries;
@end
@implementation V30SoundRetry
- (void)updateAvailableSounds {} // Synthetic fixture avoids library and saved ringtone lookup.
- (void)updateSoundIO { self.retries++; }
@end

@interface NSObject (V30AudioConstructors)
- (instancetype)initWithIsSystemDefault:(BOOL)isDefault name:(NSString *)name uniqueIdentifier:(NSString *)uid;
- (instancetype)initWithInput:(NSArray *)input output:(NSArray *)output;
- (instancetype)initWithInput:(id)input output:(id)output ringtoneOutput:(id)ringtoneOutput;
@end

#import "AppController.h"
#import <objc/runtime.h>
#import <Carbon/Carbon.h>

@interface AppController (V30FirstLaunchSeams)
- (void)addAccountOnFirstLaunch:(id)sender;
- (void)accountSetupControllerDidAddAccount:(NSNotification *)notification;
- (void)makeCallOrRememberDestination:(NSString *)destination;
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
- (void)makeCallFromTextService:(NSPasteboard *)pasteboard userData:(NSString *)data error:(NSString **)error;
@end
@interface V30Actions : NSObject
@property(nonatomic) SEL action;
@property(nonatomic, weak) id target;
@end
@implementation V30Actions @end
@interface V30AccountWindow : NSObject
@property(nonatomic) NSUInteger shows;
@end
@implementation V30AccountWindow
- (void)showWindowWithoutMakingKey { self.shows++; }
@end
@interface V30AccountCollection : NSObject
@property(nonatomic) NSMutableArray *items;
@property(nonatomic) NSUInteger registrations, updates;
@end
@implementation V30AccountCollection
- (void)addController:(id)controller { [self.items addObject:controller]; }
- (void)updateCallsShouldDisplayAccountInfo { self.updates++; }
- (void)registerAccountIfManualRegistrationRequired:(id)controller { self.registrations++; }
- (void)update { self.updates++; }
@end
@interface V30SetupBoundary : NSObject
@property(nonatomic) BOOL accepts;
@property(nonatomic) V30Actions *defaultButton, *otherButton;
@property(nonatomic, weak) AppController *receiver;
@end
@implementation V30SetupBoundary
- (BOOL)addAccountAndSave:(id)sender {
    if (!self.accepts) { return NO; }
    [self.receiver accountSetupControllerDidAddAccount:[NSNotification notificationWithName:@"Synthetic account accepted" object:self userInfo:@{}]];
    return YES;
}
@end
@interface V30FirstLaunchReceiver : AppController
@property(nonatomic) V30SetupBoundary *setup;
@property(nonatomic) V30Actions *preferences;
@property(nonatomic) V30AccountWindow *account;
@property(nonatomic) V30AccountCollection *collection;
@property(nonatomic) NSMutableArray *dispatched;
@property(nonatomic) NSUInteger postSetupPreferences;
@end
@implementation V30FirstLaunchReceiver
- (id)accountSetupController { return self.setup; }
- (id)preferencesMenuItem { return self.preferences; }
- (id)accountControllers { return self.collection; }
- (id)accountsMenuItems { return self.collection; }
- (id)accountControllerWithDictionary:(NSDictionary *)dictionary { return self.account; }
- (void)makeCallTo:(NSString *)destination { [self.dispatched addObject:destination]; }
- (void)showAccountPreferencesIfNeeded { self.postSetupPreferences++; }
// The first-launch acceptance test keeps unrelated plan persistence and native
// shared-window creation inert while exercising the real setup transition.
- (void)bootstrapDefaultRouteIfNeeded { }
- (void)showSharedDialler { }
@end

@interface V30AccountRepairsTests : XCTestCase @end
@implementation V30AccountRepairsTests

- (void)testKeychainReportsExactAddAndDuplicateUpdateFailures {
    for (NSNumber *status in @[@(errSecUserCanceled), @(errSecReadOnly), @(errSecAuthFailed)]) {
        V30AddStatus = status.intValue; V30AddCalls = V30UpdateCalls = 0;
        NSError *error;
        XCTAssertFalse([V30Keychain addItemWithService:@"synthetic" account:@"synthetic" password:@"test" error:&error]);
        XCTAssertEqualObjects(error.domain, NSOSStatusErrorDomain);
        XCTAssertEqual(error.code, status.intValue);
        XCTAssertEqual(V30AddCalls, 1); XCTAssertEqual(V30UpdateCalls, 0);
    }
    V30AddStatus = errSecDuplicateItem; V30UpdateStatus = errSecAuthFailed; V30UpdateCalls = 0;
    NSError *error;
    XCTAssertFalse([V30Keychain addItemWithService:@"synthetic" account:@"synthetic" password:@"test" error:&error]);
    XCTAssertEqual(error.code, errSecAuthFailed); XCTAssertEqual(V30UpdateCalls, 1);
    V30UpdateStatus = errSecSuccess;
    XCTAssertTrue([V30Keychain addItemWithService:@"synthetic" account:@"synthetic" password:@"test" error:&error]);
    XCTAssertNil(error);
    V30AddStatus = errSecSuccess;
    XCTAssertTrue([V30Keychain addItemWithService:@"synthetic" account:@"synthetic" password:@"test" error:&error]);
}

- (void)testSetupRejectsWhitespaceAndFailedCredentialsBeforeAccountCommit {
    V30Setup *controller = [[V30Setup alloc] init];
    (void)controller.window;
    controller.memory = [V30AccountMemory new]; controller.memory.accounts = @[];
    NSArray *fields = @[controller.fullNameField, controller.domainField, controller.usernameField];
    for (NSTextField *invalid in fields) {
        for (NSTextField *field in fields) { field.stringValue = @"synthetic"; }
        controller.passwordField.stringValue = @"synthetic-secret";
        invalid.stringValue = @" \t\n";
        XCTAssertFalse([controller addAccountAndSave:nil]);
        XCTAssertEqual(controller.memory.writes, 0); XCTAssertEqual(controller.saves, 0);
        XCTAssertEqual(controller.closes, 0); XCTAssertEqualObjects(controller.passwordField.stringValue, @"synthetic-secret");
    }
    for (NSTextField *field in fields) { field.stringValue = @"synthetic"; }
    XCTAssertFalse([controller addAccountAndSave:nil]);
    XCTAssertEqual(controller.errors, 1); XCTAssertEqual(controller.memory.writes, 0); XCTAssertEqual(controller.closes, 0);
    __block NSUInteger added = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKAccountSetupControllerDidAddAccountNotification
                                                                object:controller queue:nil usingBlock:^(NSNotification *note) { added++; }];
    controller.allowsSave = YES;
    XCTAssertTrue([controller addAccountAndSave:nil]);
    XCTAssertEqual(controller.memory.writes, 1); XCTAssertEqual(controller.memory.accounts.count, 1);
    XCTAssertEqual(controller.closes, 1); XCTAssertEqual(added, 1);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}

- (void)testAuthenticationKeepsInvalidAndUnsavedInputAvailable {
    V30Auth *controller = [[V30Auth alloc] initWithAccountController:nil userAgent:nil];
    (void)controller.window;
    for (NSString *username in @[@"", @" \t\n"]) {
        controller.usernameField.stringValue = username; controller.passwordField.stringValue = @"synthetic-secret";
        [controller changeUsernameAndPassword:nil];
        XCTAssertEqual(controller.closes, 0); XCTAssertEqual(controller.saves, 0);
        XCTAssertEqualObjects(controller.passwordField.stringValue, @"synthetic-secret");
        XCTAssertGreaterThan(controller.usernameField.accessibilityHelp.length, 0);
    }
    controller.usernameField.stringValue = @"synthetic";
    controller.mustSaveCheckBox.state = NSControlStateValueOn;
    [controller changeUsernameAndPassword:nil];
    XCTAssertEqual(controller.closes, 0); XCTAssertEqual(controller.saves, 1);
    XCTAssertEqualObjects(controller.passwordField.stringValue, @"synthetic-secret");
    [controller closeSheet:nil]; XCTAssertEqual(controller.closes, 1);
}

- (void)testExistingAccountRejectsInvalidAndFailedSaveBeforeLockingFields {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"Accounts": @[]}];
    V30AccountEditor *controller = [[V30AccountEditor alloc] init]; (void)controller.view;
    V30SelectedTable *table = [[V30SelectedTable alloc] init]; controller.accountsTable = table;
    controller.memory = [V30AccountMemory new];
    NSDictionary *old = @{@"UUID": @"synthetic", @"AccountEnabled": @NO, @"Domain": @"old-domain", @"Username": @"old-user"};
    controller.memory.accounts = @[old];
    controller.passwordField.stringValue = @"unchanged";
    for (NSArray *values in @[@[@"", @"user"], @[@"domain", @""], @[@" \t\n", @" \t\n"]]) {
        controller.domainField.enabled = controller.usernameField.enabled = YES;
        controller.accountEnabledCheckBox.state = NSControlStateValueOn;
        controller.domainField.stringValue = values[0]; controller.usernameField.stringValue = values[1];
        [controller changeAccountEnabled:nil];
        XCTAssertEqualObjects(controller.memory.accounts, @[old]); XCTAssertEqual(controller.memory.writes, 0);
        XCTAssertEqual(controller.reads, 0); XCTAssertEqual(controller.saves, 0);
        XCTAssertEqual(controller.accountEnabledCheckBox.state, NSControlStateValueOff);
        XCTAssertTrue(controller.domainField.enabled); XCTAssertTrue(controller.usernameField.enabled);
    }
    controller.domainField.stringValue = @"valid-domain"; controller.usernameField.stringValue = @"valid-user";
    controller.passwordField.stringValue = @"changed"; controller.accountEnabledCheckBox.state = NSControlStateValueOn;
    [controller changeAccountEnabled:nil];
    XCTAssertEqual(controller.saves, 1); XCTAssertEqual(controller.memory.writes, 0);
    XCTAssertEqualObjects(controller.memory.accounts, @[old]); XCTAssertTrue(controller.domainField.enabled);
    controller.allowsSave = YES; controller.accountEnabledCheckBox.state = NSControlStateValueOn;
    [controller changeAccountEnabled:nil];
    XCTAssertEqual(controller.memory.writes, 1); XCTAssertEqualObjects(controller.memory.accounts[0][@"Domain"], @"valid-domain");
    XCTAssertFalse(controller.domainField.enabled);
    controller.accountEnabledCheckBox.state = NSControlStateValueOff; [controller changeAccountEnabled:nil];
    XCTAssertTrue(controller.domainField.enabled);
    controller.domainField.stringValue = @""; controller.SIPAddressField.stringValue = @"sip:synthetic@example.invalid";
    controller.registrarField.stringValue = @"example.invalid"; controller.accountEnabledCheckBox.state = NSControlStateValueOn;
    [controller changeAccountEnabled:nil]; XCTAssertEqual(controller.memory.writes, 3);
}

- (void)testSoundFailuresRetryOnAppearanceAndPreserveLastValidMenus {
    V30SoundRetry *controller = [[V30SoundRetry alloc] initWithEventTarget:nil userAgent:nil]; (void)controller.view;
    [controller viewWillAppear]; XCTAssertEqual(controller.retries, 0);
    [controller showSoundIOLoadError:@"Synthetic device query failure"];
    NSPopUpButton *input = [controller valueForKey:@"soundInputPopUp"];
    XCTAssertFalse(input.enabled); XCTAssertGreaterThan(input.accessibilityHelp.length, 0);
    [controller viewWillAppear]; [controller viewWillAppear]; XCTAssertEqual(controller.retries, 2);
    NSMenu *lastValid = [[NSMenu alloc] init]; [lastValid addItemWithTitle:@"Synthetic microphone" action:nil keyEquivalent:@""];
    input.menu = lastValid; input.enabled = YES;
    [controller showSoundIOLoadError:@"Synthetic later failure"];
    XCTAssertEqual(input.menu, lastValid); XCTAssertEqualObjects(input.selectedItem.title, @"Synthetic microphone");
    XCTAssertTrue(input.enabled);
}

- (void)assertPurpose:(NSString *)purpose control:(NSControl *)control {
    id descendant = NSAccessibilityUnignoredDescendant(control);
    // SDK27 defines this native protocol property as AXDescription. Calling the
    // deprecated raw attribute method directly bypasses modern label overrides.
    XCTAssertTrue([descendant conformsToProtocol:@protocol(NSAccessibility)]);
    NSString *label = [(id<NSAccessibility>)descendant accessibilityLabel];
    XCTAssertEqualObjects(label, purpose, @"%@", descendant);
}

- (void)testActualNibsHaveAccurateNativeAccessibilityPurposes {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"Accounts": @[], @"STUNServerHost": @"", @"OutboundProxyHost": @""}];
    PreferencesController *preferences = [[PreferencesController alloc] initWithWindowNibName:@"Preferences"]; (void)preferences.window;
    [self assertPurpose:@"Recording format" control:[preferences.generalPreferencesViewController valueForKey:@"recordingFormatPopUpButton"]];
    (void)preferences.soundPreferencesViewController.view;
    NSDictionary *soundLabels = @{@"soundInputPopUp": @"Microphone", @"soundOutputPopUp": @"Call output", @"ringtoneOutputPopUp": @"Ringtone output", @"ringtonePopUp": @"Ringtone"};
    for (NSString *key in soundLabels) { [self assertPurpose:soundLabels[key] control:[preferences.soundPreferencesViewController valueForKey:key]]; }
    NetworkPreferencesViewController *network = preferences.networkPreferencesViewController; (void)network.view;
    [self assertPurpose:@"Local SIP port" control:network.transportPortField];
    [self assertPurpose:@"STUN server host" control:network.STUNServerHostField];
    [self assertPurpose:@"STUN server port" control:network.STUNServerPortField];
    [self assertPurpose:@"Outbound proxy host" control:network.outboundProxyHostField];
    [self assertPurpose:@"Outbound proxy port" control:network.outboundProxyPortField];
    [self assertPurpose:@"Clear outbound proxy" control:network.deleteOutboundProxyButton];
    XCTAssertEqualObjects(network.deleteOutboundProxyButton.toolTip, @"Clear outbound proxy");
    network.outboundProxyHostField.stringValue = @"proxy.invalid"; network.outboundProxyPortField.stringValue = @"5060";
    [network viewDidAppear]; XCTAssertFalse(network.deleteOutboundProxyButton.hidden);
    XCTAssertTrue([network areNetworkSettingsChanged:nil]);
    [network performSelector:@selector(deleteOutboundProxy:) withObject:nil];
    XCTAssertEqualObjects(network.outboundProxyHostField.stringValue, @""); XCTAssertEqualObjects(network.outboundProxyPortField.stringValue, @"");
    XCTAssertTrue(network.deleteOutboundProxyButton.hidden);
    XCTAssertFalse([network areNetworkSettingsChanged:nil]);
    AccountPreferencesViewController *account = preferences.accountPreferencesViewController; (void)account.view;
    NSDictionary *accountLabels = @{@"accountDescriptionField": @"Account description", @"fullNameField": @"Full name", @"domainField": @"Account domain", @"usernameField": @"Account username", @"passwordField": @"Account password", @"reregistrationTimeField": @"Registration interval", @"plusCharacterSubstitutionField": @"Plus character replacement", @"proxyHostField": @"Account proxy host", @"proxyPortField": @"Account proxy port", @"SIPAddressField": @"SIP address", @"registrarField": @"Registrar"};
    for (NSString *key in accountLabels) { [self assertPurpose:accountLabels[key] control:[account valueForKey:key]]; }
    V30Setup *setup = [[V30Setup alloc] init]; (void)setup.window;
    [self assertPurpose:@"Full name" control:setup.fullNameField]; [self assertPurpose:@"Domain" control:setup.domainField];
    [self assertPurpose:@"Username" control:setup.usernameField]; [self assertPurpose:@"Password" control:setup.passwordField];
    V30Auth *authentication = [[V30Auth alloc] initWithAccountController:nil userAgent:nil]; (void)authentication.window;
    [self assertPurpose:@"Username" control:authentication.usernameField]; [self assertPurpose:@"Password" control:authentication.passwordField];
}

- (void)testTokenSelectionBelongsToEachTokenAndExtraInputIsRejectedSafely {
    ActiveAccountViewController *controller = [[ActiveAccountViewController alloc] initWithNibName:@"ActiveAccountView" bundle:nil];
    NSTokenField *field = [[NSTokenField alloc] init]; controller.callDestinationField = field;
    AKSIPURI *one = [[AKSIPURI alloc] initWithUser:@"100" host:@"" displayName:@"Synthetic contact"];
    AKSIPURI *two = [[AKSIPURI alloc] initWithUser:@"200" host:@"" displayName:@"Synthetic contact"];
    NSArray *contact = @[@{kURI: one, kPhoneLabel: @"home"}, @{kURI: two, kPhoneLabel: @"mobile"}];
    field.objectValue = @[contact]; controller.callDestinationURIIndex = 1;
    NSArray *shortToken = @[@{kURI: one, kPhoneLabel: @"home"}]; field.objectValue = @[contact, shortToken];
    XCTAssertEqualObjects(controller.callDestinationURI.user, @"200");
    XCTAssertNoThrow([controller tokenField:field displayStringForRepresentedObject:shortToken]);
    field.tokenStyle = NSTokenStyleRounded;
    XCTAssertEqual([[controller tokenField:field shouldAddObjects:@[shortToken] atIndex:1] count], 0);
    NSMenu *menu = [controller tokenField:field menuForRepresentedObject:contact];
    [controller changeCallDestinationURIIndex:[menu itemWithTag:0]];
    XCTAssertEqualObjects(controller.callDestinationURI.user, @"100");
    XCTAssertEqualObjects([controller tokenField:field editingStringForRepresentedObject:contact], @"Synthetic contact <100>");
    field.objectValue = @[shortToken, contact];
    [controller changeCallDestinationURIIndex:[menu itemWithTag:1]];
    XCTAssertEqualObjects(controller.callDestinationURI.user, @"100");
    XCTAssertNoThrow([controller tokenField:field displayStringForRepresentedObject:shortToken]);
    XCTAssertNil([controller tokenField:field displayStringForRepresentedObject:@[]]);
    XCTAssertFalse([controller tokenField:field hasMenuForRepresentedObject:@"invalid"]);
}

- (void)testSoundDeviceMenusSelectDuplicateNamesByUIDAndClearRetryOnRecovery {
    V30SoundRetry *controller = [[V30SoundRetry alloc] initWithEventTarget:nil userAgent:nil]; (void)controller.view;
    Class deviceClass = NSClassFromString(@"Telephone.PresentationAudioDevice");
    Class devicesClass = NSClassFromString(@"Telephone.PresentationAudioDevices");
    Class soundClass = NSClassFromString(@"Telephone.PresentationSoundIO");
    XCTAssertNotNil(deviceClass); XCTAssertNotNil(devicesClass); XCTAssertNotNil(soundClass);
    id first = [[deviceClass alloc] initWithIsSystemDefault:NO name:@"USB Headset" uniqueIdentifier:@"USB-00000001"];
    id second = [[deviceClass alloc] initWithIsSystemDefault:NO name:@"USB Headset" uniqueIdentifier:@"USB-00000002"];
    id devices = [[devicesClass alloc] initWithInput:@[first, second] output:@[second, first]];
    id selection = [[soundClass alloc] initWithInput:second output:first ringtoneOutput:second];
    [controller showSoundIOLoadError:@"Synthetic failure"];
    [controller updateWithSoundIO:selection devices:devices];
    NSPopUpButton *input = [controller valueForKey:@"soundInputPopUp"];
    NSPopUpButton *output = [controller valueForKey:@"soundOutputPopUp"];
    XCTAssertTrue(input.enabled); XCTAssertEqual(input.selectedItem.representedObject, second);
    XCTAssertEqual(output.selectedItem.representedObject, first);
    XCTAssertNotEqualObjects([input itemAtIndex:0].title, [input itemAtIndex:1].title);
    XCTAssertNil(input.accessibilityHelp);
    [controller viewWillAppear]; XCTAssertEqual(controller.retries, 0);
}

- (void)testFirstLaunchTransitionsOnlyAfterAcceptedAccountAndDrainsExternalRequestsOnce {
    // Allocate only the receiver layout. Its real initializer starts the app and
    // loads saved accounts, so it is intentionally never called in this fixture.
    V30FirstLaunchReceiver *receiver = class_createInstance(V30FirstLaunchReceiver.class, 0);
    CFRetain((__bridge CFTypeRef)receiver); // Preserve until this disposable host exits; no production dealloc queries.
    receiver.setup = [V30SetupBoundary new]; receiver.setup.receiver = receiver;
    receiver.setup.defaultButton = [V30Actions new]; receiver.setup.otherButton = [V30Actions new];
    receiver.setup.defaultButton.action = @selector(addAccountOnFirstLaunch:);
    receiver.setup.otherButton.action = @selector(performClose:);
    receiver.preferences = [V30Actions new]; receiver.account = [V30AccountWindow new];
    receiver.collection = [V30AccountCollection new]; receiver.collection.items = [NSMutableArray new];
    receiver.dispatched = [NSMutableArray new];
    [receiver setValue:@NO forKey:@"finishedLaunching"];
    [receiver makeCallOrRememberDestination:@"queued-before-setup"];
    [receiver addAccountOnFirstLaunch:nil];
    XCTAssertFalse([[receiver valueForKey:@"finishedLaunching"] boolValue]);
    XCTAssertEqual(receiver.setup.defaultButton.action, @selector(addAccountOnFirstLaunch:));
    XCTAssertEqual(receiver.setup.otherButton.action, @selector(performClose:));
    XCTAssertEqual(receiver.preferences.action, NULL); XCTAssertEqual(receiver.dispatched.count, 0);
    XCTAssertEqual(receiver.collection.items.count, 0);
    receiver.setup.accepts = YES; [receiver addAccountOnFirstLaunch:nil];
    XCTAssertTrue([[receiver valueForKey:@"finishedLaunching"] boolValue]);
    XCTAssertEqual(receiver.collection.items.count, 1); XCTAssertEqual(receiver.collection.registrations, 1);
    XCTAssertEqual(receiver.account.shows, 1);
    XCTAssertEqualObjects(receiver.dispatched, (@[@"queued-before-setup"]));
    XCTAssertEqualObjects([receiver valueForKey:@"destinationToCall"], @"");
    XCTAssertEqual(receiver.preferences.action, @selector(showPreferencePanel:));
    XCTAssertEqual(receiver.setup.defaultButton.action, @selector(addAccount:));
    XCTAssertEqual(receiver.setup.otherButton.action, @selector(closeSheet:));
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass eventID:kAEGetURL
        targetDescriptor:[NSAppleEventDescriptor nullDescriptor] returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"url-after-setup"] forKeyword:keyDirectObject];
    [receiver handleGetURLEvent:event withReplyEvent:nil];
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [pasteboard writeObjects:@[@"service-after-setup"]];
    [receiver makeCallFromTextService:pasteboard userData:nil error:NULL];
    [pasteboard releaseGlobally];
    XCTAssertEqualObjects(receiver.dispatched, (@[@"queued-before-setup", @"url-after-setup", @"service-after-setup"]));
    XCTAssertEqual(receiver.postSetupPreferences, 1);
}
@end

#import "AKSIPUserAgent.h"

@interface V30AudioAdmissionAgent : AKSIPUserAgent
@property(nonatomic) NSMutableArray *operations, *completions;
@property(nonatomic) NSUInteger publishes, reconnections, refreshes;
@end
@implementation V30AudioAdmissionAgent
- (BOOL)isStarted { return YES; }
- (void)performSIPOperation:(pj_status_t (^)(void))operation completion:(void (^)(pj_status_t))completion {
    [self.operations addObject:[operation copy]];
    [self.completions addObject:completion ? [completion copy] : NSNull.null];
}
- (void)publishAudioState { self.publishes++; }
- (void)restoreCurrentAudioConnections { self.reconnections++; }
- (void)updateAudioDevices { self.refreshes++; }
@end

@interface V30BlockingAudioController : NSObject
@property(nonatomic) dispatch_semaphore_t releaseGate;
@property(nonatomic) XCTestExpectation *entered;
@property(nonatomic) BOOL hasFailed;
@end
@implementation V30BlockingAudioController
- (int)selectInput:(int)input output:(int)output {
    XCTAssertFalse(NSThread.isMainThread); [self.entered fulfill];
    return dispatch_semaphore_wait(self.releaseGate, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0 ? 0 : PJ_EUNKNOWN;
}
@end

@interface V30AudioAdmissionTests : XCTestCase @end
@implementation V30AudioAdmissionTests
- (V30AudioAdmissionAgent *)agent {
    // Disposable receiver layout only. Its initializer and destructor touch
    // PJSUA, so neither runs in this zero-hardware admission fixture.
    V30AudioAdmissionAgent *agent = class_createInstance(V30AudioAdmissionAgent.class, 0);
    CFRetain((__bridge CFTypeRef)agent);
    agent.operations = [NSMutableArray new]; agent.completions = [NSMutableArray new];
    [agent setValue:@1 forKey:@"audioGeneration"];
    return agent;
}
- (void)testOlderCompletionCannotUnlockANewerAdmittedSelection {
    V30AudioAdmissionAgent *agent = [self agent];
    __block NSUInteger firstRuns = 0, secondRuns = 0;
    XCTAssertTrue([agent performAudioSelection:^pj_status_t(NSUInteger revision) { firstRuns++; return PJ_SUCCESS; }]);
    XCTAssertTrue(agent.audioCommandPending); XCTAssertFalse([agent beginOutgoingCall]);
    XCTAssertTrue([agent performAudioSelection:^pj_status_t(NSUInteger revision) { secondRuns++; return PJ_SUCCESS; }]);
    pj_status_t (^oldOperation)(void) = agent.operations[0];
    void (^oldCompletion)(pj_status_t) = agent.completions[0];
    XCTAssertEqual(oldOperation(), PJ_ECANCELLED); oldCompletion(PJ_ECANCELLED);
    XCTAssertTrue(agent.audioCommandPending); XCTAssertEqual(firstRuns, 0);
    pj_status_t (^newOperation)(void) = agent.operations[1];
    void (^newCompletion)(pj_status_t) = agent.completions[1];
    XCTAssertEqual(newOperation(), PJ_SUCCESS); newCompletion(PJ_SUCCESS);
    XCTAssertFalse(agent.audioCommandPending); XCTAssertEqual(secondRuns, 1);
}
- (void)testBlockedNativeOpenDoesNotRecoverOrReconnectAnInvalidatedGeneration {
    V30AudioAdmissionAgent *agent = [self agent];
    V30BlockingAudioController *backend = [V30BlockingAudioController new];
    backend.releaseGate = dispatch_semaphore_create(0); backend.entered = [self expectationWithDescription:@"Actual native selection worker entered blocked backend"];
    [agent setValue:backend forKey:@"audioDeviceController"];
    [agent setValue:@YES forKey:@"audioRecoveryPending"];
    XCTAssertTrue([agent setSoundInputDevice:3 soundOutputDevice:7]);
    XCTAssertTrue(agent.audioCommandPending); XCTAssertFalse([agent beginOutgoingCall]);
    XCTestExpectation *complete = [self expectationWithDescription:@"Native worker returned after stale generation"];
    pj_status_t (^operation)(void) = agent.operations[0];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        pj_status_t status = operation();
        dispatch_async(dispatch_get_main_queue(), ^{ XCTAssertEqual(status, PJ_EUNKNOWN); [complete fulfill]; });
    });
    [self waitForExpectations:@[backend.entered] timeout:2];
    XCTestExpectation *responsive = [self expectationWithDescription:@"Main still processes UI while native open blocks"];
    dispatch_async(dispatch_get_main_queue(), ^{ [responsive fulfill]; });
    [self waitForExpectations:@[responsive] timeout:1];
    [agent setValue:@2 forKey:@"audioGeneration"];
    dispatch_semaphore_signal(backend.releaseGate);
    [self waitForExpectations:@[complete] timeout:3];
    XCTAssertTrue(agent.hasAudioFailure); XCTAssertEqual(agent.reconnections, 0);
}
- (void)testCancelledRetryReleasesItsOwnPendingFlagWithoutStartingSelection {
    V30AudioAdmissionAgent *agent = [self agent];
    [agent setValue:@YES forKey:@"audioRecoveryPending"];
    __block NSUInteger retries = 0;
    agent.soundIOSelectionRetry = ^{ retries++; return YES; };
    XCTAssertTrue([agent retrySoundAfterFailure]);
    [agent setValue:@2 forKey:@"audioGeneration"];
    void (^retryCompletion)(pj_status_t) = agent.completions[0]; retryCompletion(PJ_ECANCELLED);
    XCTAssertFalse(agent.audioCommandPending); XCTAssertEqual(retries, 0);
}
- (void)testStaleRetryRefreshCompletionDoesNotReplaceNewerSelection {
    V30AudioAdmissionAgent *agent = [self agent];
    [agent setValue:@YES forKey:@"audioRecoveryPending"];
    __block NSUInteger retries = 0;
    agent.soundIOSelectionRetry = ^{ retries++; return YES; };
    XCTAssertTrue([agent retrySoundAfterFailure]);
    XCTAssertTrue([agent performAudioSelection:^pj_status_t(NSUInteger revision) { return PJ_SUCCESS; }]);
    void (^retryCompletion)(pj_status_t) = agent.completions[0]; retryCompletion(PJ_SUCCESS);
    XCTAssertTrue(agent.audioCommandPending); XCTAssertEqual(retries, 0);
}
@end
