#import <Cocoa/Cocoa.h>
#import "AKRecordingRecoveryIndex.h"

NS_ASSUME_NONNULL_BEGIN

// These boundaries are injectable so isolated tests never open real panels,
// reveal user files, or invoke the recorder. All completions may arrive late.
typedef void (^AKRecoverySavePanel)(NSWindow *window, NSDictionary *job, void (^completion)(NSURL * _Nullable destination));
typedef void (^AKRecoveryDiscardConfirmation)(NSWindow *window, NSDictionary *job, void (^completion)(BOOL confirmed));
typedef void (^AKRecoveryRetry)(NSDictionary *job, NSURL *destination, void (^completion)(BOOL succeeded));
typedef void (^AKRecoveryDiscard)(NSDictionary *job, void (^completion)(BOOL succeeded, NSError * _Nullable error));
typedef void (^AKRecoveryReveal)(NSURL *directory);

@interface RecordingRecoveryController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property(nonatomic, readonly) AKRecordingRecoveryIndex *index;
// Includes cached placeholders for owned or not-yet-rechecked operations, so a
// closed progress window remains reachable without discovery or UI creation.
@property(nonatomic, readonly) NSUInteger managedJobCount;
@property(nonatomic, copy, nullable) dispatch_block_t stateDidChange;
// Closing admission never cancels an already submitted export/discard.
@property(nonatomic) BOOL actionsEnabled;
@property(nonatomic, copy) AKRecoverySavePanel savePanelHandler;
@property(nonatomic, copy) AKRecoveryDiscardConfirmation discardConfirmationHandler;
@property(nonatomic, copy) AKRecoveryRetry retryHandler;
@property(nonatomic, copy) AKRecoveryDiscard discardHandler;
@property(nonatomic, copy) AKRecoveryReveal revealHandler;
- (instancetype)initWithLoader:(AKRecordingRecoveryLoader)loader;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
// Lazy, modeless secondary window; no file work until its first refresh.
- (void)showRecovery;
- (void)refreshPresentation;
- (IBAction)refresh:(nullable id)sender;
- (IBAction)retrySelected:(nullable id)sender;
- (IBAction)saveSelectedElsewhere:(nullable id)sender;
- (IBAction)revealSelected:(nullable id)sender;
- (IBAction)discardSelected:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
