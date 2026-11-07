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

+ (NSDictionary *)queryForService:(NSString *)service account:(NSString *)account {
    // This exact identity remains the rollback source for older local builds.
    // Neither this namespace nor the new one touches the App Store namespace.
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: [@"jps Telephone 1.7.2 blue icon v4: " stringByAppendingString:service],
             (__bridge id)kSecAttrAccount: account};
}

+ (NSDictionary *)cleanQueryForService:(NSString *)service account:(NSString *)account {
    // Preserve the registrar byte-for-byte: case, ports and whitespace must not
    // merge identities which older builds treated as distinct.
    if (![service hasPrefix:@"SIP: "] || service.length <= 5) return nil;
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: [@"uk.jpsit.telephone.sip:" stringByAppendingString:[service substringFromIndex:5]],
             (__bridge id)kSecAttrAccount: account};
}

+ (NSRecursiveLock *)credentialOperationLock {
    static NSRecursiveLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSRecursiveLock new]; lock.name = @"Telephone Keychain operations"; });
    return lock;
}

+ (NSMutableDictionary *)migrationDeferrals {
    // Only non-secret identities/outcomes, at most 64. A failed copy is retried
    // by an explicit password save, never by automatic reconnect/cache expiry.
    static NSMutableDictionary *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ states = [NSMutableDictionary new]; });
    return states;
}

+ (OSStatus)copySecurityItemMatchingQuery:(NSDictionary *)query result:(CFTypeRef *)result {
    return SecItemCopyMatching((__bridge CFDictionaryRef)query, result);
}
+ (OSStatus)addSecurityItem:(NSDictionary *)item {
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}
+ (OSStatus)updateSecurityItem:(NSDictionary *)query attributes:(NSDictionary *)attributes {
    return SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
}

// This receives only the detached snapshot returned by CopyAccess.
+ (OSStatus)prepareAccessForNewItem:(SecAccessRef)access {
    // CopyAccess returns a detached snapshot, not the persisted source policy.
    // Apple excludes these per-item bindings when copying an item: securityd
    // regenerates them for the destination. Keep the owner, trusted applications,
    // prompt selectors and every ordinary permission exactly as copied.
    if (!access) return errSecParam;
    CFArrayRef copied = NULL;
    OSStatus status = SecAccessCopyACLList(access, &copied);
    NSArray *entries = CFBridgingRelease(copied);
    if (status != errSecSuccess) return status;
    if (!entries) return errSecParam;
    NSMutableArray *managed = [NSMutableArray array];
    for (id entry in entries) {
        NSArray *rights = CFBridgingRelease(SecACLCopyAuthorizations((__bridge SecACLRef)entry));
        if (!rights) return errSecParam;
        BOOL hasManaged = NO, hasOrdinary = NO;
        for (id right in rights) {
            if ([right isEqual:(__bridge id)kSecACLAuthorizationIntegrity] ||
                [right isEqual:(__bridge id)kSecACLAuthorizationPartitionID]) hasManaged = YES;
            else hasOrdinary = YES;
        }
        // An unfamiliar mixed policy must not lose user permissions. Reject it
        // before editing even this disposable snapshot, rather than broadening it.
        if (hasManaged && hasOrdinary) return errSecParam;
        if (hasManaged) [managed addObject:entry];
    }
    for (id entry in managed) {
        // SecACLRemove marks an entry deleted but leaves it in the snapshot's
        // list. Clear its managed tags first so destination integrity setup
        // cannot select that deleted entry instead of making a fresh binding.
        status = SecACLUpdateAuthorizations((__bridge SecACLRef)entry, (__bridge CFArrayRef)@[]);
        if (status != errSecSuccess) return status;
        status = SecACLRemove((__bridge SecACLRef)entry);
        if (status != errSecSuccess) return status;
    }
    return errSecSuccess;
}

