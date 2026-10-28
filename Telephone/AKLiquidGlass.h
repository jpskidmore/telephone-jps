// AppKit presentation helpers. Call and settings actions remain in their controllers.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A semantic, desktop-blending window backdrop beneath the content layer.
/// It also switches the containing window to an opaque background when Reduce
/// Transparency is enabled, without changing any controls or their hierarchy.
@interface AKWindowMaterialView : NSVisualEffectView
/// Keeps the native titlebar's semantic background while the content backdrop
/// remains nonopaque. Settings and call windows opt in for native titlebar contrast.
@property(nonatomic) BOOL usesOpaqueTitlebarBackground;
@end

/// A system material reserved for controls and navigation, not primary content.
@interface AKGlassControlContainer : NSView
@property(nonatomic, readonly) NSView *contentView;
- (instancetype)initWithFrame:(NSRect)frame sidebar:(BOOL)sidebar;
@end

/// Native call buttons whose layout rectangle matches their actual hit frame.
/// Older AppKit rounded buttons otherwise add legacy bezel alignment margins.
@interface AKCallActionButton : NSButton
@end

/// Reuses the nib's bound labels/actions in the shared compact dialler footprint.
FOUNDATION_EXPORT void AKInstallCallPresentation(NSView *view,
                                                NSTextField *caller,
                                                NSTextField *number,
                                                NSTextField *status,
                                                NSArray<NSButton *> *buttons,
                                                NSTextField * _Nullable recording,
                                                NSProgressIndicator * _Nullable progress,
                                                NSTextField * _Nullable duration);
/// Keeps a fixed body; full status remains available in its native tooltip/AX value.
FOUNDATION_EXPORT void AKUpdateCallPresentation(NSView *view, NSTextField *status);
FOUNDATION_EXPORT void AKStyleCallButton(NSButton *button, NSString *title, NSString *symbol, BOOL destructive);

NS_ASSUME_NONNULL_END
