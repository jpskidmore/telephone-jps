#import "AKLiquidGlass.h"
#import <objc/runtime.h>

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
@property(nonatomic) CGFloat cornerRadius;
@end

@implementation AKOpaqueMaterialView
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.windowBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.cornerRadius yRadius:self.cornerRadius] fill];
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast) {
        [NSColor.separatorColor setStroke];
        NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                                             xRadius:self.cornerRadius yRadius:self.cornerRadius];
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
        // Supply the shared standard window backdrop beneath call content
        // without changing frames, titlebar geometry or the responder chain.
        NSView *root = self.window.contentView;
        BOOL hasBackdrop = [root isKindOfClass:[AKWindowMaterialView class]];
        for (NSView *view in root.subviews) {
            hasBackdrop |= [view isKindOfClass:[AKWindowMaterialView class]];
        }
        if (!hasBackdrop) {
            AKWindowMaterialView *backdrop = [[AKWindowMaterialView alloc] initWithFrame:root.bounds];
            backdrop.usesOpaqueTitlebarBackground = YES;
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
        AKOpaqueMaterialView *opaque = [[AKOpaqueMaterialView alloc] initWithFrame:self.bounds];
        opaque.cornerRadius = self.sidebar ? 0 : 16;
        self.surface = opaque;
        [self.surface addSubview:self.contentView];
    } else {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
        if (@available(macOS 26.0, *)) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:self.bounds];
            glass.style = NSGlassEffectViewStyleRegular;
            glass.cornerRadius = self.sidebar ? 0 : 16;
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
            material.layer.cornerRadius = self.sidebar ? 0 : 16;
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

@implementation AKCallActionButton
- (NSEdgeInsets)alignmentRectInsets {
    // The compact row allocates 44pt to the actual button, including its native
    // bezel. macOS 15's visual alignment margins would otherwise enlarge each
    // frame to 58x56 and make adjacent hit regions overlap.
    return NSEdgeInsetsMake(0, 0, 0, 0);
}
@end

static const void *AKCallStatusHeightKey = &AKCallStatusHeightKey;

void AKStyleCallButton(NSButton *button, NSString *title, NSString *symbol, BOOL destructive) {
    // The label remains available to VoiceOver and tooltips; icon width never
    // depends on a translated action name.
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.bordered = YES;
    button.image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]
                    imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:16
                                                                                                 weight:NSFontWeightMedium]];
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.font = [NSFont systemFontOfSize:13];
    button.contentTintColor = destructive ? NSColor.systemRedColor : nil;
    button.toolTip = title;
    button.accessibilityLabel = title;
}

void AKUpdateCallPresentation(NSView *view, NSTextField *status) {
    NSLayoutConstraint *height = objc_getAssociatedObject(view, AKCallStatusHeightKey);
    if (height == nil) return; // Dedicated transfer sheets retain their layout.
    CGFloat availableWidth = MAX(180, status.bounds.size.width);
    NSRect textBounds = [status.stringValue boundingRectWithSize:NSMakeSize(availableWidth, CGFLOAT_MAX)
                                                       options:NSStringDrawingUsesLineFragmentOrigin
                                                    attributes:@{NSFontAttributeName:status.font}];
    CGFloat statusHeight = MAX(14, MIN(42, ceil(textBounds.size.height)));
    height.constant = statusHeight;
    NSRect frame = view.frame;
    frame.size = NSMakeSize(300, 112 + statusHeight - 14);
    view.frame = frame;
    status.toolTip = status.stringValue;
}

