#import <XCTest/XCTest.h>
#import "AKKeychain.h"

@interface AKKeychain (Credential73SecuritySeam)
+ (OSStatus)prepareAccessForNewItem:(SecAccessRef)access;
+ (OSStatus)copySecurityItemMatchingQuery:(NSDictionary *)query result:(CFTypeRef *)result;
@end
static NSDictionary *Credential73LastQuery;
static OSStatus Credential73Status;
static id Credential73Data;
@interface Credential73SyntheticKeychain : AKKeychain @end
@implementation Credential73SyntheticKeychain
+ (OSStatus)copySecurityItemMatchingQuery:(NSDictionary *)query result:(CFTypeRef *)result {
    Credential73LastQuery = query;
    *result = Credential73Data ? CFBridgingRetain(Credential73Data) : NULL;
    return Credential73Status;
}
@end

@interface CredentialBrokerTests : XCTestCase
@property(nonatomic) NSMutableArray<AKCredentialBroker *> *brokers;
@end
@implementation CredentialBrokerTests
- (void)setUp { [super setUp]; self.brokers = [NSMutableArray array]; }
- (void)tearDown {
    for (AKCredentialBroker *broker in self.brokers) [broker shutdown];
    Credential73LastQuery = nil; Credential73Data = nil;
    [super tearDown];
}
- (AKCredentialBroker *)broker:(AKCredentialReader)reader {
    AKCredentialBroker *broker = [[AKCredentialBroker alloc] initWithReader:reader];
    [self.brokers addObject:broker]; return broker;
}
- (AKCredentialReadResult *)read:(AKCredentialBroker *)broker service:(NSString *)service account:(NSString *)account {
    XCTestExpectation *done = [self expectationWithDescription:@"synthetic credential completion"];
    __block AKCredentialReadResult *observed;
    [broker readPasswordForService:service account:account completion:^(AKCredentialReadResult *result) {
        XCTAssertTrue(NSThread.isMainThread); observed = result; [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:3]; return observed;
}
- (void)testTypedResultsDistinguishEmptySuccessFromEveryFailure {
    AKCredentialReadResult *empty = [AKKeychain resultForSecurityStatus:errSecSuccess data:[NSData data]];
    XCTAssertEqual(empty.status, AKCredentialReadStatusSuccess); XCTAssertEqualObjects(empty.password, @""); XCTAssertNil(empty.error);
    NSArray *statuses = @[@(errSecItemNotFound), @(errSecUserCanceled), @(errSecAuthFailed), @(errSecInteractionNotAllowed), @(errSecDecode), @(errSecNotAvailable)];
    NSArray *kinds = @[@(AKCredentialReadStatusMissing), @(AKCredentialReadStatusCancelled), @(AKCredentialReadStatusDenied), @(AKCredentialReadStatusDenied), @(AKCredentialReadStatusInvalidData), @(AKCredentialReadStatusFailure)];
    for (NSUInteger i = 0; i < statuses.count; i++) {
        AKCredentialReadResult *result = [AKKeychain resultForSecurityStatus:[statuses[i] intValue] data:[@"ignored" dataUsingEncoding:NSUTF8StringEncoding]];
        XCTAssertEqual(result.status, [kinds[i] integerValue]); XCTAssertNil(result.password); XCTAssertNotNil(result.error);
    }
}
- (void)testMalformedSuccessPayloadCannotBecomeEmptyPassword {
    const unsigned char bytes[] = {0xff, 0xfe};
    for (id data in @[@"wrong type", [NSData dataWithBytes:bytes length:2]]) {
        AKCredentialReadResult *result = [AKKeychain resultForSecurityStatus:errSecSuccess data:data];
        XCTAssertEqual(result.status, AKCredentialReadStatusInvalidData); XCTAssertNil(result.password);
    }
}
- (void)testSecurityBoundaryPreservesExactNamespacePairAndSingleItemQuery {
    Credential73Status = errSecSuccess; Credential73Data = [@"fixture" dataUsingEncoding:NSUTF8StringEncoding];
    AKCredentialReadResult *result = [Credential73SyntheticKeychain readResultForService:@"SIP: synthetic.invalid" account:@"synthetic account"];
    XCTAssertEqualObjects(result.password, @"fixture");
    XCTAssertEqualObjects(Credential73LastQuery[(__bridge id)kSecAttrService], @"uk.jpsit.telephone.sip:synthetic.invalid");
    XCTAssertEqualObjects(Credential73LastQuery[(__bridge id)kSecAttrAccount], @"synthetic account");
    XCTAssertEqualObjects(Credential73LastQuery[(__bridge id)kSecMatchLimit], (__bridge id)kSecMatchLimitOne);
    XCTAssertEqualObjects(Credential73LastQuery[(__bridge id)kSecReturnData], @YES);
}
- (void)testCoalescesConcurrentReadersWithoutBlockingMain {
    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    XCTestExpectation *started = [self expectationWithDescription:@"worker started"], *done = [self expectationWithDescription:@"both consumers"];
    done.expectedFulfillmentCount = 2; __block NSUInteger reads = 0;
    AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *service, NSString *account) {
        XCTAssertFalse(NSThread.isMainThread); reads++; [started fulfill];
        dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
        return [AKCredentialReadResult successWithPassword:@"synthetic"];
    }];
    for (NSUInteger i = 0; i < 2; i++) [broker readPasswordForService:@"service" account:@"account" completion:^(AKCredentialReadResult *result) {
        XCTAssertTrue(NSThread.isMainThread); XCTAssertEqualObjects(result.password, @"synthetic"); [done fulfill];
    }];
    [self waitForExpectations:@[started] timeout:2];
    XCTestExpectation *ping = [self expectationWithDescription:@"main responsive during credential prompt"];
    dispatch_async(dispatch_get_main_queue(), ^{ [ping fulfill]; }); [self waitForExpectations:@[ping] timeout:1];
    XCTAssertEqual(reads, 1u); dispatch_semaphore_signal(gate); [self waitForExpectations:@[done] timeout:3];
}
- (void)testCachesSuccessAndKeepsExactPairsDistinct {
    __block NSUInteger reads = 0;
    AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *service, NSString *account) {
        reads++; return [AKCredentialReadResult successWithPassword:[NSString stringWithFormat:@"%@ / %@", service, account]];
    }];
    XCTAssertEqualObjects([self read:broker service:@"a|b" account:@"c"].password, @"a|b / c");
    XCTAssertEqualObjects([self read:broker service:@"a" account:@"b|c"].password, @"a / b|c");
    [self read:broker service:@"a|b" account:@"c"]; XCTAssertEqual(reads, 2u);
}
- (void)testMissingResultIsCachedWithoutSupplyingAnEmptyPassword {
    __block NSUInteger reads = 0;
    AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *s, NSString *a) {
        reads++; return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusMissing securityStatus:errSecItemNotFound];
    }];
    for (NSUInteger i = 0; i < 2; i++) { AKCredentialReadResult *r = [self read:broker service:@"s" account:@"a"]; XCTAssertEqual(r.status, AKCredentialReadStatusMissing); XCTAssertNil(r.password); }
    XCTAssertEqual(reads, 1u);
}
- (void)testCancelledDeniedAndOtherFailuresRemainLatchedUntilExplicitInvalidation {
    for (NSNumber *kind in @[@(AKCredentialReadStatusCancelled), @(AKCredentialReadStatusDenied), @(AKCredentialReadStatusInvalidData), @(AKCredentialReadStatusFailure)]) {
        __block NSUInteger reads = 0;
        AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *s, NSString *a) {
            reads++; return reads == 1 ? [AKCredentialReadResult failureWithStatus:kind.integerValue securityStatus:errSecAuthFailed] : [AKCredentialReadResult successWithPassword:@"deliberate retry"];
        }];
        for (NSUInteger i = 0; i < 2; i++) { AKCredentialReadResult *r = [self read:broker service:@"s" account:@"a"]; XCTAssertEqual(r.status, kind.integerValue); XCTAssertNil(r.password); }
        XCTAssertEqual(reads, 1u); [broker invalidateService:@"s" account:@"a"];
        XCTAssertEqualObjects([self read:broker service:@"s" account:@"a"].password, @"deliberate retry"); XCTAssertEqual(reads, 2u);
    }
}
- (void)testInvalidationCompletesImmediatelyAndSerialisesReplacementRead {
    dispatch_semaphore_t gate = dispatch_semaphore_create(0); __block NSUInteger reads = 0;
    XCTestExpectation *started = [self expectationWithDescription:@"old physical read"], *stale = [self expectationWithDescription:@"obsolete delivery"], *fresh = [self expectationWithDescription:@"replacement read"];
    AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *s, NSString *a) {
        reads++; if (reads == 1) { [started fulfill]; dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)); return [AKCredentialReadResult successWithPassword:@"obsolete"]; }
        return [AKCredentialReadResult successWithPassword:@"current"];
    }];
    [broker readPasswordForService:@"s" account:@"a" completion:^(AKCredentialReadResult *r) { XCTAssertEqual(r.status, AKCredentialReadStatusSuperseded); XCTAssertNil(r.password); [stale fulfill]; }];
    [self waitForExpectations:@[started] timeout:2]; [broker invalidateService:@"s" account:@"a"];
    [broker readPasswordForService:@"s" account:@"a" completion:^(AKCredentialReadResult *r) { XCTAssertEqualObjects(r.password, @"current"); [fresh fulfill]; }];
    [self waitForExpectations:@[stale] timeout:1]; XCTAssertEqual(reads, 1u);
    dispatch_semaphore_signal(gate); [self waitForExpectations:@[fresh] timeout:3];
    XCTAssertEqualObjects([self read:broker service:@"s" account:@"a"].password, @"current"); XCTAssertEqual(reads, 2u);
}
- (void)testQueuedInvalidatedReadNeverReachesReader {
    dispatch_semaphore_t gate = dispatch_semaphore_create(0); __block NSUInteger reads = 0;
    XCTestExpectation *started = [self expectationWithDescription:@"first started"], *first = [self expectationWithDescription:@"first completed"], *second = [self expectationWithDescription:@"queued cancelled"];
    AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *s, NSString *a) {
        reads++; [started fulfill]; dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)); return [AKCredentialReadResult successWithPassword:@"fixture"];
    }];
    [broker readPasswordForService:@"s" account:@"a" completion:^(AKCredentialReadResult *r) { [first fulfill]; }];
    [self waitForExpectations:@[started] timeout:2];
    [broker readPasswordForService:@"s" account:@"b" completion:^(AKCredentialReadResult *r) { XCTAssertEqual(r.status, AKCredentialReadStatusSuperseded); [second fulfill]; }];
    [broker invalidateService:@"s" account:@"b"]; [self waitForExpectations:@[second] timeout:1];
    dispatch_semaphore_signal(gate); [self waitForExpectations:@[first] timeout:3]; XCTAssertEqual(reads, 1u);
}
- (void)testInvalidationFencesAlreadyQueuedCachedDelivery {
    AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *s, NSString *a) { return [AKCredentialReadResult successWithPassword:@"fixture"]; }];
    [self read:broker service:@"s" account:@"a"];
    XCTestExpectation *done = [self expectationWithDescription:@"queued cache delivery fenced"];
    [broker readPasswordForService:@"s" account:@"a" completion:^(AKCredentialReadResult *r) { XCTAssertEqual(r.status, AKCredentialReadStatusSuperseded); XCTAssertNil(r.password); [done fulfill]; }];
    [broker invalidateService:@"s" account:@"a"]; [self waitForExpectations:@[done] timeout:2];
}
- (void)testShutdownClearsCacheAndRejectsNewAdmission {
    __block NSUInteger reads = 0;
    AKCredentialBroker *broker = [self broker:^AKCredentialReadResult *(NSString *s, NSString *a) { reads++; return [AKCredentialReadResult successWithPassword:@"fixture"]; }];
    [self read:broker service:@"s" account:@"a"]; [broker shutdown];
    XCTAssertEqual([self read:broker service:@"s" account:@"a"].status, AKCredentialReadStatusSuperseded); XCTAssertEqual(reads, 1u);
}
- (void)testClockExpiryRequiresFreshReadAndCapacityEvictsSuccess {
    __block NSTimeInterval now = 0; __block NSUInteger reads = 0;
    AKCredentialBroker *broker = [[AKCredentialBroker alloc] initWithReader:^AKCredentialReadResult *(NSString *s, NSString *a) { reads++; return [AKCredentialReadResult successWithPassword:@"fixture"]; } cacheLifetime:10 maximumCachedEntries:1 clock:^NSTimeInterval { return now; }];
    [self.brokers addObject:broker]; [self read:broker service:@"s" account:@"a"]; now = 11;
    [self read:broker service:@"s" account:@"a"]; XCTAssertEqual(reads, 2u);
    [self read:broker service:@"s" account:@"b"]; [self read:broker service:@"s" account:@"a"]; XCTAssertEqual(reads, 4u);
}
- (void)testFullFailureCacheRejectsNewItemWithoutForgettingDeniedEntry {
    __block NSUInteger reads = 0;
    AKCredentialBroker *broker = [[AKCredentialBroker alloc] initWithReader:^AKCredentialReadResult *(NSString *s, NSString *a) { reads++; return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusDenied securityStatus:errSecAuthFailed]; } cacheLifetime:1 maximumCachedEntries:1 clock:^NSTimeInterval { return 0; }];
    [self.brokers addObject:broker]; [self read:broker service:@"s" account:@"a"];
    XCTAssertEqual([self read:broker service:@"s" account:@"b"].status, AKCredentialReadStatusFailure);
    XCTAssertEqual([self read:broker service:@"s" account:@"a"].status, AKCredentialReadStatusDenied); XCTAssertEqual(reads, 1u);
}
- (void)testResultDescriptionDoesNotExposePassword {
    AKCredentialReadResult *result = [AKCredentialReadResult successWithPassword:@"synthetic-private-payload"];
    XCTAssertFalse([result.description containsString:@"synthetic-private-payload"]);
}
@end

