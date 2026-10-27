#import <XCTest/XCTest.h>
#import "AKRecordingCatalogue.h"
#include <sys/stat.h>

@interface RecordingCatalogueTests : XCTestCase
@property(nonatomic) NSURL *root;
@end
@implementation RecordingCatalogueTests
- (void)setUp {
    [super setUp];
    self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.root withIntermediateDirectories:YES attributes:nil error:nil]);
}
- (void)tearDown { [NSFileManager.defaultManager removeItemAtURL:self.root error:nil]; [super tearDown]; }
- (NSURL *)store { return [self.root URLByAppendingPathComponent:@"catalogue.plist"]; }
- (NSDictionary *)attachment:(NSString *)call segment:(NSString *)segment state:(NSString *)state {
    NSMutableDictionary *attachment = [@{@"callIdentifier":call, @"segmentIdentifier":segment, @"state":state,
                                         @"created":[NSDate dateWithTimeIntervalSince1970:42]} mutableCopy];
    if ([state isEqual:@"available"]) {
        attachment[@"destination"] = @"/synthetic/recording.ogg";
        attachment[@"outputBookmark"] = [@"synthetic-bookmark" dataUsingEncoding:NSUTF8StringEncoding];
        attachment[@"outputIdentity"] = @{@"device":@1, @"inode":@2, @"size":@64};
    }
    return attachment;
}
- (void)persist:(NSDictionary *)attachment catalogue:(AKRecordingCatalogue *)catalogue succeeds:(BOOL)expected {
    XCTestExpectation *done = [self expectationWithDescription:@"catalogue mutation"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil; BOOL result = [catalogue persistAttachment:attachment error:&error];
        XCTAssertEqual(result, expected); if (expected) XCTAssertNil(error); else XCTAssertNotNil(error);
        dispatch_async(dispatch_get_main_queue(), ^{ [done fulfill]; });
    });
    [self waitForExpectations:@[done] timeout:3];
}
- (void)refresh:(AKRecordingCatalogue *)catalogue succeeds:(BOOL)expected {
    XCTestExpectation *done = [self expectationWithDescription:@"catalogue refresh"];
    [catalogue refreshWithCompletion:^(BOOL loaded) { XCTAssertTrue(NSThread.isMainThread); XCTAssertEqual(loaded, expected); [done fulfill]; }];
    [self waitForExpectations:@[done] timeout:3];
}
- (NSData *)encoded:(NSArray *)attachments version:(id)version {
    return [NSPropertyListSerialization dataWithPropertyList:@{@"version":version, @"attachments":attachments}
                                                     format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
}
- (void)testConstructionAndCachedQueriesPerformNoIOAndRefreshPublishesOnMain {
    __block NSUInteger reads = 0, writes = 0;
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) {
        XCTAssertFalse(NSThread.isMainThread); reads++; return nil;
    } writer:^BOOL(NSURL *url, NSData *data, NSError **error) { writes++; return YES; }];
    XCTAssertFalse(catalogue.hasLoaded); XCTAssertEqual(catalogue.attachments.count, 0u);
    XCTAssertEqual([catalogue attachmentsForCallIdentifier:@"unknown"].count, 0u); XCTAssertNil([catalogue attachmentForCallIdentifier:@"call" segmentIdentifier:@"segment"]);
    XCTAssertEqual(reads, 0u); XCTAssertEqual(writes, 0u);
    catalogue.stateDidChange = ^{ XCTAssertTrue(NSThread.isMainThread); };
    [self refresh:catalogue succeeds:YES]; XCTAssertTrue(catalogue.hasLoaded); XCTAssertFalse(catalogue.isRefreshing); XCTAssertEqual(reads, 1u);
    for (NSUInteger index = 0; index < 1000; index++) [catalogue attachmentsForCallIdentifier:@"unknown"];
    XCTAssertEqual(reads, 1u); XCTAssertEqual(writes, 0u);
}
- (void)testExactIdentityUpsertsPreserveOtherCallsSegmentsAndUnknownMetadataAfterRestart {
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store];
    NSMutableDictionary *one = [[self attachment:@"call-a" segment:@"segment-a" state:@"capturing"] mutableCopy];
    one[@"futureMetadata"] = @{@"nested":@[@"preserved", @7], @"journalProof":[@"proof" dataUsingEncoding:NSUTF8StringEncoding]};
    [self persist:one catalogue:catalogue succeeds:YES];
    [self persist:[self attachment:@"call-a" segment:@"segment-b" state:@"failed"] catalogue:catalogue succeeds:YES];
    [self persist:[self attachment:@"call-b" segment:@"segment-a" state:@"finalising"] catalogue:catalogue succeeds:YES];
    one[@"state"] = @"available"; one[@"destination"] = @"/synthetic/recording.wav";
    one[@"outputBookmark"] = [@"bookmark" dataUsingEncoding:NSUTF8StringEncoding]; one[@"outputIdentity"] = @{@"inode":@123};
    [self persist:one catalogue:catalogue succeeds:YES];
    AKRecordingCatalogue *restarted = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store]; [self refresh:restarted succeeds:YES];
    XCTAssertEqual(restarted.attachments.count, 3u); XCTAssertEqual([restarted attachmentsForCallIdentifier:@"call-a"].count, 2u);
    NSDictionary *loaded = [restarted attachmentForCallIdentifier:@"call-a" segmentIdentifier:@"segment-a"];
    XCTAssertEqualObjects(loaded[@"state"], @"available"); XCTAssertEqualObjects(loaded[@"futureMetadata"], one[@"futureMetadata"]);
    XCTAssertEqualObjects([restarted attachmentForCallIdentifier:@"call-b" segmentIdentifier:@"segment-a"][@"state"], @"finalising");
}
- (void)testMutableCallerObjectsCannotAlterQueuedOrCachedMetadata {
    __block NSData *stored;
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) { return stored; }
        writer:^BOOL(NSURL *url, NSData *data, NSError **error) { stored = data; return YES; }];
    NSMutableArray *values = [NSMutableArray arrayWithObject:@"original"];
    NSMutableDictionary *attachment = [[self attachment:@"call" segment:@"segment" state:@"capturing"] mutableCopy]; attachment[@"values"] = values;
    [self persist:attachment catalogue:catalogue succeeds:YES];
    [values addObject:@"changed"]; attachment[@"state"] = @"failed";
    NSDictionary *loaded = [catalogue attachmentForCallIdentifier:@"call" segmentIdentifier:@"segment"];
    XCTAssertEqualObjects(loaded[@"state"], @"capturing"); XCTAssertEqual([loaded[@"values"] count], 1u);
    XCTAssertFalse([loaded isKindOfClass:NSMutableDictionary.class]); XCTAssertFalse([loaded[@"values"] isKindOfClass:NSMutableArray.class]);
}
- (void)testUnreadableStoreDoesNotInvokeWriterAndRetainsPendingMutation {
    __block BOOL unreadable = YES; __block NSUInteger writes = 0; __block NSData *stored;
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) {
        if (unreadable) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:nil]; return nil; } return stored;
    } writer:^BOOL(NSURL *url, NSData *data, NSError **error) { writes++; stored = data; return YES; }];
    [self persist:[self attachment:@"call" segment:@"segment" state:@"available"] catalogue:catalogue succeeds:NO];
    XCTAssertEqual(writes, 0u); XCTAssertEqual(catalogue.pendingMutationCount, 1u); XCTAssertEqual(catalogue.attachments.count, 0u); XCTAssertFalse(catalogue.hasLoaded);
    unreadable = NO;
    XCTestExpectation *done = [self expectationWithDescription:@"retry"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ XCTAssertTrue([catalogue retryPendingMutationsWithError:nil]); dispatch_async(dispatch_get_main_queue(), ^{ [done fulfill]; }); });
    [self waitForExpectations:@[done] timeout:3]; XCTAssertEqual(writes, 1u); XCTAssertEqual(catalogue.pendingMutationCount, 0u); XCTAssertNil(catalogue.error);
    XCTAssertEqualObjects(catalogue.attachments.firstObject[@"state"], @"available");
}
- (void)testFailedWriteKeepsLastDurableSnapshotAndQueuedLatestMutation {
    __block BOOL fail = NO; __block NSData *stored;
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) { return stored; }
        writer:^BOOL(NSURL *url, NSData *data, NSError **error) { if (fail) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOSPC userInfo:nil]; return NO; } stored = data; return YES; }];
    [self persist:[self attachment:@"call" segment:@"segment" state:@"capturing"] catalogue:catalogue succeeds:YES]; fail = YES;
    [self persist:[self attachment:@"call" segment:@"segment" state:@"finalising"] catalogue:catalogue succeeds:NO];
    [self persist:[self attachment:@"call" segment:@"segment" state:@"available"] catalogue:catalogue succeeds:NO];
    XCTAssertEqual(catalogue.pendingMutationCount, 1u); XCTAssertEqualObjects(catalogue.attachments.firstObject[@"state"], @"capturing"); XCTAssertEqual(catalogue.error.code, ENOSPC);
    [self refresh:catalogue succeeds:YES];
    XCTAssertEqual(catalogue.error.code, ENOSPC); XCTAssertEqual(catalogue.pendingMutationCount, 1u);
    XCTAssertEqualObjects(catalogue.attachments.firstObject[@"state"], @"capturing");
    fail = NO;
    [self persist:[self attachment:@"other" segment:@"another" state:@"failed"] catalogue:catalogue succeeds:YES];
    XCTAssertEqual(catalogue.attachments.count, 2u); XCTAssertEqual(catalogue.pendingMutationCount, 0u);
    XCTAssertEqualObjects([catalogue attachmentForCallIdentifier:@"call" segmentIdentifier:@"segment"][@"state"], @"available");
}
- (void)testMalformedAndUnsupportedStoreNeverOverwritten {
    NSArray *invalidStores = @[[NSData data], [@"not a property list" dataUsingEncoding:NSUTF8StringEncoding],
                              [self encoded:@[] version:@2], [self encoded:@[] version:@YES],
                              [self encoded:@[@{@"callIdentifier":@"call"}] version:@1]];
    for (NSData *invalid in invalidStores) {
        __block NSUInteger writes = 0;
        AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) { return invalid; }
            writer:^BOOL(NSURL *url, NSData *data, NSError **error) { writes++; return YES; }];
        [self persist:[self attachment:@"call" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:NO];
        XCTAssertEqual(writes, 0u); XCTAssertEqual(catalogue.attachments.count, 0u); XCTAssertNotNil(catalogue.error);
    }
}
- (void)testDuplicateStoredIdentityIsRejectedAsCorrupt {
    NSDictionary *attachment = [self attachment:@"call" segment:@"segment" state:@"capturing"];
    NSData *duplicated = [self encoded:@[attachment, attachment] version:@1]; __block NSUInteger writes = 0;
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) { return duplicated; }
        writer:^BOOL(NSURL *url, NSData *data, NSError **error) { writes++; return YES; }];
    [self persist:[self attachment:@"other" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:NO]; XCTAssertEqual(writes, 0u);
}
- (void)testFailedRefreshRetainsLoadedAttachmentAndError {
    __block BOOL fail = NO; NSData *good = [self encoded:@[[self attachment:@"call" segment:@"segment" state:@"available"]] version:@1];
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) {
        if (fail) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:nil]; return nil; } return good;
    } writer:^BOOL(NSURL *url, NSData *data, NSError **error) { XCTFail(@"Refresh must not write"); return NO; }];
    [self refresh:catalogue succeeds:YES]; fail = YES; [self refresh:catalogue succeeds:NO];
    XCTAssertTrue(catalogue.hasLoaded); XCTAssertEqual(catalogue.attachments.count, 1u); XCTAssertEqual(catalogue.error.code, EIO);
}
- (void)testInvalidIdentitiesStatePropertyListAndUnprovedAvailableAreRejected {
    NSArray *invalid = @[@{}, @{@"callIdentifier":@1, @"segmentIdentifier":@"segment", @"state":@"failed"},
        @{@"callIdentifier":@"call", @"segmentIdentifier":@"", @"state":@"failed"},
        @{@"callIdentifier":@"call", @"segmentIdentifier":@"segment", @"state":@"other"},
        @{@"callIdentifier":@"call", @"segmentIdentifier":@"segment", @"state":@"available"},
        @{@"callIdentifier":@"call", @"segmentIdentifier":@"segment", @"state":@"capturing", @"invalid":NSNull.null}];
    __block NSUInteger reads = 0, writes = 0;
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store reader:^NSData *(NSURL *url, NSError **error) { reads++; return nil; }
        writer:^BOOL(NSURL *url, NSData *data, NSError **error) { writes++; return YES; }];
    for (NSDictionary *attachment in invalid) [self persist:attachment catalogue:catalogue succeeds:NO];
    XCTAssertEqual(reads, 0u); XCTAssertEqual(writes, 0u); XCTAssertEqual(catalogue.pendingMutationCount, 0u);
}
- (void)testSerialConcurrentMutationsKeepEveryIndependentSegment {
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store];
    XCTestExpectation *done = [self expectationWithDescription:@"concurrent mutations"];
    dispatch_group_t group = dispatch_group_create();
    for (NSUInteger index = 0; index < 24; index++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *segment = [NSString stringWithFormat:@"segment-%lu", (unsigned long)index];
            NSError *error; XCTAssertTrue([catalogue persistAttachment:[self attachment:@"call" segment:segment state:@"failed"] error:&error]); XCTAssertNil(error);
        });
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ [done fulfill]; });
    [self waitForExpectations:@[done] timeout:5]; [self refresh:catalogue succeeds:YES]; XCTAssertEqual(catalogue.attachments.count, 24u);
}
- (void)testSeparateInstancesAtSameStoreSerializeReadModifyWriteTransactions {
    AKRecordingCatalogue *one = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store];
    AKRecordingCatalogue *two = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store];
    XCTestExpectation *done = [self expectationWithDescription:@"two-instance mutations"];
    dispatch_group_t group = dispatch_group_create();
    for (NSUInteger index = 0; index < 24; index++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            AKRecordingCatalogue *target = index % 2 == 0 ? one : two;
            NSString *segment = [NSString stringWithFormat:@"segment-%lu", (unsigned long)index];
            NSError *error = nil;
            XCTAssertTrue([target persistAttachment:[self attachment:@"call" segment:segment state:@"failed"] error:&error]); XCTAssertNil(error);
        });
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ [done fulfill]; });
    [self waitForExpectations:@[done] timeout:5]; [self refresh:one succeeds:YES]; [self refresh:two succeeds:YES];
    XCTAssertEqual(one.attachments.count, 24u); XCTAssertEqualObjects(one.attachments, two.attachments);
}
- (void)testExistingCorruptDiskFileAndSymlinkArePreserved {
    NSData *damaged = [@"keep damaged bytes" dataUsingEncoding:NSUTF8StringEncoding]; XCTAssertTrue([damaged writeToURL:self.store options:0 error:nil]);
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store];
    [self persist:[self attachment:@"call" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:NO]; XCTAssertEqualObjects([NSData dataWithContentsOfURL:self.store], damaged);
    [NSFileManager.defaultManager removeItemAtURL:self.store error:nil];
    NSURL *target = [self.root URLByAppendingPathComponent:@"target"]; XCTAssertTrue([damaged writeToURL:target options:0 error:nil]);
    XCTAssertTrue([NSFileManager.defaultManager createSymbolicLinkAtURL:self.store withDestinationURL:target error:nil]);
    [self persist:[self attachment:@"call" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:NO];
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:target], damaged); XCTAssertNotNil([NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:self.store.path error:nil]);
}
- (void)testDefaultDiskTransactionRejectsSymlinkDirectoryAndInsecureSiblingLocks {
    NSURL *lock = [NSURL fileURLWithPath:[self.store.path stringByAppendingString:@".lock"]];
    NSURL *foreign = [self.root URLByAppendingPathComponent:@"foreign"];
    NSData *foreignData = [@"foreign bytes" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([foreignData writeToURL:foreign options:0 error:nil]);
    XCTAssertTrue([NSFileManager.defaultManager createSymbolicLinkAtURL:lock withDestinationURL:foreign error:nil]);
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store];
    [self persist:[self attachment:@"call" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:NO];
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:foreign], foreignData); XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:self.store.path]);
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:lock error:nil]);
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:lock withIntermediateDirectories:NO attributes:nil error:nil]);
    [self persist:[self attachment:@"call" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:NO];
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:lock error:nil]);
    XCTAssertTrue([NSData.data writeToURL:lock options:0 error:nil]); XCTAssertEqual(chmod(lock.fileSystemRepresentation, 0644), 0);
    [self persist:[self attachment:@"call" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:NO];
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:self.store.path]);
    XCTAssertEqual(chmod(lock.fileSystemRepresentation, 0600), 0);
    [self persist:[self attachment:@"call" segment:@"segment" state:@"failed"] catalogue:catalogue succeeds:YES];
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:lock.path]);
    struct stat info; XCTAssertEqual(lstat(lock.fileSystemRepresentation, &info), 0); XCTAssertEqual(info.st_mode & 0777, 0600);
}
- (void)testIdentityKeyCannotCollideAcrossAmbiguousConcatenations {
    AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:self.store];
    [self persist:[self attachment:@"a" segment:@"bc" state:@"capturing"] catalogue:catalogue succeeds:YES];
    [self persist:[self attachment:@"ab" segment:@"c" state:@"failed"] catalogue:catalogue succeeds:YES];
    XCTAssertEqual(catalogue.attachments.count, 2u); XCTAssertEqualObjects([catalogue attachmentForCallIdentifier:@"a" segmentIdentifier:@"bc"][@"state"], @"capturing");
    XCTAssertEqualObjects([catalogue attachmentForCallIdentifier:@"ab" segmentIdentifier:@"c"][@"state"], @"failed");
}
@end