+ (NSDictionary *)migrationContextForItem:(id)item status:(OSStatus *)status {
    // The authorised legacy read returns its actual item reference. Copy its
    // access list and stay in that same login/file Keychain; never substitute a
    // default or wider ACL, entitlement, access group or synchronisation mode.
    if (!item || CFGetTypeID((__bridge CFTypeRef)item) != SecKeychainItemGetTypeID()) {
        *status = errSecParam; return nil;
    }
    SecAccessRef access = NULL;
    SecKeychainRef keychain = NULL;
    *status = SecKeychainItemCopyAccess((__bridge SecKeychainItemRef)item, &access);
    if (*status == errSecSuccess) *status = SecKeychainItemCopyKeychain((__bridge SecKeychainItemRef)item, &keychain);
    NSDictionary *context = nil;
    if (*status == errSecSuccess && access && keychain) *status = [self prepareAccessForNewItem:access];
    if (*status == errSecSuccess && access && keychain) {
        context = @{(__bridge id)kSecAttrAccess: (__bridge id)access,
                    (__bridge id)kSecUseKeychain: (__bridge id)keychain};
    } else if (*status == errSecSuccess) *status = errSecParam;
    if (access) CFRelease(access);
    if (keychain) CFRelease(keychain);
    return context;
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

+ (id)copyPayloadForQuery:(NSDictionary *)identity includeItem:(BOOL)includeItem status:(OSStatus *)status {
    NSMutableDictionary *query = [identity mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    if (includeItem) {
        query[(__bridge id)kSecReturnAttributes] = @YES;
        query[(__bridge id)kSecReturnRef] = @YES;
    }
    CFTypeRef payload = NULL;
    *status = [self copySecurityItemMatchingQuery:query result:&payload];
    return CFBridgingRelease(payload);
}
+ (id)dataInPayload:(id)payload {
    return [payload isKindOfClass:NSDictionary.class] ? payload[(__bridge id)kSecValueData] : payload;
}
+ (NSDictionary *)scopedCleanQuery:(NSDictionary *)clean context:(NSDictionary *)context {
    NSMutableDictionary *query = [clean mutableCopy];
    query[(__bridge id)kSecMatchSearchList] = @[context[(__bridge id)kSecUseKeychain]];
    return query;
}
+ (NSDictionary *)cleanItem:(NSDictionary *)clean context:(NSDictionary *)context data:(NSData *)data {
    NSMutableDictionary *item = [clean mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    item[(__bridge id)kSecAttrLabel] = @"jps Telephone — SIP account";
    [item addEntriesFromDictionary:context];
    return item;
}
+ (AKCredentialReadResult *)deferMigration:(AKCredentialMigrationStatus)kind status:(OSStatus)status
                                  password:(NSString *)password key:(NSArray *)key {
    return [self deferMigration:kind status:status password:password key:key credentialAvailable:YES];
}
+ (AKCredentialReadResult *)deferMigration:(AKCredentialMigrationStatus)kind status:(OSStatus)status
                                  password:(NSString *)password key:(NSArray *)key credentialAvailable:(BOOL)available {
    if ([self migrationDeferrals].count < 64 || [self migrationDeferrals][key]) {
        [self migrationDeferrals][key] = @[@(kind), @(status), @(available)];
    }
    if (!available) return [AKCredentialReadResult failureWithStatus:[self resultForSecurityStatus:status data:nil].status
        securityStatus:status migrationStatus:kind];
    return [AKCredentialReadResult successWithPassword:password migrationStatus:kind securityStatus:status];
}

+ (AKCredentialReadResult *)readResultForService:(NSString *)service account:(NSString *)account {
    return [self readResultForService:service account:account migrationAllowed:^BOOL { return YES; }];
}
+ (AKCredentialReadResult *)readResultForService:(NSString *)service account:(NSString *)account
                             migrationAllowed:(BOOL (^)(void))migrationAllowed {
    NSParameterAssert(service); NSParameterAssert(account);
    NSRecursiveLock *lock = [self credentialOperationLock];
    // A save on main must not wait behind a modal Keychain read. Likewise a
    // concurrent reader may retry later; no operation interleaves with a copy.
    if (NSThread.isMainThread) {
        if (![lock tryLock]) return [self resultForSecurityStatus:errSecNotAvailable data:nil];
    } else [lock lock]; // Waiting on the utility worker never stalls AppKit.
    @try {
        if (!migrationAllowed()) return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusSuperseded securityStatus:errSecUserCanceled];
        NSDictionary *legacy = [self queryForService:service account:account];
        NSDictionary *clean = [self cleanQueryForService:service account:account];
        OSStatus status;
        NSArray *key = @[NSStringFromClass(self), service, account];
        if (clean) {
            id canonical = [self copyPayloadForQuery:clean includeItem:NO status:&status];
            if (status != errSecItemNotFound) {
                // The clean namespace is canonical. A denied/cancelled or
                // malformed canonical read must never be bypassed via backup.
                AKCredentialReadResult *result = [self resultForSecurityStatus:status data:[self dataInPayload:canonical]];
                if (result.status != AKCredentialReadStatusSuccess) return result;
                NSArray *state = [self migrationDeferrals][key];
                BOOL conflict = state && [state[0] integerValue] == AKCredentialMigrationStatusConflict;
                if (!conflict) [[self migrationDeferrals] removeObjectForKey:key];
                return [AKCredentialReadResult successWithPassword:result.password
                    migrationStatus:conflict ? AKCredentialMigrationStatusConflict : AKCredentialMigrationStatusVerified
                    securityStatus:conflict ? [state[1] intValue] : errSecSuccess];
            }
            if (!migrationAllowed()) return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusSuperseded securityStatus:errSecUserCanceled];
        }
        id payload = [self copyPayloadForQuery:legacy includeItem:clean != nil status:&status];
        NSData *data = [self dataInPayload:payload];
        AKCredentialReadResult *original = [self resultForSecurityStatus:status data:data];
        if (!clean || original.status != AKCredentialReadStatusSuccess) return original;
        if (!migrationAllowed()) return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusSuperseded securityStatus:errSecUserCanceled];
        NSArray *deferred = [self migrationDeferrals][key];
        if (deferred) {
            if (deferred.count > 2 && ![deferred[2] boolValue]) return [AKCredentialReadResult
                failureWithStatus:[self resultForSecurityStatus:[deferred[1] intValue] data:nil].status
                securityStatus:[deferred[1] intValue] migrationStatus:[deferred[0] integerValue]];
            return [AKCredentialReadResult successWithPassword:original.password
                migrationStatus:[deferred[0] integerValue] securityStatus:[deferred[1] intValue]];
        }
        if ([self migrationDeferrals].count >= 64) return [AKCredentialReadResult successWithPassword:original.password
            migrationStatus:AKCredentialMigrationStatusDeferred securityStatus:errSecAllocate];
        id item = [payload isKindOfClass:NSDictionary.class] ? payload[(__bridge id)kSecValueRef] : nil;
        NSDictionary *context = [self migrationContextForItem:item status:&status];
        if (!context) return [self deferMigration:AKCredentialMigrationStatusDeferred status:status password:original.password key:key];
        if (!migrationAllowed()) return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusSuperseded securityStatus:errSecUserCanceled];
        NSDictionary *query = [self scopedCleanQuery:clean context:context];
        id copied = [self copyPayloadForQuery:clean includeItem:NO status:&status];
        if (status == errSecItemNotFound) {
            if (!migrationAllowed()) return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusSuperseded securityStatus:errSecUserCanceled];
            // Copy, never rename/delete the rollback item. A duplicate from a
            // concurrent process is verified, never blindly overwritten.
            status = [self addSecurityItem:[self cleanItem:clean context:context data:data]];
            if (status == errSecSuccess || status == errSecDuplicateItem) {
                if (!migrationAllowed()) return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusSuperseded securityStatus:errSecUserCanceled];
                copied = [self copyPayloadForQuery:query includeItem:NO status:&status];
            }
        }
        NSData *copiedData = [self dataInPayload:copied];
        AKCredentialReadResult *verification = [self resultForSecurityStatus:status data:copiedData];
        if (verification.status != AKCredentialReadStatusSuccess) {
            return [self deferMigration:AKCredentialMigrationStatusDeferred status:verification.securityStatus
                password:original.password key:key credentialAvailable:NO];
        }
        if (![copiedData isEqualToData:data]) {
            return [self deferMigration:AKCredentialMigrationStatusConflict status:errSecDuplicateItem
                password:original.password key:key credentialAvailable:NO];
        }
        return [AKCredentialReadResult successWithPassword:verification.password
            migrationStatus:AKCredentialMigrationStatusVerified securityStatus:errSecSuccess];
    } @finally { [lock unlock]; }
}