// Issue #77: every Security call is intercepted. These items are in-memory
// synthetic fixtures; no login Keychain, real credentials or OS prompts.
@interface AKKeychain (Namespace77Seams)
+ (OSStatus)addSecurityItem:(NSDictionary *)item;
+ (OSStatus)updateSecurityItem:(NSDictionary *)query attributes:(NSDictionary *)attributes;
+ (NSDictionary *)migrationContextForItem:(id)item status:(OSStatus *)status;
+ (NSMutableDictionary *)migrationDeferrals;
+ (AKCredentialReadResult *)readResultForService:(NSString *)service account:(NSString *)account migrationAllowed:(BOOL (^)(void))allowed;
@end
static NSMutableDictionary *K77Items, *K77ReadFaults, *K77AddFaults, *K77UpdateFaults, *K77Deferrals;
static NSMutableArray *K77Operations;
static OSStatus K77ContextStatus;
static NSData *K77RaceData, *K77CorruptCopy;
static void (^K77BeforeRead)(NSDictionary *);
static void (^K77ReadDidFinish)(void);
static NSString *const K77Service = @"SIP: sip.synthetic.invalid:5061";
static NSString *const K77Account = @"synthetic user";
static NSString *const K77Keychain = @"isolated synthetic file Keychain";
static NSString *K77Legacy(NSString *service) { return [@"jps Telephone 1.7.2 blue icon v4: " stringByAppendingString:service]; }
static NSString *K77Clean(NSString *service) { return [@"uk.jpsit.telephone.sip:" stringByAppendingString:[service substringFromIndex:5]]; }
static NSArray *K77Key(NSDictionary *query) { return @[query[(__bridge id)kSecAttrService], query[(__bridge id)kSecAttrAccount]]; }
static OSStatus K77Fault(NSMutableDictionary *faults, NSDictionary *query, OSStatus fallback) {
    NSMutableArray *values = faults[K77Key(query)];
    if (!values.count) return fallback;
    OSStatus status = [values.firstObject intValue]; [values removeObjectAtIndex:0]; return status;
}
@interface Namespace77Keychain : AKKeychain @end
@implementation Namespace77Keychain
+ (AKCredentialReadResult *)readResultForService:(NSString *)service account:(NSString *)account migrationAllowed:(BOOL (^)(void))allowed {
    AKCredentialReadResult *result = [super readResultForService:service account:account migrationAllowed:allowed];
    if (K77ReadDidFinish) K77ReadDidFinish();
    return result;
}
+ (NSMutableDictionary *)migrationDeferrals { return K77Deferrals; }
+ (OSStatus)copySecurityItemMatchingQuery:(NSDictionary *)query result:(CFTypeRef *)result {
    [K77Operations addObject:@{@"operation":@"read", @"query":query}];
    if (K77BeforeRead) K77BeforeRead(query);
    NSDictionary *item = K77Items[K77Key(query)];
    NSArray *search = query[(__bridge id)kSecMatchSearchList];
    if (search && ![search containsObject:K77Keychain]) item = nil;
    OSStatus status = K77Fault(K77ReadFaults, query, item ? errSecSuccess : errSecItemNotFound);
    if (status != errSecSuccess) { *result = NULL; return status; }
    id value = query[(__bridge id)kSecReturnAttributes]
        ? @{(__bridge id)kSecValueData:item[(__bridge id)kSecValueData], (__bridge id)kSecValueRef:item}
        : item[(__bridge id)kSecValueData];
    *result = value ? CFBridgingRetain(value) : NULL; return status;
}
+ (NSDictionary *)migrationContextForItem:(id)item status:(OSStatus *)status {
    [K77Operations addObject:@{@"operation":@"context"}];
    *status = K77ContextStatus;
    if (*status != errSecSuccess) return nil;
    return @{(__bridge id)kSecAttrAccess:item[(__bridge id)kSecAttrAccess], (__bridge id)kSecUseKeychain:K77Keychain};
}
+ (OSStatus)addSecurityItem:(NSDictionary *)item {
    [K77Operations addObject:@{@"operation":@"add", @"query":item}];
    OSStatus status = K77Fault(K77AddFaults, item, K77Items[K77Key(item)] ? errSecDuplicateItem : errSecSuccess);
    if (status == errSecSuccess || (status == errSecDuplicateItem && K77RaceData)) {
        NSMutableDictionary *stored = [item mutableCopy];
        if (K77RaceData) { stored[(__bridge id)kSecValueData] = K77RaceData; K77RaceData = nil; }
        else if (K77CorruptCopy && [item[(__bridge id)kSecAttrService] hasPrefix:@"uk.jpsit."]) stored[(__bridge id)kSecValueData] = K77CorruptCopy;
        if (!stored[(__bridge id)kSecAttrAccess]) stored[(__bridge id)kSecAttrAccess] = @"synthetic default ACL";
        K77Items[K77Key(item)] = stored;
    }
    return status;
}
+ (OSStatus)updateSecurityItem:(NSDictionary *)query attributes:(NSDictionary *)attributes {
    [K77Operations addObject:@{@"operation":@"update", @"query":query, @"attributes":attributes}];
    NSMutableDictionary *item = K77Items[K77Key(query)];
    OSStatus status = K77Fault(K77UpdateFaults, query, item ? errSecSuccess : errSecItemNotFound);
    if (status == errSecSuccess) [item addEntriesFromDictionary:attributes];
    return status;
}
@end

