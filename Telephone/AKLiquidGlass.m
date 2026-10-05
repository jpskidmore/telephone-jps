#import "AKLiquidGlass.h"

@implementation AKWindowMaterialView

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        self.state = NSVisualEffectStateFollowsWindowActiveState;
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                          selector:@selector(accessibilityOptionsChanged:)
                                                              name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                            object:nil];
        [self updateWindowComposition];
    }
    return self;
}

- (void)dealloc {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (void)setUsesOpaqueTitlebarBackground:(BOOL)usesOpaqueTitlebarBackground {
    _usesOpaqueTitlebarBackground = usesOpaqueTitlebarBackground;
    [self updateWindowComposition];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateWindowComposition];
}

- (void)accessibilityOptionsChanged:(NSNotification *)notification {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateWindowComposition]; });
        return;
    }
    [self updateWindowComposition];
}

- (void)updateWindowComposition {
    BOOL reduced = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    // Standard material belongs to the app background; Liquid Glass remains
    // confined to the navigation/control layer above it. WindowBackground is
    // explicitly opaque, whereas UnderWindowBackground permits desktop blend.
    self.material = reduced ? NSVisualEffectMaterialWindowBackground : NSVisualEffectMaterialUnderWindowBackground;
    self.window.opaque = reduced;
    // A normal Settings titlebar draws the window background. Preserve its
    // semantic opaque color without making the desktop-blending body opaque.
    self.window.backgroundColor = reduced || self.usesOpaqueTitlebarBackground
                                  ? NSColor.windowBackgroundColor : NSColor.clearColor;
    self.needsDisplay = YES;
    [self.window invalidateShadow];
}

@end

@interface AKOpaqueMaterialView : NSView
@end

@implementation AKOpaqueMaterialView
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.windowBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:16 yRadius:16] fill];
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast) {
        [NSColor.separatorColor setStroke];
        NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                                             xRadius:16 yRadius:16];
        outline.lineWidth = 1;
        [outline stroke];
    }
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

@interface AKGlassControlContainer ()
@property(nonatomic, readwrite) NSView *contentView;
@property(nonatomic) NSView *surface;
@property(nonatomic) BOOL sidebar;
@end

@implementation AKGlassControlContainer

- (instancetype)initWithFrame:(NSRect)frame sidebar:(BOOL)sidebar {
    if ((self = [super initWithFrame:frame])) {
        _sidebar = sidebar;
        _contentView = [[NSView alloc] initWithFrame:self.bounds];
        _contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.accessibilityElement = NO;
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                          selector:@selector(accessibilityOptionsChanged:)
                                                              name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                            object:nil];
        [self rebuildSurface];
    }
    return self;
}

- (void)dealloc {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (void)accessibilityOptionsChanged:(NSNotification *)notification {
    // Workspace notifications may arrive off the main thread.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self rebuildSurface]; });
        return;
    }
    [self rebuildSurface];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.sidebar && self.window != nil) {
        // Call controllers keep their existing content view and account footer.
        // Supply the same standard window backdrop beneath all of those views
        // without changing their frames, titlebar geometry or responder chain.
        NSView *root = self.window.contentView;
        BOOL hasBackdrop = [root isKindOfClass:[AKWindowMaterialView class]];
        for (NSView *view in root.subviews) {
            hasBackdrop |= [view isKindOfClass:[AKWindowMaterialView class]];
        }
        if (!hasBackdrop) {
            AKWindowMaterialView *backdrop = [[AKWindowMaterialView alloc] initWithFrame:root.bounds];
            backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [root addSubview:backdrop positioned:NSWindowBelow relativeTo:nil];
        }
    }
}

- (void)rebuildSurface {
    NSWindow *window = self.window;
    NSResponder *responder = window.firstResponder;
    NSView *focusedView = [responder isKindOfClass:[NSView class]] ? (NSView *)responder : nil;
    NSTextView *editor = [responder isKindOfClass:[NSTextView class]] && [(NSTextView *)responder isFieldEditor]
                        ? (NSTextView *)responder : nil;
    if (editor != nil && [editor.delegate isKindOfClass:[NSView class]]) {
        focusedView = (NSView *)editor.delegate;
    }
    BOOL restoreFocus = focusedView != nil && [focusedView isDescendantOf:self.contentView];
    NSRange selection = editor.selectedRange;

    // Keep controls (and any field editor) alive while switching material.
    [self.contentView removeFromSuperview];
    [self.surface removeFromSuperview];
    self.surface = nil;

    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency) {
        self.surface = [[AKOpaqueMaterialView alloc] initWithFrame:self.bounds];
        [self.surface addSubview:self.contentView];
    } else {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
        if (@available(macOS 26.0, *)) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:self.bounds];
            glass.style = NSGlassEffectViewStyleRegular;
            glass.cornerRadius = 16;
            // AppKit only guarantees proper glass composition through contentView.
            glass.contentView = self.contentView;
            self.surface = glass;
        } else
#endif
        {
            NSVisualEffectView *material = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
            material.material = self.sidebar ? NSVisualEffectMaterialSidebar : NSVisualEffectMaterialPopover;
            material.blendingMode = NSVisualEffectBlendingModeWithinWindow;
            material.state = NSVisualEffectStateFollowsWindowActiveState;
            material.wantsLayer = YES;
            material.layer.cornerRadius = 16;
            material.layer.masksToBounds = YES;
            [material addSubview:self.contentView];
            self.surface = material;
        }
    }
    self.surface.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.surface.accessibilityElement = NO;
    self.contentView.frame = self.surface.bounds;
    [self addSubview:self.surface];
    if (restoreFocus && focusedView.window == window && [window makeFirstResponder:focusedView]) {
        if (editor != nil && [window.firstResponder isKindOfClass:[NSTextView class]]) {
            NSTextView *restoredEditor = (NSTextView *)window.firstResponder;
            NSUInteger length = restoredEditor.string.length;
            selection.location = MIN(selection.location, length);
            selection.length = MIN(selection.length, length - selection.location);
            restoredEditor.selectedRange = selection;
        }
    }
}