+ (NSString *)passwordForService:(NSString *)service account:(NSString *)account {
    return [self readResultForService:service account:account].password ?: @"";
}
+ (BOOL)addItemWithService:(NSString *)service account:(NSString *)account password:(NSString *)password {
    return [self addItemWithService:service account:account password:password error:NULL];
}
+ (OSStatus)saveCompatibilityData:(NSData *)data identity:(NSDictionary *)identity {
    NSMutableDictionary *query = [identity mutableCopy];
    // Bind an update to the exact item found in the search list, without reading
    // the old password just to write an explicitly entered replacement.
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecReturnRef] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = [self copySecurityItemMatchingQuery:query result:&result];
    id payload = CFBridgingRelease(result);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [identity mutableCopy];
        item[(__bridge id)kSecValueData] = data;
        item[(__bridge id)kSecAttrLabel] = @"jps Telephone — SIP account (compatibility copy)";
        status = [self addSecurityItem:item];
        if (status != errSecDuplicateItem) return status;
        result = NULL;
        status = [self copySecurityItemMatchingQuery:query result:&result];
        payload = CFBridgingRelease(result);
    }
    if (status != errSecSuccess) return status;
    id item = [payload isKindOfClass:NSDictionary.class] ? payload[(__bridge id)kSecValueRef] : nil;
    if (!item) return errSecParam;
    NSMutableDictionary *match = [identity mutableCopy];
    match[(__bridge id)kSecMatchItemList] = @[item];
    return [self updateSecurityItem:match attributes:@{(__bridge id)kSecValueData:data,
        (__bridge id)kSecAttrLabel:@"jps Telephone — SIP account (compatibility copy)"}];
}
+ (OSStatus)saveData:(NSData *)data identity:(NSDictionary *)identity additions:(NSDictionary *)additions {
    NSMutableDictionary *item = [identity mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    [item addEntriesFromDictionary:additions];
    OSStatus status = [self addSecurityItem:item];
    if (status == errSecDuplicateItem) {
        NSMutableDictionary *attributes = [@{(__bridge id)kSecValueData:data} mutableCopy];
        if (additions[(__bridge id)kSecAttrLabel]) attributes[(__bridge id)kSecAttrLabel] = additions[(__bridge id)kSecAttrLabel];
        // Preserve the existing item's ACL and identity when updating its value.
        status = [self updateSecurityItem:identity attributes:attributes];
    }
    return status;
}
+ (BOOL)addItemWithService:(NSString *)service account:(NSString *)account password:(NSString *)password error:(NSError **)error {
    NSParameterAssert(service); NSParameterAssert(account); NSParameterAssert(password);
    if (error) *error = nil;
    AKCredentialBroker *broker = AKCredentialBroker.sharedBroker;
    [broker invalidateService:service account:account];
    NSRecursiveLock *lock = [self credentialOperationLock];
    OSStatus status = errSecNotAvailable;
    BOOL compatibilitySaved = NO;
    NSString *saveStage = @"operation-admission";
    if ([lock tryLock]) {
        @try {
            NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *legacy = [self queryForService:service account:account];
            NSDictionary *clean = [self cleanQueryForService:service account:account];
            [[self migrationDeferrals] removeObjectForKey:@[NSStringFromClass(self), service, account]];
            saveStage = @"compatibility-write";
            status = data ? (clean ? [self saveCompatibilityData:data identity:legacy]
                : [self saveData:data identity:legacy additions:@{}]) : errSecParam;
            if (status == errSecSuccess && clean) {
                compatibilitySaved = YES;
                saveStage = @"compatibility-readback";
                id payload = [self copyPayloadForQuery:legacy includeItem:YES status:&status];
                if (status == errSecSuccess && ![[self dataInPayload:payload] isEqual:data]) status = errSecDecode;
                if (status == errSecSuccess) {
                    id item = [payload isKindOfClass:NSDictionary.class] ? payload[(__bridge id)kSecValueRef] : nil;
                    saveStage = @"access-context";
                    NSDictionary *context = [self migrationContextForItem:item status:&status];
                    if (context) {
                        NSDictionary *query = [self scopedCleanQuery:clean context:context];
                        // Add in the source Keychain; update with a precise search
                        // there, without supplying ACL attributes to SecItemUpdate.
                        saveStage = @"canonical-write";
                        status = [self addSecurityItem:[self cleanItem:clean context:context data:data]];
                        if (status == errSecDuplicateItem) {
                            saveStage = @"canonical-update";
                            status = [self updateSecurityItem:query attributes:
                                @{(__bridge id)kSecValueData:data, (__bridge id)kSecAttrLabel:@"jps Telephone — SIP account"}];
                        }
                        if (status == errSecSuccess) {
                            saveStage = @"canonical-readback";
                            id verified = [self copyPayloadForQuery:query includeItem:NO status:&status];
                            if (status == errSecSuccess && ![[self dataInPayload:verified] isEqual:data]) status = errSecDecode;
                        }
                        if (status == errSecSuccess) {
                            // Registration reads the whole search list. Another
                            // Keychain may shadow this scoped copy; never report
                            // a successful save while that effective value differs.
                            saveStage = @"effective-readback";
                            id effective = [self copyPayloadForQuery:clean includeItem:NO status:&status];
                            if (status == errSecSuccess && ![[self dataInPayload:effective] isEqual:data]) status = errSecDecode;
                        }
                    }
                }
            }
            if (compatibilitySaved && status != errSecSuccess) {
                [self deferMigration:AKCredentialMigrationStatusConflict status:status password:password
                    key:@[NSStringFromClass(self), service, account]];
            }
        } @finally { [lock unlock]; }
    }
    [broker invalidateService:service account:account];
    if (status != errSecSuccess && error) {
        NSString *message = compatibilitySaved
            ? NSLocalizedString(@"The compatibility password was saved, but the new Keychain entry could not be verified. Account changes have not been applied. Try saving again.", @"Partial Keychain migration save.")
            : (status == errSecNotAvailable
                ? NSLocalizedString(@"The Keychain is busy or unavailable. Try saving again after any password request finishes.", @"Busy Keychain save.")
                : (CFBridgingRelease(SecCopyErrorMessageString(status, NULL)) ?: @"The password could not be saved in the Keychain."));
        // Fixed operation names and an OSStatus are safe to share. Never put
        // service/account names, Keychain paths or password values in errors.
        NSDictionary *steps = @{
            @"operation-admission": NSLocalizedString(@"Starting the password save", @"Keychain save diagnostic stage."),
            @"compatibility-write": NSLocalizedString(@"Saving the compatibility entry", @"Keychain save diagnostic stage."),
            @"compatibility-readback": NSLocalizedString(@"Verifying the compatibility entry", @"Keychain save diagnostic stage."),
            @"access-context": NSLocalizedString(@"Preserving Keychain permissions", @"Keychain save diagnostic stage."),
            @"canonical-write": NSLocalizedString(@"Saving the new Keychain entry", @"Keychain save diagnostic stage."),
            @"canonical-update": NSLocalizedString(@"Updating the new Keychain entry", @"Keychain save diagnostic stage."),
            @"canonical-readback": NSLocalizedString(@"Verifying the new Keychain entry", @"Keychain save diagnostic stage."),
            @"effective-readback": NSLocalizedString(@"Verifying the entry selected for sign-in", @"Keychain save diagnostic stage.")
        };
        message = [NSString stringWithFormat:NSLocalizedString(@"%@\n\n%@ (Keychain error %d).", @"Credential save failure with safe diagnostic."),
                   message, steps[saveStage], (int)status];
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{
            NSLocalizedDescriptionKey:message, @"AKCredentialSaveStage":saveStage}];
    }
    return status == errSecSuccess;
}

