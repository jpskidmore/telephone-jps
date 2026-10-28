//
//  AKKeychain.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "AKKeychain.h"

@implementation AKKeychain

+ (nonnull NSDictionary *)queryForService:(nonnull NSString *)service account:(nonnull NSString *)account {
    // Keep this ad-hoc-signed local build independent from the App Store app,
    // earlier development builds, and their keychain access-control entries.
    // SecItem uses the user's login keychain here because the Data Protection
    // keychain requires an Apple-issued application-identifier entitlement.
    NSString *localService = [@"jps Telephone 1.7.2 blue icon v4: " stringByAppendingString:service];
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: localService,
        (__bridge id)kSecAttrAccount: account
    };
}

// An overridable, synchronous Security boundary. Tests override this method;
// normal UI code never calls it or the read-result method directly.
+ (OSStatus)copySecurityItemMatchingQuery:(NSDictionary *)query result:(CFTypeRef *)result {
    return SecItemCopyMatching((__bridge CFDictionaryRef)query, result);
}

+ (AKCredentialReadResult *)resultForSecurityStatus:(OSStatus)status data:(id)data {
    if (status != errSecSuccess) {
        AKCredentialReadStatus kind = AKCredentialReadStatusFailure;
        if (status == errSecItemNotFound) kind = AKCredentialReadStatusMissing;
        else if (status == errSecUserCanceled) kind = AKCredentialReadStatusCancelled;
        else if (status == errSecAuthFailed || status == errSecInteractionNotAllowed) kind = AKCredentialReadStatusDenied;
        else if (status == errSecDecode) kind = AKCredentialReadStatusInvalidData;
        return [AKCredentialReadResult failureWithStatus:kind securityStatus:status];
    }
    if (![data isKindOfClass:NSData.class]) {
        return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusInvalidData securityStatus:errSecDecode];
    }
    NSString *password = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return password ? [AKCredentialReadResult successWithPassword:password]
        : [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusInvalidData securityStatus:errSecDecode];
}

