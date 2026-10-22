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

@interface SharedDialerController () <NSWindowDelegate, NSMenuDelegate, NSPopoverDelegate>
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
@property(nonatomic) NSPopover *pendingPopover;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *pendingRequests;
@property(nonatomic, copy) NSArray<NSButton *> *pendingCancelButtons;
@end

@implementation SharedDialerController
- (instancetype)initWithAccounts:(AccountControllers *)accounts historyFactory:(AsyncCallHistoryViewEventTargetFactory *)factory {
    SharedDialerRouteResolver resolver = nil;
    if (factory != nil) resolver = ^DialPlanRoute *(NSString *input, NSArray<DialPlanAccount *> *accounts) {
        return [DialPlanStore.shared resolveDestination:input accounts:accounts];
    };
    return [self initWithAccounts:accounts historyFactory:factory routeResolver:resolver];
}
- (instancetype)initWithAccounts:(AccountControllers *)accounts
                 historyFactory:(AsyncCallHistoryViewEventTargetFactory *)factory
                  routeResolver:(SharedDialerRouteResolver)routeResolver {
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
        if (routeResolver != nil) _dialler.callRoutePreviewHandler = ^NSString *(AKSIPURI *uri, NSString *text) {
            SharedDialerController *owner = weakSelf;
            if (owner == nil) return @"Call";
            if (text.length == 0) return @"Call";
            AKSIPURI *address = [uri copy]; address.displayName = @"";
            NSString *input = address ? (address.host.length ? address.description : address.user) : text;
            NSArray<DialPlanAccount *> *snapshot = [owner routeAccountSnapshots];
            DialPlanRoute *route = routeResolver(input, snapshot);
            DialPlanRoutePresentation *presentation = [[DialPlanRoutePresentation alloc] initWithRoute:route accounts:snapshot];
            return presentation.detailText;
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pendingCallsChanged:) name:JPSPendingRoutedCallsDidChangeNotification object:nil];
        [self refreshAccounts];
    }
    return self;
}
- (void)dealloc {
    self.pendingPopover.delegate = nil;
    [self.pendingPopover close];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (NSArray<CallHistoryAccount *> *)historyAccounts {
    NSMutableArray *result = [NSMutableArray array];
    for (AccountController *account in self.accounts.all) {
        [result addObject:[[CallHistoryAccount alloc] initWithUUID:account.account.uuid name:account.accountDescription domain:account.account.domain]];
    }
    return result;
}
- (NSArray<DialPlanAccount *> *)routeAccountSnapshots {
    NSMutableArray<DialPlanAccount *> *snapshot = [NSMutableArray array];
    for (AccountController *account in self.accounts.all) {
        [snapshot addObject:[[DialPlanAccount alloc] initWithUUID:account.accountUUID name:account.accountDescription
                                                        enabled:account.isEnabled availability:account.routingAvailability]];
    }
    return snapshot.copy;
}
- (void)refreshAccounts {
    [self.historyFactory updateGlobalAccounts:[self historyAccounts]];
    [self rebuildAvailability];
    [self.dialler refreshCallRoutePreview];
    [self refreshPendingCalls];
    // AppController has admitted additions/removals/replacements before this
    // boundary; editor previews must not read the earlier preferences signal.
    [NSNotificationCenter.defaultCenter postNotificationName:DialPlanStore.accountsChangeNotificationName object:nil];
}
- (void)accountStateChanged:(NSNotification *)notification { [self rebuildAvailability]; [self.dialler refreshCallRoutePreview]; }
- (void)pendingCallsChanged:(NSNotification *)notification { [self refreshPendingCalls]; }
- (void)refreshPendingCalls {
    NSResponder *focused = self.pendingPopover.contentViewController.view.window.firstResponder;
    NSUInteger focusedIndex = [self.pendingCancelButtons indexOfObjectIdenticalTo:focused];
    NSMutableArray *requests = [NSMutableArray array];
    for (AccountController *account in self.accounts.all) [requests addObjectsFromArray:account.pendingRoutedCallSummaries];
    self.pendingRequests = requests;
    [self.dialler setPendingCallCount:requests.count target:self action:@selector(showPendingCalls:)];
    if (self.pendingPopover.isShown) {
        if (requests.count == 0) [self.pendingPopover close];
        else {
            [self rebuildPendingPopover];
            if (focusedIndex != NSNotFound) {
                NSButton *next = self.pendingCancelButtons[MIN(focusedIndex, self.pendingCancelButtons.count - 1)];
                [next.window makeFirstResponder:next];
                [next scrollRectToVisible:next.bounds];
            }
        }
    }
}
- (void)showPendingCalls:(NSButton *)sender {
    if (self.pendingPopover.isShown) { [self.pendingPopover close]; return; }
    if (self.pendingRequests.count == 0) return;
    [self rebuildPendingPopover];
    [self.pendingPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSMinYEdge];
    [self configurePendingKeyLoop];
    NSButton *first = self.pendingCancelButtons.firstObject;
    [first.window makeFirstResponder:first];
}
- (void)rebuildPendingPopover {
    if (self.pendingPopover == nil) {
        self.pendingPopover = [[NSPopover alloc] init];
        self.pendingPopover.behavior = NSPopoverBehaviorTransient;
        self.pendingPopover.animates = NO;
        self.pendingPopover.delegate = self;
    }
    CGFloat width = 330, rowHeight = 52;
    CGFloat rowsHeight = rowHeight * self.pendingRequests.count;
    CGFloat visibleHeight = MIN(288, rowsHeight), height = visibleHeight + 38;
    NSViewController *content = [[NSViewController alloc] init];
    content.view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,width,height)];
    NSTextField *heading = [NSTextField labelWithString:NSLocalizedString(@"Waiting for registration", @"Waiting call list heading.")];
    heading.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    heading.frame = NSMakeRect(12,height-28,width-24,18);
    [content.view addSubview:heading];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,width,visibleHeight)];
    scroll.borderType = NSNoBorder; scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = rowsHeight > visibleHeight;
    scroll.autohidesScrollers = YES;
    NSView *rows = [[NSView alloc] initWithFrame:NSMakeRect(0,0,width-16,rowsHeight)];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < self.pendingRequests.count; index++) {
        NSDictionary<NSString *, NSString *> *request = self.pendingRequests[index];
        CGFloat y = rowsHeight - (index+1)*rowHeight;
        NSTextField *provider = [NSTextField labelWithString:request[@"providerName"]];
        provider.frame = NSMakeRect(12,y+29,210,16);
        provider.font = [NSFont systemFontOfSize:11]; provider.textColor = NSColor.secondaryLabelColor;
        provider.lineBreakMode = NSLineBreakByTruncatingTail;
        provider.toolTip = request[@"providerName"];
        NSTextField *destination = [NSTextField labelWithString:request[@"destination"]];
        destination.frame = NSMakeRect(12,y+9,210,18);
        destination.font = [NSFont systemFontOfSize:13]; destination.lineBreakMode = NSLineBreakByTruncatingTail;
        destination.toolTip = request[@"destination"];
        NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"Cancel one waiting call.") target:self action:@selector(cancelWaitingCall:)];
        cancel.frame = NSMakeRect(234,y+4,68,44);
        cancel.bezelStyle = NSBezelStyleRounded;
        cancel.identifier = @"PendingCallCancelButton";
        cancel.cell.representedObject = request;
        cancel.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Cancel call to %@ through %@", @"Cancel waiting destination through its selected connection."),request[@"destination"],request[@"providerName"]];
        cancel.cell.accessibilityLabel = cancel.accessibilityLabel;
        cancel.toolTip = heading.stringValue; cancel.accessibilityHelp = cancel.toolTip;
        [rows addSubview:provider]; [rows addSubview:destination]; [rows addSubview:cancel];
        [buttons addObject:cancel];
    }
    content.view.nextKeyView = buttons.firstObject;
    scroll.documentView = rows; [content.view addSubview:scroll];
    self.pendingCancelButtons = buttons;
    self.pendingPopover.contentViewController = content;
    self.pendingPopover.contentSize = NSMakeSize(width,height);
    [self configurePendingKeyLoop];
    // Start with the first listed destination, including when the list scrolls.
    [rows scrollRectToVisible:NSMakeRect(0,MAX(0,rowsHeight-visibleHeight),width,visibleHeight)];
}
- (void)configurePendingKeyLoop {
    NSWindow *window = self.pendingPopover.contentViewController.view.window;
    window.autorecalculatesKeyViewLoop = NO;
    window.initialFirstResponder = self.pendingCancelButtons.firstObject;
    for (NSUInteger index = 0; index < self.pendingCancelButtons.count; index++)
        self.pendingCancelButtons[index].nextKeyView = self.pendingCancelButtons[(index+1)%self.pendingCancelButtons.count];
}
- (void)cancelWaitingCall:(NSButton *)sender {
    NSDictionary<NSString *, NSString *> *request = sender.cell.representedObject;
    for (AccountController *account in self.accounts.all) {
        if ([account.account.uuid isEqualToString:request[@"accountUUID"]]) {
            if ([account cancelPendingRoutedCallWithIdentifier:request[@"id"]]) return;
            break;
        }
    }
    // An old button may outlive registration, expiry or removal of its account.
    [self refreshPendingCalls];
}
- (void)popoverDidClose:(NSNotification *)notification {
    NSView *next = self.dialler.pendingCallsButton.hidden ? self.dialler.callDestinationField : self.dialler.pendingCallsButton;
    [self.window makeFirstResponder:next];
}
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
    // The first history focus target changes between collapsed table and
    // expanded search. Refresh the parent key loop on every transition.
    [self.dialler updateNextKeyView:self.history.keyView];
    [self.dialler updateHistoryExpanded:self.expanded]; [self resizeForHistory:self.expanded];
}
- (NSMenu *)moreActionsMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    for (NSMenuItem *item in self.history.actionsMenu.itemArray) if (item.action == NSSelectorFromString(@"deleteAll:")) [menu addItem:[item copy]];
    for (AccountController *account in self.accounts.all) if (account.hasPendingRoutedCalls) {
        NSMenuItem *cancel = [[NSMenuItem alloc] initWithTitle:@"Cancel pending calls" action:@selector(cancelPendingCalls:) keyEquivalent:@""];
        cancel.target = self; [menu addItem:cancel]; break;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Guided routes…" action:@selector(showGuidedRoutes:) keyEquivalent:@""];
    settings.target = self; [menu addItem:settings];
    return menu;
}
- (void)showActions:(NSView *)sender {
    NSMenu *menu = [self moreActionsMenu];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,NSMaxY(sender.bounds)) inView:sender];
}
- (void)cancelPendingCalls:(id)sender { for (AccountController *account in self.accounts.all) [account cancelPendingRoutedCalls]; }
- (void)showGuidedRoutes:(id)sender {
    // This window handles the same action. A nil target would find it again in
    // the responder chain instead of reaching the application-owned Settings.
    id delegate = NSApp.delegate;
    SEL action = NSSelectorFromString(@"showGuidedRoutes:");
    if ([delegate respondsToSelector:action]) [NSApp sendAction:action to:delegate from:sender];
}
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
