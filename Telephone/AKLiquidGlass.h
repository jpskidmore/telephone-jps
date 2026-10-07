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

/// Reuses the nib's bound labels and actions in a 300pt compact call card.
FOUNDATION_EXPORT void AKInstallCallPresentation(NSView *view,
                                                NSTextField *caller,
                                                NSTextField *number,
                                                NSTextField *status,
                                                NSArray<NSButton *> *buttons,
                                                NSTextField * _Nullable recording,
                                                NSProgressIndicator * _Nullable progress,
                                                NSTextField * _Nullable duration);
/// Fits up to three status lines without enlarging the ordinary 112pt body.
FOUNDATION_EXPORT void AKUpdateCallPresentation(NSView *view, NSTextField *status);
FOUNDATION_EXPORT void AKStyleCallButton(NSButton *button, NSString *title, NSString *symbol, BOOL destructive);

NS_ASSUME_NONNULL_END
