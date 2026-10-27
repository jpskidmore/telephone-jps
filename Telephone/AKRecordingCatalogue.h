#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const AKRecordingCatalogueErrorDomain;
// Missing storage is represented by nil data with no error. All seams run on the
// catalogue's serial utility queue. Writers return YES only after durable storage.
typedef NSData * _Nullable (^AKRecordingCatalogueReader)(NSURL *storeURL, NSError **error);
typedef BOOL (^AKRecordingCatalogueWriter)(NSURL *storeURL, NSData *data, NSError **error);

// Metadata only: this object never reads audio, resolves bookmarks, modifies
// history, launches playback, or deletes an export/recovery directory.
@interface AKRecordingCatalogue : NSObject
@property(atomic, readonly, copy) NSArray<NSDictionary *> *attachments;
@property(atomic, readonly, nullable) NSError *error;
@property(atomic, readonly) BOOL hasLoaded;
@property(atomic, readonly, getter=isRefreshing) BOOL refreshing;
@property(atomic, readonly) NSUInteger pendingMutationCount;
@property(nonatomic, copy, nullable) dispatch_block_t stateDidChange;
// Construction does no IO; initial reads are explicit and asynchronous. Default
// disk storage serialises cooperating processes with a persistent sibling lock;
// lock admission times out after about two seconds rather than hanging a drain.
+ (instancetype)sharedCatalogue;
- (instancetype)initWithStoreURL:(NSURL *)storeURL;
- (instancetype)initWithStoreURL:(NSURL *)storeURL
                         reader:(AKRecordingCatalogueReader)reader
                         writer:(AKRecordingCatalogueWriter)writer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// Invoke off main, inside the recording finalisation drain. Returns YES only if
// all queued metadata, including this exact call+segment mutation, is durable.
// Failure retains queued mutations and never replaces a failed/unreadable store.
// Available requires outputBookmark data, outputIdentity dictionary and a display
// destination; the caller must first verify exact output proof under its grant.
- (BOOL)persistAttachment:(NSDictionary *)attachment error:(NSError **)error;
- (BOOL)retryPendingMutationsWithError:(NSError **)error;
// Main-owned immutable presentation. Completion and stateDidChange run on main;
// reads/errors preserve the last successfully loaded durable snapshot.
- (void)refreshWithCompletion:(void (^ _Nullable)(BOOL loaded))completion;
- (NSArray<NSDictionary *> *)attachmentsForCallIdentifier:(NSString *)callIdentifier NS_SWIFT_NAME(attachments(forCallIdentifier:));
- (nullable NSDictionary *)attachmentForCallIdentifier:(NSString *)callIdentifier
                                   segmentIdentifier:(NSString *)segmentIdentifier NS_SWIFT_NAME(attachment(forCallIdentifier:segmentIdentifier:));
@end
NS_ASSUME_NONNULL_END
