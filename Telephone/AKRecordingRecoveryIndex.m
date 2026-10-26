#import "AKRecordingRecoveryIndex.h"

@interface AKRecordingRecoveryIndex ()
@property(nonatomic, readwrite, copy) NSArray<NSDictionary *> *jobs;
@property(nonatomic, readwrite) NSError *error;
@property(nonatomic, readwrite, getter=isRefreshing) BOOL refreshing;
@property(nonatomic, readwrite) BOOL hasLoaded;
@property(nonatomic, readwrite) NSUInteger generation;
@property(nonatomic, copy) AKRecordingRecoveryLoader loader;
@property(nonatomic) BOOL invalidated;
@end

@implementation AKRecordingRecoveryIndex
- (instancetype)initWithLoader:(AKRecordingRecoveryLoader)loader {
    NSParameterAssert(loader != nil);
    if ((self = [super init])) { _loader = [loader copy]; _jobs = @[]; }
    return self;
}
- (NSDictionary *)selectedJob {
    if (self.selectedIdentity == nil) return nil;
    for (NSDictionary *job in self.jobs) {
        if ([job[@"directoryIdentity"] isEqual:self.selectedIdentity]) return job;
    }
    return nil;
}
- (void)refreshWithCompletion:(void (^)(BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Recovery presentation admission belongs on main");
    if (self.invalidated) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); }); return; }
    NSUInteger generation = ++self.generation;
    self.refreshing = YES;
    if (self.stateDidChange) self.stateDidChange();
    AKRecordingRecoveryLoader loader = self.loader;
    __weak AKRecordingRecoveryIndex *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSArray<NSDictionary *> *loaded = loader(&error);
        NSArray *snapshot = loaded ? [[NSArray alloc] initWithArray:loaded copyItems:YES] : nil;
        if (!snapshot && !error) error = [NSError errorWithDomain:@"uk.jpsit.telephone.recording-recovery" code:1
            userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Recordings could not be checked. The original audio has been kept.", @"Recovery scan failed without details.")}];
        dispatch_async(dispatch_get_main_queue(), ^{
            AKRecordingRecoveryIndex *index = weakSelf;
            if (index == nil || index.invalidated || index.generation != generation) { if (completion) completion(NO); return; }
            index.refreshing = NO;
            index.hasLoaded = YES;
            index.error = error;
            if (error == nil) {
                index.jobs = snapshot ?: @[];
                if (index.selectedJob == nil) index.selectedIdentity = index.jobs.firstObject[@"directoryIdentity"];
            }
            if (index.stateDidChange) index.stateDidChange();
            if (completion) completion(YES);
        });
    });
}
- (void)invalidate {
    NSAssert(NSThread.isMainThread, @"Recovery presentation shutdown belongs on main");
    self.invalidated = YES;
    self.generation++;
    self.refreshing = NO;
    self.stateDidChange = nil;
}
@end