@end

@interface AKCredentialReadResult ()
- (instancetype)initWithStatus:(AKCredentialReadStatus)status password:(nullable NSString *)password securityStatus:(OSStatus)securityStatus;
- (void)applyMigrationStatus:(AKCredentialMigrationStatus)status securityStatus:(OSStatus)securityStatus;
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

- (void)applyMigrationStatus:(AKCredentialMigrationStatus)status securityStatus:(OSStatus)securityStatus {
    _migrationStatus = status;
    _migrationSecurityStatus = securityStatus;
    if (status == AKCredentialMigrationStatusConflict) {
        _migrationHelp = NSLocalizedString(@"The Keychain entries need reconciliation. Re-enter the intended password in Accounts to reconcile them.", @"Conflicting Keychain namespace copies.");
    } else if (status == AKCredentialMigrationStatusDeferred) {
        _migrationHelp = NSLocalizedString(@"Keychain migration could not be verified. The compatibility entry is retained. Re-enter the password in Accounts to retry migration.", @"Deferred Keychain namespace migration.");
    }
}
+ (instancetype)successWithPassword:(NSString *)password migrationStatus:(AKCredentialMigrationStatus)migrationStatus
                    securityStatus:(OSStatus)securityStatus {
    AKCredentialReadResult *result = [self successWithPassword:password];
    [result applyMigrationStatus:migrationStatus securityStatus:securityStatus];
    return result;
}
+ (instancetype)failureWithStatus:(AKCredentialReadStatus)status securityStatus:(OSStatus)securityStatus
                 migrationStatus:(AKCredentialMigrationStatus)migrationStatus {
    AKCredentialReadResult *result = [self failureWithStatus:status securityStatus:securityStatus];
    [result applyMigrationStatus:migrationStatus securityStatus:securityStatus];
    return result;
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
@property(nonatomic) Class keychainReaderClass;
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
        broker.keychainReaderClass = AKKeychain.class;
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
        AKCredentialReadResult *result;
        if (self.keychainReaderClass) {
            result = [self.keychainReaderClass readResultForService:key[0] account:key[1] migrationAllowed:^BOOL {
                [self.lock lock];
                BOOL current = !self.stopped && !entry.invalidated && self.entries[key] == entry;
                [self.lock unlock];
                return current;
            }];
        } else result = self.reader(key[0], key[1]);
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
