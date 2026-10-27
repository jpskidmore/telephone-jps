#import "AKRecordingCatalogue.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <time.h>
#include <unistd.h>

NSString *const AKRecordingCatalogueErrorDomain = @"uk.jpsit.telephone.recording-catalogue";
static const NSUInteger CatalogueVersion = 1;
static const NSUInteger CatalogueMaximumBytes = 16 * 1024 * 1024;

static NSError *CatalogueError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:AKRecordingCatalogueErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}
static void CataloguePOSIXError(NSError **error, int code) {
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}
// Cooperating application processes hold one persistent sibling lock across the
// complete read/merge/atomic-write transaction. Never unlink a lock: another
// waiting process may already hold its descriptor. Injected stores omit this IO.
static BOOL CatalogueLockIsCurrent(NSURL *parent, int directory, NSString *name, int descriptor) {
    struct stat heldDirectory, currentDirectory, heldLock, currentLock;
    return fstat(directory, &heldDirectory) == 0 &&
        stat(parent.fileSystemRepresentation, &currentDirectory) == 0 &&
        heldDirectory.st_dev == currentDirectory.st_dev && heldDirectory.st_ino == currentDirectory.st_ino &&
        fstat(descriptor, &heldLock) == 0 && S_ISREG(heldLock.st_mode) &&
        (heldLock.st_mode & 0777) == 0600 && heldLock.st_uid == geteuid() && heldLock.st_nlink == 1 &&
        fstatat(directory, name.fileSystemRepresentation, &currentLock, AT_SYMLINK_NOFOLLOW) == 0 &&
        S_ISREG(currentLock.st_mode) && heldLock.st_dev == currentLock.st_dev && heldLock.st_ino == currentLock.st_ino;
}
static int LockCatalogueTransaction(NSURL *url, int *directoryOut, NSError **error) {
    NSURL *parent = url.URLByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:error]) return -1;
    int directory = open(parent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directory < 0) { CataloguePOSIXError(error, errno); return -1; }
    NSString *name = [url.lastPathComponent stringByAppendingString:@".lock"];
    int descriptor = -1; int openError = ENOENT;
    for (NSUInteger attempt = 0; attempt < 20; attempt++) {
        descriptor = openat(directory, name.fileSystemRepresentation, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
        if (descriptor >= 0) break;
        openError = errno;
        if (openError != ENOENT) break;
        descriptor = openat(directory, name.fileSystemRepresentation, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (descriptor >= 0) break;
        openError = errno;
        // Another process may be publishing this persistent lock for the first
        // time. Reopen it; never replace or unlink its inode.
        if (openError != EEXIST && openError != ENOENT) break;
        struct timespec delay = {0, 1000 * 1000}; nanosleep(&delay, NULL);
    }
    if (descriptor < 0) { close(directory); CataloguePOSIXError(error, openError); return -1; }
    if (!CatalogueLockIsCurrent(parent, directory, name, descriptor)) {
        close(descriptor); close(directory); CataloguePOSIXError(error, ESTALE); return -1;
    }
    // A stale/hung peer must not hold the recording finalisation drain forever.
    BOOL locked = NO; int code = ETIMEDOUT;
    for (NSUInteger attempt = 0; attempt < 100; attempt++) {
        if (flock(descriptor, LOCK_EX | LOCK_NB) == 0) { locked = YES; break; }
        if (errno == EINTR) continue;
        if (errno != EWOULDBLOCK && errno != EAGAIN) { code = errno; break; }
        struct timespec delay = {0, 20 * 1000 * 1000}; nanosleep(&delay, NULL);
    }
    if (!locked || !CatalogueLockIsCurrent(parent, directory, name, descriptor)) {
        if (locked) { flock(descriptor, LOCK_UN); code = ESTALE; }
        close(descriptor); close(directory); CataloguePOSIXError(error, code); return -1;
    }
    *directoryOut = directory; return descriptor;
}
static dispatch_queue_t CatalogueQueueForURL(NSURL *url) {
    static NSMutableDictionary<NSString *, id> *queues; static dispatch_once_t once;
    dispatch_once(&once, ^{ queues = [NSMutableDictionary dictionary]; });
    @synchronized (queues) {
        NSString *key = url.standardizedURL.path;
        dispatch_queue_t queue = queues[key];
        if (queue == nil) {
            queue = dispatch_queue_create("com.tlphn.Telephone.recording-catalogue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
            queues[key] = queue;
        }
        return queue;
    }
}
static BOOL NonemptyString(id value) { return [value isKindOfClass:NSString.class] && [value length] > 0; }
static NSString *AttachmentKey(NSDictionary *attachment) {
    NSString *call = attachment[@"callIdentifier"], *segment = attachment[@"segmentIdentifier"];
    return [NSString stringWithFormat:@"%lu:%@%@", (unsigned long)call.length, call, segment];
}
static id FreezePropertyList(id value) {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[value count]];
        for (NSString *key in value) result[[key copy]] = FreezePropertyList(value[key]);
        return [result copy];
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[value count]];
        for (id element in value) [result addObject:FreezePropertyList(element)];
        return [result copy];
    }
    return [value copy];
}
static NSDictionary *ImmutableAttachment(id value, NSError **error) {
    if (![value isKindOfClass:NSDictionary.class] ||
        !NonemptyString(value[@"callIdentifier"]) || !NonemptyString(value[@"segmentIdentifier"]) ||
        [value[@"callIdentifier"] length] > 1024 || [value[@"segmentIdentifier"] length] > 1024 ||
        ![@[@"capturing", @"finalising", @"failed", @"available"] containsObject:value[@"state"] ?: @""]) {
        if (error) *error = CatalogueError(1, @"The recording attachment identity or state is invalid.");
        return nil;
    }
    if ([value[@"state"] isEqual:@"available"] &&
        (![value[@"outputBookmark"] isKindOfClass:NSData.class] || [value[@"outputBookmark"] length] == 0 ||
         ![value[@"outputIdentity"] isKindOfClass:NSDictionary.class] || [value[@"outputIdentity"] count] == 0 ||
         !NonemptyString(value[@"destination"]))) {
        if (error) *error = CatalogueError(2, @"The available recording has no verified output reference.");
        return nil;
    }
    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0
                                                           options:0 error:&serializationError];
    if (data == nil) {
        if (error) *error = serializationError ?: CatalogueError(3, @"Recording metadata could not be saved.");
        return nil;
    }
    id parsed = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    return parsed ? FreezePropertyList(parsed) : nil;
}
static NSData *ReadCatalogue(NSURL *url, NSError **error) {
    int descriptor = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) { if (errno != ENOENT) CataloguePOSIXError(error, errno); return nil; }
    struct stat info;
    if (fstat(descriptor, &info) != 0) { int code = errno; close(descriptor); CataloguePOSIXError(error, code); return nil; }
    if (!S_ISREG(info.st_mode) || info.st_size < 0 || (unsigned long long)info.st_size > CatalogueMaximumBytes) {
        close(descriptor); if (error) *error = CatalogueError(4, @"The recording catalogue is not a supported regular file."); return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t count = read(descriptor, (char *)data.mutableBytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { int code = count < 0 ? errno : EIO; close(descriptor); CataloguePOSIXError(error, code); return nil; }
        offset += (NSUInteger)count;
    }
    // An append/truncate during the read is not a valid complete snapshot.
    struct stat after;
    if (fstat(descriptor, &after) != 0 || after.st_size != info.st_size ||
        after.st_mtimespec.tv_sec != info.st_mtimespec.tv_sec || after.st_mtimespec.tv_nsec != info.st_mtimespec.tv_nsec) {
        close(descriptor); CataloguePOSIXError(error, EAGAIN); return nil;
    }
    close(descriptor); return data;
}
static BOOL WriteCatalogue(NSURL *url, NSData *data, NSError **error) {
    if (data.length > CatalogueMaximumBytes) { if (error) *error = CatalogueError(5, @"The recording catalogue is too large."); return NO; }
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *parent = url.URLByDeletingLastPathComponent;
    if (![manager createDirectoryAtURL:parent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    int directory = open(parent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directory < 0) { CataloguePOSIXError(error, errno); return NO; }
    struct stat existing;
    if (fstatat(directory, url.lastPathComponent.fileSystemRepresentation, &existing, AT_SYMLINK_NOFOLLOW) == 0 && !S_ISREG(existing.st_mode)) {
        close(directory); CataloguePOSIXError(error, EINVAL); return NO;
    }
    NSString *temporary = [@".catalogue-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int descriptor = openat(directory, temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (descriptor < 0) { int code = errno; close(directory); CataloguePOSIXError(error, code); return NO; }
    BOOL success = YES; int code = 0; NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t count = write(descriptor, (const char *)data.bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { success = NO; code = count < 0 ? errno : EIO; break; }
        offset += (NSUInteger)count;
    }
    if (success && fsync(descriptor) != 0) { success = NO; code = errno; }
    if (close(descriptor) != 0 && success) { success = NO; code = errno; }
    if (success && renameat(directory, temporary.fileSystemRepresentation, directory, url.lastPathComponent.fileSystemRepresentation) != 0) { success = NO; code = errno; }
    if (success && fsync(directory) != 0) { success = NO; code = errno; }
    if (!success) unlinkat(directory, temporary.fileSystemRepresentation, 0);
    close(directory);
    if (!success) CataloguePOSIXError(error, code);
    return success;
}

@interface AKRecordingCatalogue ()
@property(atomic, readwrite, copy) NSArray<NSDictionary *> *attachments;
@property(atomic, readwrite) NSError *error;
@property(atomic, readwrite) BOOL hasLoaded;
@property(atomic, readwrite, getter=isRefreshing) BOOL refreshing;
@property(atomic, readwrite) NSUInteger pendingMutationCount;
@end

@implementation AKRecordingCatalogue {
    NSURL *_storeURL;
    AKRecordingCatalogueReader _reader;
    AKRecordingCatalogueWriter _writer;
    dispatch_queue_t _queue;
    NSMutableDictionary<NSString *, NSDictionary *> *_pending;
    NSMutableArray<NSString *> *_pendingOrder;
    NSArray<NSDictionary *> *_durableAttachments;
    NSUInteger _revision;
    NSUInteger _publishedRevision;
    NSUInteger _refreshGeneration;
    BOOL _hasSuccessfulRead;
    BOOL _requiresTransactionLock;
    NSError *_pendingPersistenceError;
}
+ (instancetype)sharedCatalogue {
    static AKRecordingCatalogue *catalogue; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier ?: @"com.tlphn.Telephone";
        NSURL *directory = [support URLByAppendingPathComponent:identifier isDirectory:YES];
        catalogue = [[self alloc] initWithStoreURL:[directory URLByAppendingPathComponent:@"Recording Catalogue.plist"]];
    });
    return catalogue;
}
- (instancetype)initWithStoreURL:(NSURL *)storeURL {
    self = [self initWithStoreURL:storeURL reader:^NSData *(NSURL *url, NSError **error) { return ReadCatalogue(url, error); }
                          writer:^BOOL(NSURL *url, NSData *data, NSError **error) { return WriteCatalogue(url, data, error); }];
    if (self) _requiresTransactionLock = YES;
    return self;
}
- (instancetype)initWithStoreURL:(NSURL *)storeURL reader:(AKRecordingCatalogueReader)reader writer:(AKRecordingCatalogueWriter)writer {
    NSParameterAssert(storeURL.isFileURL && storeURL.path.isAbsolutePath && storeURL.lastPathComponent.length > 0);
    NSParameterAssert(reader != nil && writer != nil);
    if ((self = [super init])) {
        _storeURL = [storeURL copy]; _reader = [reader copy]; _writer = [writer copy];
        _queue = CatalogueQueueForURL(storeURL);
        dispatch_queue_set_specific(_queue, (__bridge const void *)self, (__bridge void *)self, NULL);
        _pending = [NSMutableDictionary dictionary]; _pendingOrder = [NSMutableArray array];
        _durableAttachments = @[]; _attachments = @[];
    }
    return self;
}
- (NSArray<NSDictionary *> *)readAttachmentsWithError:(NSError **)error {
    NSError *readError = nil; NSData *data = _reader(_storeURL, &readError);
    if (readError) { if (error) *error = readError; return nil; }
    if (data == nil) return @[];
    NSError *parseError = nil;
    id root = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&parseError];
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"version"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)root[@"version"]) == CFBooleanGetTypeID() ||
        ![root[@"version"] isEqual:@(CatalogueVersion)] || ![root[@"attachments"] isKindOfClass:NSArray.class]) {
        if (error) *error = parseError ?: CatalogueError(6, @"The recording catalogue format is unsupported or damaged. Existing metadata has been kept.");
        return nil;
    }
    NSMutableArray *result = [NSMutableArray array]; NSMutableSet *keys = [NSMutableSet set];
    for (id candidate in root[@"attachments"]) {
        NSDictionary *attachment = ImmutableAttachment(candidate, error);
        if (attachment == nil) return nil;
        NSString *key = AttachmentKey(attachment);
        if ([keys containsObject:key]) { if (error) *error = CatalogueError(7, @"The recording catalogue contains duplicate attachment identities."); return nil; }
        [keys addObject:key]; [result addObject:attachment];
    }
    return [result copy];
}
- (void)publishError:(NSError *)error {
    NSUInteger revision = ++_revision;
    NSArray *snapshot = [_durableAttachments copy]; NSUInteger pending = _pending.count; BOOL loaded = _hasSuccessfulRead;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (revision < self->_publishedRevision) return;
        self->_publishedRevision = revision; self.attachments = snapshot; self.error = error;
        self.hasLoaded = loaded; self.pendingMutationCount = pending;
        if (self.stateDidChange) self.stateDidChange();
    });
}
- (BOOL)flushWithError:(NSError **)error {
    if (!_requiresTransactionLock) return [self flushLockedWithError:error];
    int directory = -1; NSError *lockError = nil;
    int descriptor = LockCatalogueTransaction(_storeURL, &directory, &lockError);
    if (descriptor < 0) {
        if (_pending.count > 0) _pendingPersistenceError = lockError;
        if (error) *error = lockError; [self publishError:lockError]; return NO;
    }
    @try { return [self flushLockedWithError:error]; }
    @finally { flock(descriptor, LOCK_UN); close(descriptor); close(directory); }
}
- (BOOL)flushLockedWithError:(NSError **)error {
    NSError *operationError = nil;
    // Reread before each transaction: an unreadable/damaged store is never
    // replaced using an earlier empty or cached snapshot.
    NSArray *existing = [self readAttachmentsWithError:&operationError];
    if (existing == nil) {
        if (_pending.count > 0) _pendingPersistenceError = operationError;
        if (error) *error = operationError; [self publishError:operationError]; return NO;
    }
    _hasSuccessfulRead = YES; _durableAttachments = existing;
    if (_pending.count == 0) { _pendingPersistenceError = nil; [self publishError:nil]; return YES; }
    NSMutableArray<NSDictionary *> *updated = [existing mutableCopy];
    for (NSString *key in _pendingOrder) {
        NSDictionary *mutation = _pending[key]; BOOL found = NO;
        for (NSUInteger index = 0; index < updated.count; index++) {
            if ([AttachmentKey(updated[index]) isEqual:key]) { updated[index] = mutation; found = YES; break; }
        }
        if (!found) [updated addObject:mutation];
    }
    NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:@{@"version":@(CatalogueVersion), @"attachments":updated}
                                                                format:NSPropertyListBinaryFormat_v1_0 options:0 error:&operationError];
    BOOL success = encoded != nil && _writer(_storeURL, encoded, &operationError);
    if (!success) {
        operationError = operationError ?: CatalogueError(8, @"The recording catalogue could not be saved. The original recording has been kept.");
        _pendingPersistenceError = operationError;
        if (error) *error = operationError; [self publishError:operationError]; return NO;
    }
    _pendingPersistenceError = nil;
    _durableAttachments = [updated copy]; [_pending removeAllObjects]; [_pendingOrder removeAllObjects];
    [self publishError:nil]; return YES;
}
- (BOOL)persistAttachment:(NSDictionary *)attachment error:(NSError **)error {
    NSError *validationError = nil; NSDictionary *immutable = ImmutableAttachment(attachment, &validationError);
    if (immutable == nil) { if (error) *error = validationError; return NO; }
    __block BOOL success = NO; __block NSError *operationError = nil;
    dispatch_block_t mutation = ^{
        NSString *key = AttachmentKey(immutable);
        if (self->_pending[key] == nil) [self->_pendingOrder addObject:key];
        self->_pending[key] = immutable; success = [self flushWithError:&operationError];
    };
    if (dispatch_get_specific((__bridge const void *)self)) mutation(); else dispatch_sync(_queue, mutation);
    if (!success && error) *error = operationError; return success;
}
- (BOOL)retryPendingMutationsWithError:(NSError **)error {
    __block BOOL success = NO; __block NSError *operationError = nil;
    dispatch_block_t retry = ^{ success = [self flushWithError:&operationError]; };
    if (dispatch_get_specific((__bridge const void *)self)) retry(); else dispatch_sync(_queue, retry);
    if (!success && error) *error = operationError; return success;
}
- (void)refreshWithCompletion:(void (^)(BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Recording catalogue presentation belongs on main");
    NSUInteger generation = ++_refreshGeneration;
    self.refreshing = YES; if (self.stateDidChange) self.stateDidChange();
    dispatch_async(_queue, ^{
        NSError *error = nil; NSArray *loaded = [self readAttachmentsWithError:&error];
        if (loaded) { self->_durableAttachments = loaded; self->_hasSuccessfulRead = YES; }
        [self publishError:error ?: (self->_pending.count > 0 ? self->_pendingPersistenceError : nil)];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == self->_refreshGeneration) { self.refreshing = NO; if (self.stateDidChange) self.stateDidChange(); }
            if (completion) completion(loaded != nil);
        });
    });
}
- (NSArray<NSDictionary *> *)attachmentsForCallIdentifier:(NSString *)callIdentifier {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *attachment in self.attachments) if ([attachment[@"callIdentifier"] isEqual:callIdentifier]) [result addObject:attachment];
    return [result copy];
}
- (NSDictionary *)attachmentForCallIdentifier:(NSString *)callIdentifier segmentIdentifier:(NSString *)segmentIdentifier {
    for (NSDictionary *attachment in self.attachments) {
        if ([attachment[@"callIdentifier"] isEqual:callIdentifier] && [attachment[@"segmentIdentifier"] isEqual:segmentIdentifier]) return attachment;
    }
    return nil;
}
@end