void AKInstallCallPresentation(NSView *view, NSTextField *caller, NSTextField *number, NSTextField *status,
                               NSArray<NSButton *> *buttons, NSTextField *recording,
                               NSProgressIndicator *progress, NSTextField *duration) {
    [NSLayoutConstraint deactivateConstraints:view.constraints];
    for (NSView *control in buttons) [NSLayoutConstraint deactivateConstraints:control.constraints];
    [NSLayoutConstraint deactivateConstraints:status.constraints];
    view.frame = NSMakeRect(0, 0, 300, 112);

    caller.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    caller.textColor = NSColor.labelColor;
    caller.lineBreakMode = NSLineBreakByTruncatingTail;
    caller.selectable = YES;
    caller.accessibilityLabel = NSLocalizedString(@"Caller", @"Call window caller label.");
    number.font = [NSFont systemFontOfSize:11];
    number.textColor = NSColor.secondaryLabelColor;
    number.lineBreakMode = NSLineBreakByTruncatingMiddle;
    number.selectable = YES;
    number.accessibilityLabel = NSLocalizedString(@"Phone number", @"Remote call number accessibility label.");
    number.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:number];
    status.font = [NSFont systemFontOfSize:11];
    status.textColor = NSColor.secondaryLabelColor;
    status.lineBreakMode = NSLineBreakByWordWrapping;
    status.cell.wraps = YES;
    status.cell.scrollable = NO;
    status.maximumNumberOfLines = 3;
    status.selectable = YES;
    status.accessibilityLabel = NSLocalizedString(@"Call status", @"Call status accessibility label.");

    AKGlassControlContainer *bar = [[AKGlassControlContainer alloc] initWithFrame:NSZeroRect sidebar:NO];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.identifier = @"CallActions";
    [view addSubview:bar];
    NSStackView *actions = [NSStackView stackViewWithViews:buttons];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 12;
    actions.detachesHiddenViews = NO;
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.contentView addSubview:actions];
    for (NSButton *button in buttons) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button.widthAnchor constraintEqualToConstant:44].active = YES;
        [button.heightAnchor constraintEqualToConstant:44].active = YES;
    }
    NSLayoutConstraint *statusHeight = [status.heightAnchor constraintEqualToConstant:14];
    objc_setAssociatedObject(view, AKCallStatusHeightKey, statusHeight, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMutableArray<NSLayoutConstraint *> *constraints = [@[
        [caller.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [caller.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:progress ? -40 : -16],
        [caller.topAnchor constraintEqualToAnchor:view.topAnchor constant:8],
        [caller.heightAnchor constraintEqualToConstant:16],
        [number.leadingAnchor constraintEqualToAnchor:caller.leadingAnchor],
        [number.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:recording ? -76 : -16],
        [number.topAnchor constraintEqualToAnchor:caller.bottomAnchor constant:2],
        [number.heightAnchor constraintEqualToConstant:14],
        [status.leadingAnchor constraintEqualToAnchor:caller.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:duration ? -80 : -16],
        [status.topAnchor constraintEqualToAnchor:number.bottomAnchor constant:2],
        statusHeight,
        [bar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [bar.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
        [bar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-8],
        [bar.heightAnchor constraintEqualToConstant:44],
        [actions.centerXAnchor constraintEqualToAnchor:bar.contentView.centerXAnchor],
        [actions.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor]
    ] mutableCopy];
    if (recording != nil) {
        recording.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        recording.textColor = NSColor.systemRedColor;
        recording.accessibilityLabel = NSLocalizedString(@"Recording in progress", @"Call recording accessibility label.");
        [constraints addObjectsFromArray:@[
            [recording.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
            [recording.centerYAnchor constraintEqualToAnchor:number.centerYAnchor],
            [recording.widthAnchor constraintEqualToConstant:52],
            [recording.heightAnchor constraintEqualToConstant:14]
        ]];
    }
    if (progress != nil) {
        [constraints addObjectsFromArray:@[
            [progress.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
            [progress.centerYAnchor constraintEqualToAnchor:caller.centerYAnchor],
            [progress.widthAnchor constraintEqualToConstant:16],
            [progress.heightAnchor constraintEqualToConstant:16]
        ]];
        progress.accessibilityLabel = NSLocalizedString(@"Connecting call", @"Call progress indicator accessibility label.");
    }
    if (duration != nil) {
        duration.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        duration.textColor = NSColor.secondaryLabelColor;
        duration.alignment = NSTextAlignmentRight;
        duration.accessibilityLabel = NSLocalizedString(@"Call duration", @"Call duration accessibility label.");
        duration.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:duration];
        [constraints addObjectsFromArray:@[
            [duration.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
            [duration.topAnchor constraintEqualToAnchor:status.topAnchor],
            [duration.widthAnchor constraintEqualToConstant:60],
            [duration.heightAnchor constraintEqualToConstant:14]
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    [view layoutSubtreeIfNeeded];
    AKUpdateCallPresentation(view, status);
}