// Model an existing canonical item earlier in the search list, outside the
// source file Keychain. All writes still use the synthetic source store above.
static id K77EarlierCanonicalData;
static OSStatus K77EarlierCanonicalStatus;
@interface SearchList77Keychain : Namespace77Keychain @end
@implementation SearchList77Keychain
+ (OSStatus)copySecurityItemMatchingQuery:(NSDictionary *)query result:(CFTypeRef *)result {
    if ([query[(__bridge id)kSecAttrService] isEqual:K77Clean(K77Service)] &&
        [query[(__bridge id)kSecAttrAccount] isEqual:K77Account] &&
        !query[(__bridge id)kSecMatchSearchList]) {
        [K77Operations addObject:@{@"operation":@"read", @"query":query}];
        *result = K77EarlierCanonicalStatus == errSecSuccess && K77EarlierCanonicalData
            ? CFBridgingRetain(K77EarlierCanonicalData) : NULL;
        return K77EarlierCanonicalStatus;
    }
    return [super copySecurityItemMatchingQuery:query result:result];
}
@end

@interface KeychainNamespaceMigrationTests : XCTestCase @end
@implementation KeychainNamespaceMigrationTests
- (void)setUp {
    [super setUp];
    K77Items = [NSMutableDictionary new]; K77Operations = [NSMutableArray new];
    K77ReadFaults = [NSMutableDictionary new]; K77AddFaults = [NSMutableDictionary new]; K77UpdateFaults = [NSMutableDictionary new];
    K77Deferrals = [NSMutableDictionary new]; K77ContextStatus = errSecSuccess;
    K77RaceData = K77CorruptCopy = nil; K77BeforeRead = nil; K77ReadDidFinish = nil;
    K77EarlierCanonicalData = nil; K77EarlierCanonicalStatus = errSecSuccess;
}
- (void)tearDown {
    K77BeforeRead = nil; K77ReadDidFinish = nil; K77Items = K77ReadFaults = K77AddFaults = K77UpdateFaults = K77Deferrals = nil;
    K77Operations = nil; K77RaceData = K77CorruptCopy = nil; [super tearDown];
    K77EarlierCanonicalData = nil;
}
- (NSData *)data:(NSString *)value { return [value dataUsingEncoding:NSUTF8StringEncoding]; }
- (void)seed:(NSString *)namespace service:(NSString *)service account:(NSString *)account password:(NSString *)password {
    NSString *name = [namespace isEqual:@"legacy"] ? K77Legacy(service) : K77Clean(service);
    K77Items[@[name,account]] = [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:name, (__bridge id)kSecAttrAccount:account,
        (__bridge id)kSecValueData:[self data:password], (__bridge id)kSecAttrAccess:[NSObject new]} mutableCopy];
}
- (void)seedLegacy { [self seed:@"legacy" service:K77Service account:K77Account password:@"synthetic password"]; }
- (AKCredentialReadResult *)read { return [Namespace77Keychain readResultForService:K77Service account:K77Account]; }
- (NSArray *)operations:(NSString *)kind {
    return [K77Operations filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *op, NSDictionary *bindings) { return [op[@"operation"] isEqual:kind]; }]];
}
- (NSDictionary *)legacy { return K77Items[@[K77Legacy(K77Service),K77Account]]; }
- (NSDictionary *)clean { return K77Items[@[K77Clean(K77Service),K77Account]]; }
- (void)fault:(NSMutableDictionary *)faults namespace:(NSString *)namespace statuses:(NSArray *)statuses {
    faults[@[[namespace isEqual:@"legacy"] ? K77Legacy(K77Service) : K77Clean(K77Service),K77Account]] = [statuses mutableCopy];
}
- (BOOL)save:(NSString *)password error:(NSError **)error {
    return [Namespace77Keychain addItemWithService:K77Service account:K77Account password:password error:error];
}
- (void)testAuthorisedCopyRetainsExactSourceACLAndKeychainAndVerifiesNewValue {
    [self seedLegacy]; NSDictionary *before = [self.legacy copy];
    AKCredentialReadResult *result = [self read];
    XCTAssertEqual(result.status, AKCredentialReadStatusSuccess);
    XCTAssertEqual(result.migrationStatus, AKCredentialMigrationStatusVerified);
    XCTAssertEqualObjects(result.password, @"synthetic password");
    XCTAssertEqualObjects(self.legacy, before);
    XCTAssertEqual(self.clean[(__bridge id)kSecAttrAccess], before[(__bridge id)kSecAttrAccess]);
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecUseKeychain], K77Keychain);
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecAttrLabel], @"jps Telephone — SIP account");
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData], before[(__bridge id)kSecValueData]);
    XCTAssertEqual([self operations:@"add"].count, 1u); XCTAssertEqual([self operations:@"read"].count, 4u);
    NSDictionary *verify = [self operations:@"read"].lastObject[@"query"];
    XCTAssertEqualObjects(verify[(__bridge id)kSecAttrService], K77Clean(K77Service));
    XCTAssertEqualObjects(verify[(__bridge id)kSecMatchSearchList], @[K77Keychain]);
    XCTAssertNil(self.clean[(__bridge id)kSecAttrSynchronizable]);
    XCTAssertNil(self.clean[(__bridge id)kSecUseDataProtectionKeychain]);
    XCTAssertNil(self.clean[(__bridge id)kSecAttrAccessGroup]);
}
- (void)testRepeatedReadsAndSimulatedRelaunchDoNotCreateDuplicateCopies {
    [self seedLegacy]; [self read]; [K77Deferrals removeAllObjects];
    for (int i=0; i<3; i++) XCTAssertEqual([self read].migrationStatus, AKCredentialMigrationStatusVerified);
    XCTAssertEqual(K77Items.count, 2u); XCTAssertEqual([self operations:@"add"].count, 1u); XCTAssertEqual([self operations:@"update"].count, 0u);
}
- (void)testExactRegistrarAndAccountPairsNeverMergeOrTouchOtherNamespaces {
    NSArray *pairs = @[@[@"SIP: registrar.invalid",@"a|b"], @[@"SIP: REGISTRAR.invalid:5061",@"a|b"], @[@"SIP: registrar.invalid",@"b"]];
    for (NSArray *pair in pairs) {
        [self seed:@"legacy" service:pair[0] account:pair[1] password:[pair componentsJoinedByString:@" / "]];
        AKCredentialReadResult *r = [Namespace77Keychain readResultForService:pair[0] account:pair[1]];
        XCTAssertEqualObjects(r.password, [pair componentsJoinedByString:@" / "]);
        XCTAssertEqual(r.migrationStatus, AKCredentialMigrationStatusVerified);
    }
    XCTAssertEqual(K77Items.count, 6u);
    for (NSDictionary *op in [self operations:@"add"]) XCTAssertTrue([op[@"query"][(__bridge id)kSecAttrService] hasPrefix:@"uk.jpsit.telephone.sip:"]);
}
- (void)testLegacyDenialCancellationAndInvalidDataNeverTryTheNewCopy {
    [self seedLegacy];
    for (NSNumber *status in @[@(errSecUserCanceled),@(errSecAuthFailed),@(errSecInteractionNotAllowed),@(errSecNotAvailable)]) {
        [K77Operations removeAllObjects]; [self fault:K77ReadFaults namespace:@"legacy" statuses:@[status]];
        AKCredentialReadResult *r = [self read]; XCTAssertNil(r.password); XCTAssertNotEqual(r.status, AKCredentialReadStatusSuccess);
        XCTAssertEqual(K77Operations.count, 2u); XCTAssertEqualObjects(K77Operations.firstObject[@"query"][(__bridge id)kSecAttrService], K77Clean(K77Service));
        XCTAssertEqualObjects(K77Operations.lastObject[@"query"][(__bridge id)kSecAttrService], K77Legacy(K77Service));
    }
    const unsigned char bytes[]={0xff,0xfe};
    K77Items[@[K77Legacy(K77Service),K77Account]][(__bridge id)kSecValueData]=[NSData dataWithBytes:bytes length:2];
    XCTAssertEqual([self read].status, AKCredentialReadStatusInvalidData);
    XCTAssertEqual([self operations:@"add"].count, 0u);
}
- (void)testBothMissingAndNewOnlyFallbackRemainReadOnly {
    XCTAssertEqual([self read].status, AKCredentialReadStatusMissing); XCTAssertEqual([self operations:@"read"].count, 2u);
    [self seed:@"clean" service:K77Service account:K77Account password:@"new only"];
    XCTAssertEqualObjects([self read].password, @"new only"); XCTAssertEqual(K77Items.count, 1u);
    XCTAssertEqual([self operations:@"add"].count, 0u); XCTAssertEqual([self operations:@"context"].count, 0u);
}
- (void)testExistingMatchingCopyIsVerifiedWithoutMutation {
    [self seedLegacy]; [self seed:@"clean" service:K77Service account:K77Account password:@"synthetic password"];
    NSDictionary *before = [self.clean copy]; XCTAssertEqual([self read].migrationStatus, AKCredentialMigrationStatusVerified);
    XCTAssertEqualObjects(self.clean, before); XCTAssertEqual([self operations:@"add"].count, 0u); XCTAssertEqual([self operations:@"update"].count, 0u);
}
- (void)testCanonicalEntryWinsWithoutReadingOrOverwritingTheRollbackCopy {
    [self seedLegacy]; [self seed:@"clean" service:K77Service account:K77Account password:@"canonical password"];
    AKCredentialReadResult *r = [self read];
    XCTAssertEqual(r.migrationStatus, AKCredentialMigrationStatusVerified);
    XCTAssertEqualObjects(r.password, @"canonical password");
    XCTAssertEqual(K77Operations.count,1u);
    XCTAssertEqualObjects(self.legacy[(__bridge id)kSecValueData],[self data:@"synthetic password"]);
    XCTAssertEqual([self operations:@"update"].count,0u);
    NSError *error; XCTAssertTrue([self save:@"intended replacement" error:&error]); XCTAssertNil(error);
    XCTAssertEqual([self read].migrationStatus,AKCredentialMigrationStatusVerified);
    XCTAssertEqualObjects(self.legacy[(__bridge id)kSecValueData],[self data:@"intended replacement"]);
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData],[self data:@"intended replacement"]);
}
- (void)testSourceContextFailureNeverSubstitutesDefaultACL {
    [self seedLegacy]; K77ContextStatus=errSecAuthFailed;
    AKCredentialReadResult *r=[self read]; XCTAssertEqual(r.migrationStatus, AKCredentialMigrationStatusDeferred);
    XCTAssertEqualObjects(r.password,@"synthetic password"); XCTAssertNil(self.clean);
    XCTAssertEqual([self operations:@"add"].count,0u);
    K77ContextStatus=errSecSuccess; [self read]; XCTAssertNil(self.clean); // Latched until explicit save.
    NSError *error; XCTAssertTrue([self save:@"synthetic password" error:&error]); XCTAssertNotNil(self.clean);
}
- (void)testFailedAddIsLatchedWithoutRepeatedPromptsOrDeletingTheSource {
    [self seedLegacy]; [self fault:K77AddFaults namespace:@"clean" statuses:@[@(errSecUserCanceled)]];
    AKCredentialReadResult *r=[self read]; XCTAssertEqual(r.status,AKCredentialReadStatusCancelled); XCTAssertNil(r.password);
    XCTAssertEqual(r.migrationStatus,AKCredentialMigrationStatusDeferred); XCTAssertEqual(r.migrationSecurityStatus,errSecUserCanceled);
    XCTAssertEqual([self operations:@"add"].count,1u);
    XCTAssertNil([self read].password); XCTAssertNil([self read].password);
    XCTAssertEqual([self operations:@"add"].count,1u); XCTAssertEqual(K77Items.count,1u);
}
- (void)testCanonicalDenialCancellationAndMalformedDataNeverFallBackToLegacy {
    [self seedLegacy]; [self seed:@"clean" service:K77Service account:K77Account password:@"canonical password"];
    for (NSNumber *status in @[@(errSecAuthFailed),@(errSecUserCanceled),@(errSecInteractionNotAllowed),@(errSecNotAvailable)]) {
        [K77Operations removeAllObjects]; [self fault:K77ReadFaults namespace:@"clean" statuses:@[status]];
        AKCredentialReadResult *r=[self read]; XCTAssertNil(r.password); XCTAssertNotEqual(r.status,AKCredentialReadStatusSuccess);
        XCTAssertEqual(K77Operations.count,1u); XCTAssertEqual([self operations:@"add"].count,0u);
        XCTAssertEqualObjects(K77Operations.firstObject[@"query"][(__bridge id)kSecAttrService],K77Clean(K77Service));
    }
    K77Items[@[K77Clean(K77Service),K77Account]][(__bridge id)kSecValueData]=@"wrong payload type";
    XCTAssertEqual([self read].status,AKCredentialReadStatusInvalidData);
    XCTAssertEqual([self operations:@"add"].count,0u);
}
- (void)testDuplicateCreationRaceRequiresReadbackAndNeverOverwrites {
    [self seedLegacy]; K77RaceData=[self data:@"synthetic password"];
    [self fault:K77AddFaults namespace:@"clean" statuses:@[@(errSecDuplicateItem)]];
    XCTAssertEqual([self read].migrationStatus,AKCredentialMigrationStatusVerified);
    XCTAssertEqual([self operations:@"read"].count,4u); XCTAssertEqual([self operations:@"update"].count,0u);
}
- (void)testConflictingDuplicateRaceRetainsBothValuesForReview {
    [self seedLegacy]; K77RaceData=[self data:@"concurrent distinct copy"];
    [self fault:K77AddFaults namespace:@"clean" statuses:@[@(errSecDuplicateItem)]];
    XCTAssertEqual([self read].migrationStatus,AKCredentialMigrationStatusConflict);
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData],[self data:@"concurrent distinct copy"]);
    XCTAssertEqual([self operations:@"update"].count,0u); XCTAssertEqual(K77Items.count,2u);
}
- (void)testReadbackCancellationRetainsBothCopiesAndExplicitSaveRecovers {
    [self seedLegacy]; [self fault:K77ReadFaults namespace:@"clean" statuses:@[@(errSecItemNotFound),@(errSecItemNotFound),@(errSecUserCanceled)]];
    AKCredentialReadResult *r=[self read]; XCTAssertEqual(r.migrationStatus,AKCredentialMigrationStatusDeferred);
    XCTAssertEqual(r.status,AKCredentialReadStatusCancelled); XCTAssertNil(r.password); XCTAssertEqual(K77Items.count,2u);
    NSError *error; XCTAssertTrue([self save:@"synthetic password" error:&error]);
    XCTAssertEqual([self read].migrationStatus,AKCredentialMigrationStatusVerified); XCTAssertEqual(K77Items.count,2u);
}
- (void)testNewPasswordSaveKeepsRollbackCopyAndVerifiesNewNamespace {
    NSError *error; XCTAssertTrue([self save:@"first password" error:&error]); XCTAssertNil(error);
    XCTAssertEqual(K77Items.count,2u); XCTAssertEqualObjects(self.legacy[(__bridge id)kSecValueData],[self data:@"first password"]);
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData],[self data:@"first password"]);
    XCTAssertEqualObjects(self.legacy[(__bridge id)kSecAttrLabel],@"jps Telephone — SIP account (compatibility copy)");
    XCTAssertEqualObjects(K77Operations.firstObject[@"query"][(__bridge id)kSecAttrService],K77Legacy(K77Service));
    XCTAssertNil(K77Operations.firstObject[@"query"][(__bridge id)kSecReturnData]);
    XCTAssertEqualObjects(K77Operations.lastObject[@"query"][(__bridge id)kSecAttrService],K77Clean(K77Service));
}
- (void)testUpdatingBothPasswordsPreservesTheirExistingAccessLists {
    [self seedLegacy]; [self seed:@"clean" service:K77Service account:K77Account password:@"prior"];
    id oldACL=self.legacy[(__bridge id)kSecAttrAccess],newACL=self.clean[(__bridge id)kSecAttrAccess];
    NSError *error; XCTAssertTrue([self save:@"edited password" error:&error]);
    XCTAssertEqual(self.legacy[(__bridge id)kSecAttrAccess],oldACL); XCTAssertEqual(self.clean[(__bridge id)kSecAttrAccess],newACL);
    for (NSDictionary *op in [self operations:@"update"]) {
        XCTAssertNil(op[@"attributes"][(__bridge id)kSecAttrAccess]); XCTAssertNil(op[@"attributes"][(__bridge id)kSecAttrService]);
        XCTAssertNil(op[@"attributes"][(__bridge id)kSecAttrAccount]); XCTAssertNotNil(op[@"query"][(__bridge id)kSecAttrService]);
        XCTAssertNotNil(op[@"query"][(__bridge id)kSecAttrAccount]);
        if ([op[@"query"][(__bridge id)kSecAttrService] isEqual:K77Legacy(K77Service)]) {
            XCTAssertEqual([op[@"query"][(__bridge id)kSecMatchItemList] count],1u);
        } else XCTAssertEqualObjects(op[@"query"][(__bridge id)kSecMatchSearchList],@[K77Keychain]);
    }
}
- (void)testSaveReportsPartialFailureWhenAnotherKeychainShadowsTheSavedCanonicalItem {
    [self seedLegacy];
    K77EarlierCanonicalData = [self data:@"earlier Keychain password"];
    NSData *earlier = [K77EarlierCanonicalData copy];
    id sourceACL = self.legacy[(__bridge id)kSecAttrAccess];
    NSError *error;
    XCTAssertFalse([SearchList77Keychain addItemWithService:K77Service account:K77Account
        password:@"intended replacement" error:&error]);
    XCTAssertEqual(error.code, errSecDecode);
    XCTAssertTrue([error.localizedDescription containsString:@"compatibility password was saved"]);
    XCTAssertEqualObjects(self.legacy[(__bridge id)kSecValueData], [self data:@"intended replacement"]);
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData], [self data:@"intended replacement"]);
    XCTAssertEqual(self.legacy[(__bridge id)kSecAttrAccess], sourceACL);
    XCTAssertEqual(self.clean[(__bridge id)kSecAttrAccess], sourceACL);
    XCTAssertEqualObjects(K77EarlierCanonicalData, earlier);
    AKCredentialReadResult *effective = [SearchList77Keychain readResultForService:K77Service account:K77Account];
    XCTAssertEqualObjects(effective.password, @"earlier Keychain password");
    XCTAssertEqual(effective.migrationStatus, AKCredentialMigrationStatusConflict);
    for (NSDictionary *op in [self operations:@"update"]) {
        if ([op[@"query"][(__bridge id)kSecAttrService] isEqual:K77Clean(K77Service)])
            XCTAssertEqualObjects(op[@"query"][(__bridge id)kSecMatchSearchList], @[K77Keychain]);
    }
    for (NSDictionary *op in [self operations:@"add"])
        XCTAssertEqualObjects(op[@"query"][(__bridge id)kSecUseKeychain], K77Keychain);
}
- (void)testSaveCannotSucceedWhenTheEffectiveCanonicalReadIsUnavailable {
    [self seedLegacy]; K77EarlierCanonicalData = [self data:@"intended replacement"];
    for (NSNumber *failure in @[@(errSecAuthFailed), @(errSecUserCanceled),
                               @(errSecInteractionNotAllowed), @(errSecNotAvailable), @(errSecItemNotFound)]) {
        K77EarlierCanonicalStatus = failure.intValue;
        NSError *error;
        XCTAssertFalse([SearchList77Keychain addItemWithService:K77Service account:K77Account
            password:@"intended replacement" error:&error]);
        XCTAssertEqual(error.code, failure.intValue);
        XCTAssertTrue([error.localizedDescription containsString:@"compatibility password was saved"]);
        NSArray *reads = [self operations:@"read"];
        XCTAssertEqualObjects(reads[reads.count - 2][@"query"][(__bridge id)kSecMatchSearchList], @[K77Keychain]);
        XCTAssertNil(reads.lastObject[@"query"][(__bridge id)kSecMatchSearchList]);
        XCTAssertEqualObjects(reads.lastObject[@"query"][(__bridge id)kSecAttrService], K77Clean(K77Service));
        XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData], [self data:@"intended replacement"]);
    }
}
- (void)testSaveRejectsMalformedEffectiveCanonicalDataWithoutChangingThatItem {
    [self seedLegacy];
    for (id malformed in @[@"wrong payload type", NSNull.null]) {
        K77EarlierCanonicalData = malformed;
        NSError *error;
        XCTAssertFalse([SearchList77Keychain addItemWithService:K77Service account:K77Account
            password:@"intended replacement" error:&error]);
        XCTAssertEqual(error.code, errSecDecode);
        XCTAssertTrue([error.localizedDescription containsString:@"compatibility password was saved"]);
        XCTAssertEqual(K77EarlierCanonicalData, malformed);
    }
}
- (void)testSaveVerifiesBothScopedAndEffectiveCanonicalValuesWhenTheyMatch {
    [self seedLegacy]; K77EarlierCanonicalData = [self data:@"intended replacement"];
    NSError *error;
    XCTAssertTrue([SearchList77Keychain addItemWithService:K77Service account:K77Account
        password:@"intended replacement" error:&error]);
    XCTAssertNil(error);
    NSArray *reads = [self operations:@"read"];
    XCTAssertEqualObjects(reads[reads.count - 2][@"query"][(__bridge id)kSecMatchSearchList], @[K77Keychain]);
    XCTAssertNil(reads.lastObject[@"query"][(__bridge id)kSecMatchSearchList]);
    XCTAssertEqualObjects(reads.lastObject[@"query"][(__bridge id)kSecAttrService], K77Clean(K77Service));
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData], K77EarlierCanonicalData);
}
- (void)testLegacySaveFailureStopsBeforeAnyNewNamespaceAccess {
    [self seedLegacy]; [self fault:K77UpdateFaults namespace:@"legacy" statuses:@[@(errSecAuthFailed)]];
    NSError *error; XCTAssertFalse([self save:@"edited password" error:&error]); XCTAssertEqual(error.code,errSecAuthFailed);
    XCTAssertEqual(K77Operations.count,2u); XCTAssertNil(self.clean);
    XCTAssertEqualObjects(self.legacy[(__bridge id)kSecValueData],[self data:@"synthetic password"]);
}
// Real Security-framework ACL objects only. No keychain/file/credential API.
- (NSArray *)aclEntries:(SecAccessRef)access {
    CFArrayRef entries = NULL;
    XCTAssertEqual(SecAccessCopyACLList(access, &entries), errSecSuccess);
    return CFBridgingRelease(entries);
}
- (id)addACL:(SecAccessRef)access authorizations:(NSArray *)authorizations {
    SecACLRef acl = NULL;
    OSStatus status = SecACLCreateWithSimpleContents(access, NULL, CFSTR("Synthetic ACL fixture"),
        kSecKeychainPromptRequirePassphase, &acl);
    XCTAssertEqual(status, errSecSuccess);
    if (status != errSecSuccess) return nil;
    XCTAssertEqual(SecACLUpdateAuthorizations(acl, (__bridge CFArrayRef)authorizations), errSecSuccess);
    return CFBridgingRelease(acl);
}
- (NSDictionary *)aclContents:(id)entry {
    CFArrayRef applications = NULL; CFStringRef description = NULL; SecKeychainPromptSelector selector;
    XCTAssertEqual(SecACLCopyContents((__bridge SecACLRef)entry, &applications, &description, &selector), errSecSuccess);
    NSArray *authorizations = CFBridgingRelease(SecACLCopyAuthorizations((__bridge SecACLRef)entry));
    return @{@"applications":CFBridgingRelease(applications) ?: NSNull.null,
        @"description":CFBridgingRelease(description) ?: NSNull.null,
        @"selector":@(selector), @"authorizations":authorizations ?: @[]};
}
- (void)testAccessCopyDropsOnlyPerItemManagedBindingsAndRetainsUserPermissions {
    SecAccessRef access = NULL;
    XCTAssertEqual(SecAccessCreate(CFSTR("Synthetic access fixture"), NULL, &access), errSecSuccess);
    NSArray *ordinary = [self aclEntries:access];
    NSMutableArray *contents = [NSMutableArray array];
    for (id acl in ordinary) [contents addObject:[self aclContents:acl]];
    id integrity = [self addACL:access authorizations:@[(__bridge id)kSecACLAuthorizationIntegrity]];
    id partition = [self addACL:access authorizations:@[(__bridge id)kSecACLAuthorizationPartitionID]];
    XCTAssertNotNil(integrity); XCTAssertNotNil(partition);
    XCTAssertEqual([AKKeychain prepareAccessForNewItem:access], errSecSuccess);
    // Removed entries remain as tombstones in a SecAccess snapshot. Neither
    // must advertise a managed tag that destination integrity setup can select.
    for (id managed in @[integrity, partition]) {
        NSArray *rights = CFBridgingRelease(SecACLCopyAuthorizations((__bridge SecACLRef)managed));
        XCTAssertEqualObjects(rights, @[]);
    }
    XCTAssertEqual([AKKeychain prepareAccessForNewItem:access], errSecSuccess);
    for (NSUInteger index = 0; index < ordinary.count; index++)
        XCTAssertEqualObjects([self aclContents:ordinary[index]], contents[index]);
    CFRelease(access);
}
- (void)testAccessCopyLeavesAnOrdinaryAccessPolicyUnchanged {
    SecAccessRef access = NULL;
    XCTAssertEqual(SecAccessCreate(CFSTR("Synthetic access fixture"), NULL, &access), errSecSuccess);
    NSArray *before = [self aclEntries:access];
    XCTAssertEqual([AKKeychain prepareAccessForNewItem:access], errSecSuccess);
    XCTAssertEqualObjects([self aclEntries:access], before);
    CFRelease(access);
}
- (void)testAccessCopyRejectsMixedManagedAndUserPermissionsWithoutEditingThePolicy {
    SecAccessRef access = NULL;
    XCTAssertEqual(SecAccessCreate(CFSTR("Synthetic access fixture"), NULL, &access), errSecSuccess);
    id mixed = [self addACL:access authorizations:@[(__bridge id)kSecACLAuthorizationPartitionID,
        (__bridge id)kSecACLAuthorizationDecrypt]];
    NSArray *before = [self aclEntries:access]; NSDictionary *contents = [self aclContents:mixed];
    XCTAssertEqual([AKKeychain prepareAccessForNewItem:access], errSecParam);
    XCTAssertEqualObjects([self aclEntries:access], before);
    XCTAssertEqualObjects([self aclContents:mixed], contents);
    CFRelease(access);
}
- (void)assertSaveDiagnosticStage:(NSString *)stage status:(OSStatus)status {
    NSError *error;
    XCTAssertFalse([self save:@"private synthetic replacement" error:&error]);
    XCTAssertEqual(error.code, status);
    XCTAssertEqualObjects(error.userInfo[@"AKCredentialSaveStage"], stage);
    NSString *statusText = [NSString stringWithFormat:@"Keychain error %d", (int)status];
    XCTAssertTrue([error.localizedDescription containsString:statusText]);
    for (NSString *privateValue in @[@"private synthetic replacement", K77Service, K77Account, K77Keychain]) {
        XCTAssertFalse([error.description containsString:privateValue], @"Diagnostic exposed a credential or identity");
    }
}
- (void)testSaveDiagnosticIdentifiesCompatibilityWriteFailure {
    [self seedLegacy]; [self fault:K77UpdateFaults namespace:@"legacy" statuses:@[@(errSecAuthFailed)]];
    [self assertSaveDiagnosticStage:@"compatibility-write" status:errSecAuthFailed];
}
- (void)testSaveDiagnosticIdentifiesCompatibilityReadbackFailure {
    [self seedLegacy]; [self fault:K77ReadFaults namespace:@"legacy" statuses:@[@(errSecSuccess), @(errSecUserCanceled)]];
    [self assertSaveDiagnosticStage:@"compatibility-readback" status:errSecUserCanceled];
}
- (void)testSaveDiagnosticIdentifiesPermissionContextFailure {
    [self seedLegacy]; K77ContextStatus = errSecParam;
    [self assertSaveDiagnosticStage:@"access-context" status:errSecParam];
}
- (void)testSaveDiagnosticIdentifiesNewEntryWriteFailure {
    [self seedLegacy]; [self fault:K77AddFaults namespace:@"clean" statuses:@[@(errSecReadOnly)]];
    [self assertSaveDiagnosticStage:@"canonical-write" status:errSecReadOnly];
}
- (void)testSaveDiagnosticIdentifiesNewEntryUpdateFailure {
    [self seedLegacy]; [self seed:@"clean" service:K77Service account:K77Account password:@"previous value"];
    [self fault:K77UpdateFaults namespace:@"clean" statuses:@[@(errSecAuthFailed)]];
    [self assertSaveDiagnosticStage:@"canonical-update" status:errSecAuthFailed];
}
- (void)testSaveDiagnosticIdentifiesNewEntryReadbackFailure {
    [self seedLegacy]; [self fault:K77ReadFaults namespace:@"clean" statuses:@[@(errSecDecode)]];
    [self assertSaveDiagnosticStage:@"canonical-readback" status:errSecDecode];
}
- (void)testSaveDiagnosticIdentifiesEffectiveLookupFailure {
    [self seedLegacy]; [self fault:K77ReadFaults namespace:@"clean" statuses:@[@(errSecSuccess), @(errSecNotAvailable)]];
    [self assertSaveDiagnosticStage:@"effective-readback" status:errSecNotAvailable];
}
- (void)testPartialSaveIsReportedHonestlyAndCanBeRetried {
    [self seedLegacy]; [self fault:K77AddFaults namespace:@"clean" statuses:@[@(errSecReadOnly)]];
    NSError *error; XCTAssertFalse([self save:@"edited password" error:&error]); XCTAssertEqual(error.code,errSecReadOnly);
    XCTAssertTrue([error.localizedDescription containsString:@"compatibility password was saved"]);
    XCTAssertFalse([error.localizedDescription containsString:@"edited password"]);
    XCTAssertEqualObjects(self.legacy[(__bridge id)kSecValueData],[self data:@"edited password"]);
    XCTAssertNil(self.clean); XCTAssertTrue([self save:@"edited password" error:&error]); XCTAssertNil(error);
}
- (void)testCorruptCopyCannotBeReportedAsVerifiedOrSuccessfullySaved {
    [self seedLegacy]; K77CorruptCopy=[self data:@"wrong readback"];
    XCTAssertEqual([self read].migrationStatus,AKCredentialMigrationStatusConflict);
    [K77Items removeObjectForKey:@[K77Clean(K77Service),K77Account]];
    NSError *error; XCTAssertFalse([self save:@"edited password" error:&error]); XCTAssertEqual(error.code,errSecDecode);
    XCTAssertNotNil(self.legacy); XCTAssertNotNil(self.clean);
}
- (void)testEmptyPasswordIsARealCredentialInBothNamespaces {
    [self seed:@"legacy" service:K77Service account:K77Account password:@""];
    AKCredentialReadResult *r=[self read]; XCTAssertEqual(r.status,AKCredentialReadStatusSuccess);
    XCTAssertEqual(r.migrationStatus,AKCredentialMigrationStatusVerified); XCTAssertEqualObjects(r.password,@"");
    NSError *error; XCTAssertTrue([self save:@"" error:&error]); XCTAssertNil(error);
}
- (void)testDeferralAdmissionIsBoundedWithoutDroppingExistingFailures {
    [self seedLegacy]; for (NSUInteger i=0;i<64;i++) K77Deferrals[@[@"synthetic",@(i)]]=@[@(AKCredentialMigrationStatusDeferred),@(errSecAuthFailed)];
    AKCredentialReadResult *r=[self read]; XCTAssertEqual(r.migrationStatus,AKCredentialMigrationStatusDeferred);
    XCTAssertEqual(r.migrationSecurityStatus,errSecAllocate); XCTAssertEqual(K77Deferrals.count,64u);
    XCTAssertEqual(K77Operations.count,2u); XCTAssertNil(self.clean);
}
- (void)testSupersededReadCannotStartAKeychainCopy {
    [self seedLegacy]; __block BOOL admitted=YES;
    K77BeforeRead=^(NSDictionary *query) { admitted=NO; };
    AKCredentialReadResult *r=[Namespace77Keychain readResultForService:K77Service account:K77Account migrationAllowed:^BOOL { return admitted; }];
    XCTAssertEqual(r.status,AKCredentialReadStatusSuperseded); XCTAssertNil(r.password); XCTAssertNil(self.clean);
    XCTAssertEqual(K77Operations.count,1u);
}
- (void)testSupersededAfterNewLookupCannotAddOrVerifyAnotherItem {
    [self seedLegacy]; __block BOOL admitted=YES;
    K77BeforeRead=^(NSDictionary *query) { if ([query[(__bridge id)kSecAttrService] isEqual:K77Clean(K77Service)]) admitted=NO; };
    AKCredentialReadResult *r=[Namespace77Keychain readResultForService:K77Service account:K77Account migrationAllowed:^BOOL { return admitted; }];
    XCTAssertEqual(r.status,AKCredentialReadStatusSuperseded); XCTAssertEqual([self operations:@"add"].count,0u); XCTAssertNil(self.clean);
}
- (void)testBrokerInvalidationPreventsCopyAfterPendingAuthorisedRead {
    [self seedLegacy];
    dispatch_semaphore_t gate=dispatch_semaphore_create(0);
    XCTestExpectation *started=[self expectationWithDescription:@"broker source read pending"];
    XCTestExpectation *superseded=[self expectationWithDescription:@"invalidated completion"];
    XCTestExpectation *finished=[self expectationWithDescription:@"Security reader finished"];
    K77BeforeRead=^(NSDictionary *query) {
        if ([query[(__bridge id)kSecAttrService] isEqual:K77Legacy(K77Service)]) {
            [started fulfill]; dispatch_semaphore_wait(gate,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));
        }
    };
    K77ReadDidFinish=^{ [finished fulfill]; };
    AKCredentialBroker *broker=[[AKCredentialBroker alloc] initWithReader:^AKCredentialReadResult *(NSString *service, NSString *account) {
        XCTFail(@"The injected Security reader must be used");
        return [AKCredentialReadResult failureWithStatus:AKCredentialReadStatusFailure securityStatus:errSecParam];
    }];
    // Same guarded production path as sharedBroker, with the complete Security
    // boundary replaced by the synthetic subclass rather than the real Keychain.
    [broker setValue:Namespace77Keychain.class forKey:@"keychainReaderClass"];
    [broker readPasswordForService:K77Service account:K77Account completion:^(AKCredentialReadResult *result) {
        XCTAssertEqual(result.status,AKCredentialReadStatusSuperseded); XCTAssertNil(result.password); [superseded fulfill];
    }];
    [self waitForExpectations:@[started] timeout:2];
    [broker invalidateService:K77Service account:K77Account];
    [self waitForExpectations:@[superseded] timeout:2];
    dispatch_semaphore_signal(gate);
    [self waitForExpectations:@[finished] timeout:3];
    XCTAssertEqual([self operations:@"add"].count,0u); XCTAssertNil(self.clean); [broker shutdown];
}
- (void)testSaveNeverBlocksMainBehindPendingAuthorisationOrInterleavesWithMigration {
    [self seedLegacy]; dispatch_semaphore_t gate=dispatch_semaphore_create(0);
    XCTestExpectation *started=[self expectationWithDescription:@"synthetic authorised read pending"],*done=[self expectationWithDescription:@"read finished"];
    __block BOOL paused=NO;
    K77BeforeRead=^(NSDictionary *query) {
        if (!paused) { paused=YES; [started fulfill]; dispatch_semaphore_wait(gate,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC)); }
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ [self read]; [done fulfill]; });
    [self waitForExpectations:@[started] timeout:2];
    NSTimeInterval begin=NSProcessInfo.processInfo.systemUptime;
    NSError *error; BOOL saved=[self save:@"must not interleave" error:&error];
    NSTimeInterval elapsed=NSProcessInfo.processInfo.systemUptime-begin;
    dispatch_semaphore_signal(gate); [self waitForExpectations:@[done] timeout:3];
    XCTAssertFalse(saved); XCTAssertEqual(error.code,errSecNotAvailable); XCTAssertLessThan(elapsed,.5);
    XCTAssertEqualObjects(self.legacy[(__bridge id)kSecValueData],[self data:@"synthetic password"]);
    XCTAssertEqualObjects(self.clean[(__bridge id)kSecValueData],[self data:@"synthetic password"]);
}
@end