+ (AKCredentialReadResult *)readResultForService:(NSString *)service account:(NSString *)account {
    NSParameterAssert(service);
    NSParameterAssert(account);
    NSMutableDictionary *query = [[self queryForService:service account:account] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = [self copySecurityItemMatchingQuery:query result:&result];
    id data = CFBridgingRelease(result);
    return [self resultForSecurityStatus:status data:data];
}

+ (NSString *)passwordForService:(NSString *)service account:(NSString *)account {
    // Compatibility only. Production UI consumers use AKCredentialBroker so a
    // Security query can neither block main nor erase its typed failure state.
    return [self readResultForService:service account:account].password ?: @"";
}

+ (BOOL)addItemWithService:(nonnull NSString *)service account:(nonnull NSString *)account password:(nonnull NSString *)password {
    return [self addItemWithService:service account:account password:password error:NULL];
}

+ (OSStatus)addSecurityItem:(NSDictionary *)item {
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

+ (OSStatus)updateSecurityItem:(NSDictionary *)query attributes:(NSDictionary *)attributes {
    return SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
}

+ (BOOL)addItemWithService:(NSString *)service account:(NSString *)account password:(NSString *)password
                    error:(NSError **)error {
    NSParameterAssert(service);
    NSParameterAssert(account);
    NSParameterAssert(password);
    if (error) { *error = nil; }
    // Fence both a read already in flight and one admitted while Security is
    // updating the item. A failed write does not resurrect an older result.
    [[AKCredentialBroker sharedBroker] invalidateService:service account:account];
    
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *item = [[self queryForService:service account:account] mutableCopy];
    item[(__bridge id)kSecValueData] = passwordData;

    OSStatus status = [self addSecurityItem:item];
    if (status == errSecSuccess) {
        [[AKCredentialBroker sharedBroker] invalidateService:service account:account];
        return YES;
    }

    if (status == errSecDuplicateItem) {
        NSDictionary *attributes = @{(__bridge id)kSecValueData: passwordData};
        status = [self updateSecurityItem:[self queryForService:service account:account] attributes:attributes];
    }

    if (status != errSecSuccess) {
        NSString *message = CFBridgingRelease(SecCopyErrorMessageString(status, NULL))
            ?: @"The password could not be saved in the Keychain.";
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        NSLog(@"Telephone keychain write failed (%d): %@",
              (int)status,
              CFBridgingRelease(SecCopyErrorMessageString(status, NULL)));
    }

    [[AKCredentialBroker sharedBroker] invalidateService:service account:account];
    return status == errSecSuccess;
}

@end

@interface AKCredentialReadResult ()
- (instancetype)initWithStatus:(AKCredentialReadStatus)status password:(nullable NSString *)password securityStatus:(OSStatus)securityStatus;
@end

@implementation AKCredentialReadResult

- (instancetype)initWithStatus:(AKCredentialReadStatus)status password:(NSString *)password securityStatus:(OSStatus)securityStatus {
    if ((self = [super init])) {
        _status = status;
        _password = status == AKCredentialReadStatusSuccess ? [password copy] : nil;
        _securityStatus = securityStatus;
        NSString *message;
        switch (status) {
            case AKCredentialReadStatusSuccess: break;
            case AKCredentialReadStatusMissing:
                message = NSLocalizedString(@"No saved password is available.", @"Missing Keychain credential."); break;
            case AKCredentialReadStatusCancelled:
                message = NSLocalizedString(@"Keychain access was cancelled. Try again when you are ready.", @"Cancelled Keychain credential access."); break;
            case AKCredentialReadStatusDenied:
                message = NSLocalizedString(@"Keychain access was denied. Try again when you are ready.", @"Denied Keychain credential access."); break;
            case AKCredentialReadStatusInvalidData:
                message = NSLocalizedString(@"The saved password could not be decoded. Enter it again.", @"Malformed Keychain credential."); break;
            case AKCredentialReadStatusFailure:
                message = NSLocalizedString(@"The password could not be read from the Keychain.", @"Other Keychain credential failure."); break;
            case AKCredentialReadStatusSuperseded:
                message = NSLocalizedString(@"This credential request is no longer current.", @"Obsolete credential read."); break;
        }
        if (message) _error = [NSError errorWithDomain:@"uk.jpsit.telephone.credential-read" code:securityStatus
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return self;
}

+ (instancetype)successWithPassword:(NSString *)password {
    NSParameterAssert(password);
    return [[self alloc] initWithStatus:AKCredentialReadStatusSuccess password:password securityStatus:errSecSuccess];
}

+ (instancetype)failureWithStatus:(AKCredentialReadStatus)status securityStatus:(OSStatus)securityStatus {
    NSParameterAssert(status != AKCredentialReadStatusSuccess);
    return [[self alloc] initWithStatus:status password:nil securityStatus:securityStatus];
}

- (NSString *)description {
    // Logging an outcome must never format the password it may contain.
    return [NSString stringWithFormat:@"<AKCredentialReadResult status=%ld securityStatus=%d>", (long)self.status, (int)self.securityStatus];
}

@end

@interface AKCredentialBrokerEntry : NSObject
@property(nonatomic, copy) NSArray<NSString *> *key;
@property(nonatomic) BOOL invalidated;
@property(nonatomic) BOOL pending;
@property(nonatomic) NSTimeInterval expiresAt;
@property(nonatomic) NSUInteger lastUse;
@property(nonatomic) NSUInteger deliveries;
@property(nonatomic) AKCredentialReadResult *result;
@property(nonatomic) NSMutableArray<AKCredentialReadCompletion> *waiters;
@end
@implementation AKCredentialBrokerEntry @end

@interface AKCredentialBroker ()
@property(nonatomic) NSLock *lock;
@property(nonatomic) NSMutableDictionary<NSArray<NSString *> *, AKCredentialBrokerEntry *> *entries;
@property(nonatomic, copy) AKCredentialReader reader;
@property(nonatomic, copy) AKCredentialClock clock;
@property(nonatomic) NSTimeInterval cacheLifetime;
@property(nonatomic) NSUInteger maximumCachedEntries;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic) BOOL stopped;
@property(nonatomic) dispatch_queue_t worker;
@property(nonatomic) dispatch_source_t expiryTimer;
@end

@implementation AKCredentialBroker

+ (instancetype)sharedBroker {
    static AKCredentialBroker *broker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        broker = [[self alloc] initWithReader:^AKCredentialReadResult *(NSString *service, NSString *account) {
            return [AKKeychain readResultForService:service account:account];
        }];
    });
    return broker;
}

- (instancetype)initWithReader:(AKCredentialReader)reader {
    return [self initWithReader:reader cacheLifetime:300 maximumCachedEntries:64 clock:^NSTimeInterval {
        return NSProcessInfo.processInfo.systemUptime;
    }];
}

- (instancetype)initWithReader:(AKCredentialReader)reader cacheLifetime:(NSTimeInterval)cacheLifetime
          maximumCachedEntries:(NSUInteger)maximumCachedEntries clock:(AKCredentialClock)clock {
    NSParameterAssert(reader);
    NSParameterAssert(clock);
    if ((self = [super init])) {
        _reader = [reader copy]; _clock = [clock copy];
        _cacheLifetime = MAX(0, cacheLifetime); _maximumCachedEntries = MAX(1, maximumCachedEntries);
        _lock = [[NSLock alloc] init]; _lock.name = @"Telephone credential admission";
        _entries = [[NSMutableDictionary alloc] init];
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
        _worker = dispatch_queue_create("uk.jpsit.telephone.credential-worker", attributes);
        if (_cacheLifetime > 0) {
            _expiryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
            NSTimeInterval interval = MIN(30, MAX(0.01, _cacheLifetime));
            uint64_t nanoseconds = (uint64_t)(interval * NSEC_PER_SEC);
            dispatch_source_set_timer(_expiryTimer, dispatch_time(DISPATCH_TIME_NOW, nanoseconds), nanoseconds, nanoseconds / 10);
            __weak AKCredentialBroker *weakSelf = self;
            dispatch_source_set_event_handler(_expiryTimer, ^{ [weakSelf purgeExpiredResults]; });
            dispatch_resume(_expiryTimer);
        }
    }
    return self;
}

- (void)dealloc {
    if (_expiryTimer) dispatch_source_cancel(_expiryTimer);
}

- (void)purgeExpiredResults {
    [self.lock lock];
    NSTimeInterval now = self.clock();
    for (AKCredentialBrokerEntry *entry in self.entries.allValues) {
        if (!entry.pending && !entry.deliveries && entry.result && [self isExpiringResult:entry.result] && entry.expiresAt <= now) {
            entry.invalidated = YES; entry.result = nil;
            [self.entries removeObjectForKey:entry.key];
        }
    }
    [self.lock unlock];
}

- (AKCredentialReadResult *)supersededResult {
    return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusSuperseded securityStatus:errSecUserCanceled];
}

