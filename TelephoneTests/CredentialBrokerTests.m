#import <XCTest/XCTest.h>
#import "AKKeychain.h"

@interface AKKeychain (Credential73SecuritySeam)
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
    XCTAssertEqualObjects(Credential73LastQuery[(__bridge id)kSecAttrService], @"jps Telephone 1.7.2 blue icon v4: SIP: synthetic.invalid");
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
