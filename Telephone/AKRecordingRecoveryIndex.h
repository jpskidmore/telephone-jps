#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// A loader performs file work on a utility queue; it must not touch AppKit.
typedef NSArray<NSDictionary *> * _Nullable (^AKRecordingRecoveryLoader)(NSError **error);

// Main-owned presentation cache. Menu validation reads these values without IO.
@interface AKRecordingRecoveryIndex : NSObject
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *jobs;
@property(nonatomic, readonly, nullable) NSError *error;
@property(nonatomic, readonly, getter=isRefreshing) BOOL refreshing;
@property(nonatomic, readonly) BOOL hasLoaded;
@property(nonatomic, readonly) NSUInteger generation;
@property(nonatomic, copy, nullable) NSString *selectedIdentity;
@property(nonatomic, readonly, nullable) NSDictionary *selectedJob;
@property(nonatomic, copy, nullable) dispatch_block_t stateDidChange;
- (instancetype)initWithLoader:(AKRecordingRecoveryLoader)loader NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// Every completion is delivered on main. NO means obsolete or invalidated;
// current failed scans publish their error and preserve the previous jobs.
- (void)refreshWithCompletion:(void (^ _Nullable)(BOOL published))completion;
// Terminal shutdown: retires publications without cancelling native/file work.
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