- (void)deliverEntry:(AKCredentialBrokerEntry *)entry completion:(AKCredentialReadCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.lock lock];
        AKCredentialReadResult *result = (!self.stopped && !entry.invalidated && self.entries[entry.key] == entry)
            ? entry.result : nil;
        if (entry.deliveries) entry.deliveries--;
        // Keep an admitted result alive until its queued main deliveries have
        // run. Cache expiry/eviction must not cancel a previously admitted read.
        if (result && !entry.deliveries && [self isExpiringResult:result] && entry.expiresAt <= self.clock()) {
            entry.invalidated = YES; entry.result = nil;
            [self.entries removeObjectForKey:entry.key];
        }
        [self.lock unlock];
        completion(result ?: [self supersededResult]);
    });
}

- (void)deliverSuperseded:(NSArray<AKCredentialReadCompletion> *)waiters {
    for (AKCredentialReadCompletion completion in waiters) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion([self supersededResult]); });
    }
}

- (BOOL)isExpiringResult:(AKCredentialReadResult *)result {
    return result.status == AKCredentialReadStatusSuccess || result.status == AKCredentialReadStatusMissing;
}

// Called only under lock. Eviction may drop a successful cached secret, never a
// failed-access latch or an in-flight read. A full set of those entries rejects
// new admission rather than prompting again for a forgotten failure.
- (BOOL)makeRoomLocked {
    while (self.entries.count >= self.maximumCachedEntries) {
        AKCredentialBrokerEntry *oldest;
        for (AKCredentialBrokerEntry *candidate in self.entries.allValues) {
            if (!candidate.pending && !candidate.deliveries && candidate.result && [self isExpiringResult:candidate.result] &&
                (!oldest || candidate.lastUse < oldest.lastUse)) oldest = candidate;
        }
        if (!oldest) return NO;
        oldest.invalidated = YES; oldest.result = nil;
        [self.entries removeObjectForKey:oldest.key];
    }
    return YES;
}

