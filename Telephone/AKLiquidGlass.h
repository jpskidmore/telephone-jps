// AppKit presentation helpers. Call and settings actions remain in their controllers.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A semantic, desktop-blending window backdrop beneath the content layer.
/// It also switches the containing window to an opaque background when Reduce
/// Transparency is enabled, without changing any controls or their hierarchy.
@interface AKWindowMaterialView : NSVisualEffectView
/// Keeps the native titlebar's semantic background while the content backdrop
/// remains nonopaque. Settings opts in; call-window composition is unchanged.
@property(nonatomic) BOOL usesOpaqueTitlebarBackground;
@end

/// A system material reserved for controls and navigation, not primary content.
@interface AKGlassControlContainer : NSView
@property(nonatomic, readonly) NSView *contentView;
- (instancetype)initWithFrame:(NSRect)frame sidebar:(BOOL)sidebar;
@end

/// Reuses the nib's bound labels and action buttons in a spacious call layout.
FOUNDATION_EXPORT void AKInstallCallPresentation(NSView *view,
                                                NSTextField *caller,
                                                NSTextField *status,
                                                NSArray<NSButton *> *buttons,
                                                NSTextField * _Nullable recording,
                                                NSProgressIndicator * _Nullable progress);
FOUNDATION_EXPORT void AKStyleCallButton(NSButton *button, NSString *title, NSString *symbol, BOOL destructive);

NS_ASSUME_NONNULL_END
