#import "SharedDialerController.h"
#import "AccountController.h"
#import "AccountControllers.h"
#import "ActiveAccountViewController.h"
#import "AKLiquidGlass.h"
#import "AKSIPURI.h"
#import "Telephone-Swift.h"

@interface JPSCompactAvailabilityPopUp : NSPopUpButton
@end
@implementation JPSCompactAvailabilityPopUp
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0,0,0,0); }
@end

@interface SharedDialerController () <NSWindowDelegate, NSMenuDelegate>
@property(nonatomic) AccountControllers *accounts;
@property(nonatomic) AsyncCallHistoryViewEventTargetFactory *historyFactory;
@property(nonatomic) ActiveAccountViewController *dialler;
@property(nonatomic) CallHistoryViewController *history;
@property(nonatomic) CallHistoryViewEventTarget *historyTarget;
@property(nonatomic) NSPopUpButton *availability;
@property(nonatomic) BOOL expanded;
@property(nonatomic) BOOL adjustingFrame;
@property(nonatomic) NSSize expandedSize;
@property(nonatomic) BOOL menuTracking;
@property(nonatomic) BOOL availabilityRefreshPending;
@end

@implementation SharedDialerController
- (instancetype)initWithAccounts:(AccountControllers *)accounts historyFactory:(AsyncCallHistoryViewEventTargetFactory *)factory {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,368,104)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _accounts = accounts; _historyFactory = factory;
        window.title = @"jps Telephone";
        window.delegate = self;
        window.releasedWhenClosed = NO;
        window.tabbingMode = NSWindowTabbingModeDisallowed;
        window.contentMinSize = NSMakeSize(368,104);
        window.contentMaxSize = NSMakeSize(CGFLOAT_MAX,104);
        window.excludedFromWindowsMenu = YES;
        _expandedSize = NSMakeSize(368,268);
        AKWindowMaterialView *body = [[AKWindowMaterialView alloc] initWithFrame:NSMakeRect(0,0,368,104)];
        body.usesOpaqueTitlebarBackground = YES;
        body.material = NSVisualEffectMaterialWindowBackground;
        body.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        body.state = NSVisualEffectStateFollowsWindowActiveState;
        window.contentView = body;
        _dialler = [[ActiveAccountViewController alloc] initWithNibName:@"ActiveAccountView" bundle:nil];
        _history = [[CallHistoryViewController alloc] init];
        _availability = [[JPSCompactAvailabilityPopUp alloc] initWithFrame:NSMakeRect(0,0,44,44) pullsDown:YES];
        _availability.translatesAutoresizingMaskIntoConstraints = NO;
        _availability.imagePosition = NSImageOnly;
        _availability.bezelStyle = NSBezelStyleRounded;
        _availability.imageScaling = NSImageScaleProportionallyDown;
        ((NSPopUpButtonCell *)_availability.cell).arrowPosition = NSPopUpNoArrow;
        _availability.accessibilityLabel = @"Account availability";
        _availability.cell.accessibilityLabel = @"Account availability";
        _availability.menu.delegate = self;
        __weak SharedDialerController *weakSelf = self;
        _dialler.callDestinationHandler = ^(AKSIPURI *uri, NSString *label) {
            [DialPlanCoordinator.shared routeURI:uri phoneLabel:label];
        };
        if (factory != nil) _dialler.callRoutePreviewHandler = ^NSString *(AKSIPURI *uri, NSString *text) {
            if (text.length == 0) return @"Call";
            AKSIPURI *address = [uri copy]; address.displayName = @"";
            NSString *input = address ? (address.host.length ? address.description : address.user) : text;
            DialPlanRoute *route = [DialPlanStore.shared resolveDestination:input accounts:[DialPlanCoordinator.shared accountSnapshots]];
            return [NSString stringWithFormat:@"%@\n%@", route.destination.destination,route.message];
        };
        (void)_dialler.view;
        [_dialler installCompactDialerWithAvailabilityView:_availability target:self historyAction:@selector(toggleHistory:) moreAction:@selector(showActions:)];
        [_dialler allowCallDestinationInput];
        [_history setHistoryExpanded:NO];
        NSView *dialView = _dialler.view; NSView *historyView = _history.view;
        dialView.translatesAutoresizingMaskIntoConstraints = NO;
        historyView.translatesAutoresizingMaskIntoConstraints = NO;
        [body addSubview:dialView]; [body addSubview:historyView];
        NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
        separator.boxType = NSBoxSeparator; separator.translatesAutoresizingMaskIntoConstraints = NO;
        [body addSubview:separator];
        [NSLayoutConstraint activateConstraints:@[
            [dialView.topAnchor constraintEqualToAnchor:body.topAnchor], [dialView.leadingAnchor constraintEqualToAnchor:body.leadingAnchor], [dialView.trailingAnchor constraintEqualToAnchor:body.trailingAnchor], [dialView.heightAnchor constraintEqualToConstant:56],
            [separator.topAnchor constraintEqualToAnchor:dialView.bottomAnchor], [separator.leadingAnchor constraintEqualToAnchor:body.leadingAnchor], [separator.trailingAnchor constraintEqualToAnchor:body.trailingAnchor], [separator.heightAnchor constraintEqualToConstant:1],
            [historyView.topAnchor constraintEqualToAnchor:separator.bottomAnchor], [historyView.leadingAnchor constraintEqualToAnchor:body.leadingAnchor], [historyView.trailingAnchor constraintEqualToAnchor:body.trailingAnchor], [historyView.bottomAnchor constraintEqualToAnchor:body.bottomAnchor]
        ]];
        [_dialler updateNextKeyView:_history.keyView]; [_history updateNextKeyView:_dialler.keyView];
        if (factory != nil) {
            [window setFrameUsingName:@"JPS.SharedCompactDialler"];
            window.frameAutosaveName = @"JPS.SharedCompactDialler";
        }
        [self resizeForHistory:NO];
        [_historyFactory makeGlobalWithAccounts:[self historyAccounts] view:_history callDestinationHandler:^(NSString *destination, NSString *label, NSString *displayName) {
            [DialPlanCoordinator.shared routeDestination:destination phoneLabel:label displayName:displayName];
        } completion:^(CallHistoryViewEventTarget *target) {
            weakSelf.historyTarget = target; weakSelf.history.target = target;
        }];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountStateChanged:) name:@"JPSAccountRoutingStateDidChangeNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountStateChanged:) name:@"JPSDialPlanDidChangeNotification" object:nil];
        [self refreshAccounts];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (NSArray<CallHistoryAccount *> *)historyAccounts {
    NSMutableArray *result = [NSMutableArray array];
    for (AccountController *account in self.accounts.all) {
        [result addObject:[[CallHistoryAccount alloc] initWithUUID:account.account.uuid name:account.accountDescription domain:account.account.domain]];
    }
    return result;
}
- (void)refreshAccounts {
    [self.historyFactory updateGlobalAccounts:[self historyAccounts]];
    [self rebuildAvailability];
}
- (void)accountStateChanged:(NSNotification *)notification { [self rebuildAvailability]; [self.dialler refreshCallRoutePreview]; }
- (void)rebuildAvailability {
    if (self.menuTracking) { self.availabilityRefreshPending = YES; return; }
    BOOL online = NO, unavailable = NO;
    for (AccountController *account in self.accounts.enabled) {
        if (account.isAccountRegistered) online = YES;
        if ([account.routingAvailability isEqualToString:@"unavailable"]) unavailable = YES;
    }
    NSString *state = online ? @"Online" : unavailable ? @"Unavailable" : @"Offline";
    NSString *symbol = online ? @"checkmark.circle.fill" : unavailable ? @"minus.circle.fill" : @"xmark.circle.fill";
    NSColor *colour = online ? NSColor.systemGreenColor : unavailable ? NSColor.secondaryLabelColor : NSColor.systemRedColor;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:state];
    image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.whiteColor,colour]]];
    image.template = NO; image.size = NSMakeSize(16,16);
    [self.availability removeAllItems];
    [self.availability addItemWithTitle:@""]; self.availability.itemArray.firstObject.image = image;
    self.availability.toolTip = state; self.availability.accessibilityValue = state;
    for (AccountController *account in self.accounts.all) {
        NSMenuItem *heading = [[NSMenuItem alloc] initWithTitle:account.accountDescription action:NULL keyEquivalent:@""];
        NSMenu *submenu = [[NSMenu alloc] initWithTitle:account.accountDescription];
        NSArray *states = @[@"online",@"unavailable",@"offline"];
        NSArray *titles = @[@"Online",@"Unavailable",@"Offline"];
        for (NSUInteger index=0;index<states.count;index++) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[index] action:@selector(changeAvailability:) keyEquivalent:@""];
            item.target = self; item.representedObject = @{@"account":account,@"state":states[index]}; item.enabled = account.isEnabled;
            NSString *current = account.routingAvailability;
            if ([current isEqualToString:states[index]]) item.state = NSControlStateValueOn;
            item.attributedTitle = [[NSAttributedString alloc] initWithString:titles[index] attributes:@{NSForegroundColorAttributeName:index==0 ? NSColor.systemGreenColor : index==2 ? NSColor.systemRedColor : NSColor.labelColor}];
            [submenu addItem:item];
        }
        heading.submenu = submenu; [self.availability.menu addItem:heading];
    }
}
- (void)menuNeedsUpdate:(NSMenu *)menu { [self rebuildAvailability]; }
- (void)menuWillOpen:(NSMenu *)menu { self.menuTracking = YES; }
- (void)menuDidClose:(NSMenu *)menu {
    self.menuTracking = NO;
    if (self.availabilityRefreshPending) { self.availabilityRefreshPending = NO; [self rebuildAvailability]; }
}
- (void)changeAvailability:(NSMenuItem *)sender {
    [sender.representedObject[@"account"] changeRoutingAvailability:sender.representedObject[@"state"]];
    if (![sender.representedObject[@"state"] isEqualToString:@"offline"]) [DialPlanCoordinator.shared startBackend];
}
- (void)resizeForHistory:(BOOL)expanded {
    NSRect old = self.window.frame;
    NSSize content = NSMakeSize(MAX(368,self.window.contentView.bounds.size.width),expanded ? self.expandedSize.height : 104);
    self.adjustingFrame = YES;
    self.window.contentMaxSize = NSMakeSize(CGFLOAT_MAX,expanded ? CGFLOAT_MAX : 104);
    NSRect frame = [self.window frameRectForContentRect:NSMakeRect(0,0,content.width,content.height)];
    frame.origin = NSMakePoint(old.origin.x,NSMaxY(old)-frame.size.height);
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    if (screen) {
        frame = [self.window constrainFrameRect:frame toScreen:screen];
        NSRect visible = screen.visibleFrame;
        if (NSWidth(frame) <= NSWidth(visible)) frame.origin.x = MIN(MAX(NSMinX(frame),NSMinX(visible)),NSMaxX(visible)-NSWidth(frame));
        if (NSHeight(frame) <= NSHeight(visible)) frame.origin.y = MIN(MAX(NSMinY(frame),NSMinY(visible)),NSMaxY(visible)-NSHeight(frame));
    }
    [self.window setFrame:frame display:YES]; self.adjustingFrame = NO;
}
- (void)toggleHistory:(id)sender {
    self.expanded = !self.expanded; [self.history setHistoryExpanded:self.expanded];
    [self.dialler updateHistoryExpanded:self.expanded]; [self resizeForHistory:self.expanded];
}
- (void)showActions:(NSView *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    for (NSMenuItem *item in self.history.actionsMenu.itemArray) if (item.action == NSSelectorFromString(@"deleteAll:")) [menu addItem:[item copy]];
    for (AccountController *account in self.accounts.all) if (account.hasPendingRoutedCalls) {
        NSMenuItem *cancel = [[NSMenuItem alloc] initWithTitle:@"Cancel pending calls" action:@selector(cancelPendingCalls:) keyEquivalent:@""];
        cancel.target = self; [menu addItem:cancel]; break;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Guided routes…" action:@selector(showGuidedRoutes:) keyEquivalent:@""];
    settings.target = self; [menu addItem:settings];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,NSMaxY(sender.bounds)) inView:sender];
}
- (void)cancelPendingCalls:(id)sender { for (AccountController *account in self.accounts.all) [account cancelPendingRoutedCalls]; }
- (void)showGuidedRoutes:(id)sender { [NSApp sendAction:NSSelectorFromString(@"showGuidedRoutes:") to:nil from:self]; }
- (void)presentFailure:(NSString *)message {
    [self showWindow:self];
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"Call could not be placed"; alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    if (self.window.attachedSheet == nil) [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (BOOL)windowShouldClose:(NSWindow *)sender { [sender orderOut:self]; return NO; }
- (void)windowDidResize:(NSNotification *)notification {
    if (self.expanded && !self.adjustingFrame) self.expandedSize = self.window.contentView.bounds.size;
}
@end