- (void)readPasswordForService:(NSString *)service account:(NSString *)account completion:(AKCredentialReadCompletion)completion {
    NSParameterAssert(service); NSParameterAssert(account); NSParameterAssert(completion);
    NSArray<NSString *> *key = @[[service copy], [account copy]];
    [self.lock lock];
    if (self.stopped) {
        [self.lock unlock];
        [self deliverSuperseded:@[[completion copy]]];
        return;
    }
    AKCredentialBrokerEntry *entry = self.entries[key];
    if (entry.result && !entry.deliveries && [self isExpiringResult:entry.result] && entry.expiresAt <= self.clock()) {
        entry.invalidated = YES; entry.result = nil;
        [self.entries removeObjectForKey:key]; entry = nil;
    }
    if (entry) {
        entry.lastUse = ++self.sequence;
        BOOL wasPending = entry.pending;
        if (wasPending) [entry.waiters addObject:[completion copy]];
        else entry.deliveries++;
        [self.lock unlock];
        if (!wasPending) [self deliverEntry:entry completion:completion];
        return;
    }
    if (![self makeRoomLocked]) {
        [self.lock unlock];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([AKCredentialReadResult failureWithStatus:AKCredentialReadStatusFailure securityStatus:errSecAllocate]);
        });
        return;
    }
    entry = [[AKCredentialBrokerEntry alloc] init]; entry.key = key; entry.pending = YES;
    entry.waiters = [NSMutableArray arrayWithObject:[completion copy]]; entry.lastUse = ++self.sequence;
    self.entries[key] = entry;
    [self.lock unlock];
    dispatch_async(self.worker, ^{
        // A queued request can be invalidated before it reaches the physical
        // reader. One serial worker also prevents overlap with an older prompt.
        [self.lock lock];
        BOOL admitted = !self.stopped && !entry.invalidated && self.entries[key] == entry;
        [self.lock unlock];
        if (!admitted) return;
        AKCredentialReadResult *result = self.reader(key[0], key[1]);
        if (!result) result = [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusFailure securityStatus:errSecInternalComponent];
        [self.lock lock];
        if (self.stopped || entry.invalidated || self.entries[key] != entry) {
            [self.lock unlock]; return;
        }
        entry.pending = NO; entry.result = result;
        entry.expiresAt = self.clock() + self.cacheLifetime;
        NSArray<AKCredentialReadCompletion> *waiters = [entry.waiters copy]; [entry.waiters removeAllObjects];
        entry.deliveries += waiters.count;
        [self.lock unlock];
        for (AKCredentialReadCompletion waiter in waiters) [self deliverEntry:entry completion:waiter];
    });
}

- (void)invalidateService:(NSString *)service account:(NSString *)account {
    NSParameterAssert(service); NSParameterAssert(account);
    NSArray<NSString *> *key = @[service, account];
    [self.lock lock];
    AKCredentialBrokerEntry *entry = self.entries[key];
    entry.invalidated = YES; entry.result = nil;
    NSArray<AKCredentialReadCompletion> *waiters = [entry.waiters copy]; [entry.waiters removeAllObjects];
    [self.entries removeObjectForKey:key];
    [self.lock unlock];
    [self deliverSuperseded:waiters];
}

- (NSArray<AKCredentialReadCompletion> *)invalidateAllLocked {
    NSMutableArray<AKCredentialReadCompletion> *waiters = [[NSMutableArray alloc] init];
    for (AKCredentialBrokerEntry *entry in self.entries.allValues) {
        entry.invalidated = YES; entry.result = nil;
        [waiters addObjectsFromArray:entry.waiters]; [entry.waiters removeAllObjects];
    }
    [self.entries removeAllObjects];
    return waiters;
}

- (void)invalidateAll {
    [self.lock lock]; NSArray *waiters = [self invalidateAllLocked]; [self.lock unlock];
    [self deliverSuperseded:waiters];
}

- (void)shutdown {
    [self.lock lock]; self.stopped = YES;
    NSArray *waiters = [self invalidateAllLocked]; [self.lock unlock];
    [self deliverSuperseded:waiters];
    if (self.expiryTimer) dispatch_source_cancel(self.expiryTimer);
}

@end