@end

void AKStyleCallButton(NSButton *button, NSString *title, NSString *symbol, BOOL destructive) {
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.bordered = YES;
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    button.imagePosition = NSImageLeft;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    button.contentTintColor = destructive ? NSColor.systemRedColor : nil;
    button.toolTip = title;
    button.accessibilityLabel = title;
}

void AKInstallCallPresentation(NSView *view, NSTextField *caller, NSTextField *status,
                               NSArray<NSButton *> *buttons, NSTextField *recording,
                               NSProgressIndicator *progress) {
    [NSLayoutConstraint deactivateConstraints:view.constraints];
    for (NSView *control in buttons) {
        [NSLayoutConstraint deactivateConstraints:control.constraints];
    }
    [NSLayoutConstraint deactivateConstraints:status.constraints];
    CGFloat widestButton = 0;
    for (NSButton *button in buttons) {
        widestButton = MAX(widestButton, button.fittingSize.width + 8);
    }
    // Two columns keep long translated labels readable without creating a
    // disproportionately wide call window. Secondary controls occupy row one.
    BOOL twoRows = buttons.count > 2;
    NSUInteger columns = twoRows ? 2 : MAX(buttons.count, 1);
    CGFloat width = MAX(480, 72 + 12 * (columns - 1) + widestButton * columns);
    view.frame = NSMakeRect(0, 0, width, twoRows ? 244 : 200);

    caller.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
    caller.textColor = NSColor.labelColor;
    caller.lineBreakMode = NSLineBreakByTruncatingTail;
    caller.selectable = YES;
    caller.accessibilityLabel = NSLocalizedString(@"Caller", @"Call window caller label.");
    status.font = [NSFont systemFontOfSize:13];
    status.textColor = NSColor.secondaryLabelColor;
    status.lineBreakMode = NSLineBreakByWordWrapping;
    status.cell.wraps = YES;
    status.cell.scrollable = NO;
    status.maximumNumberOfLines = 2;
    status.selectable = YES;
    status.accessibilityLabel = NSLocalizedString(@"Call status", @"Call status accessibility label.");

    AKGlassControlContainer *bar = [[AKGlassControlContainer alloc] initWithFrame:NSZeroRect sidebar:NO];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:bar];
    NSStackView *actions;
    if (twoRows) {
        NSStackView *firstRow = [NSStackView stackViewWithViews:[buttons subarrayWithRange:NSMakeRange(0, 2)]];
        NSStackView *secondRow = [NSStackView stackViewWithViews:[buttons subarrayWithRange:NSMakeRange(2, buttons.count - 2)]];
        for (NSStackView *row in @[firstRow, secondRow]) {
            row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            row.distribution = NSStackViewDistributionFillEqually;
            row.spacing = 12;
        }
        actions = [NSStackView stackViewWithViews:@[firstRow, secondRow]];
        actions.orientation = NSUserInterfaceLayoutOrientationVertical;
        actions.spacing = 12;
        [firstRow.widthAnchor constraintEqualToAnchor:actions.widthAnchor].active = YES;
        [secondRow.widthAnchor constraintEqualToAnchor:actions.widthAnchor].active = YES;
    } else {
        actions = [NSStackView stackViewWithViews:buttons];
        actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        actions.distribution = NSStackViewDistributionFillEqually;
        actions.spacing = 12;
    }
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.contentView addSubview:actions];
    for (NSButton *button in buttons) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button.heightAnchor constraintEqualToConstant:32].active = YES;
    }

    NSMutableArray<NSLayoutConstraint *> *constraints = [@[
        [caller.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24],
        [caller.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24],
        [caller.topAnchor constraintEqualToAnchor:view.topAnchor constant:24],
        [status.leadingAnchor constraintEqualToAnchor:caller.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:caller.trailingAnchor],
        [status.topAnchor constraintEqualToAnchor:caller.bottomAnchor constant:8],
        [status.heightAnchor constraintEqualToConstant:36],
        [bar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24],
        [bar.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24],
        [bar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-20],
        [bar.heightAnchor constraintEqualToConstant:twoRows ? 100 : 56],
        [actions.leadingAnchor constraintEqualToAnchor:bar.contentView.leadingAnchor constant:12],
        [actions.trailingAnchor constraintEqualToAnchor:bar.contentView.trailingAnchor constant:-12],
        [actions.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor]
    ] mutableCopy];
    if (recording != nil) {
        recording.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        recording.textColor = NSColor.systemRedColor;
        recording.accessibilityLabel = NSLocalizedString(@"Recording in progress", @"Call recording accessibility label.");
        [constraints addObjectsFromArray:@[
            [recording.leadingAnchor constraintEqualToAnchor:caller.leadingAnchor],
            [recording.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:6]
        ]];
    }
    if (progress != nil) {
        [constraints addObjectsFromArray:@[
            [progress.trailingAnchor constraintEqualToAnchor:caller.trailingAnchor],
            [progress.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:6],
            [progress.widthAnchor constraintEqualToConstant:16],
            [progress.heightAnchor constraintEqualToConstant:16]
        ]];
        progress.accessibilityLabel = NSLocalizedString(@"Connecting call", @"Call progress indicator accessibility label.");
    }
    [NSLayoutConstraint activateConstraints:constraints];
}
