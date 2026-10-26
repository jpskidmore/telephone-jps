#import <XCTest/XCTest.h>
#import "AKStereoRecording.h"
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

@interface RecordingRecoveryMetadataTests : XCTestCase
@property(nonatomic) NSURL *root, *scratch;
@end
@implementation RecordingRecoveryMetadataTests
- (void)setUp {
    [super setUp];
    self.scratch = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    self.root = [self.scratch URLByAppendingPathComponent:@"Recovery" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:self.scratch withIntermediateDirectories:YES attributes:nil error:nil]);
}
- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:self.scratch error:nil];
    [super tearDown];
}
- (NSURL *)makeJob:(NSString *)filename bytes:(NSUInteger)bytes date:(NSDate *)date {
    NSError *error = nil;
    NSURL *directory = AKCreateRecordingRecoveryDirectoryAtRoot(self.root, &error);
    XCTAssertNotNil(directory); XCTAssertNil(error);
    NSURL *local = [directory URLByAppendingPathComponent:@"local.wav"], *remote = [directory URLByAppendingPathComponent:@"remote.wav"];
    XCTAssertTrue([[NSMutableData dataWithLength:bytes] writeToURL:local atomically:YES]);
    XCTAssertTrue([[NSMutableData dataWithLength:bytes + 1] writeToURL:remote atomically:YES]);
    XCTAssertTrue(AKPersistRecordingRecoveryJob(directory, local, remote, [self.scratch URLByAppendingPathComponent:filename], &error));
    NSURL *manifestURL = [directory URLByAppendingPathComponent:@"recovery.plist"];
    NSMutableDictionary *manifest = [[NSDictionary dictionaryWithContentsOfURL:manifestURL] mutableCopy];
    manifest[@"created"] = date;
    XCTAssertTrue([manifest writeToURL:manifestURL atomically:YES]);
    return directory;
}
- (NSDictionary *)jobAt:(NSURL *)directory {
    NSError *error = nil;
    NSArray *jobs = AKRecordingRecoveryJobsAtRootWithError(self.root, &error);
    XCTAssertNil(error); XCTAssertNotNil(jobs);
    for (NSDictionary *job in jobs) if ([job[@"directoryURL"] isEqual:directory.URLByResolvingSymlinksInPath.standardizedURL]) return job;
    XCTFail(@"Missing chosen synthetic recording %@", directory.lastPathComponent); return nil;
}
- (void)testAbsentRootIsEmptyButNonDirectoryRootHasAnError {
    NSError *error = nil;
    XCTAssertEqual(AKRecordingRecoveryJobsAtRootWithError(self.root, &error).count, 0u); XCTAssertNil(error);
    XCTAssertTrue([[@"not a directory" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:self.root atomically:YES]);
    XCTAssertNil(AKRecordingRecoveryJobsAtRootWithError(self.root, &error)); XCTAssertNotNil(error);
}
- (void)testUnreadableRootAndManifestReportFailureRatherThanEmpty {
    NSURL *directory = [self makeJob:@"Retained.wav" bytes:5 date:NSDate.date];
    NSError *error = nil;
    XCTAssertNotEqual(geteuid(), 0u, @"This permission fixture requires an ordinary local test user");
    XCTAssertEqual(chmod(self.root.fileSystemRepresentation, 0000), 0);
    @try {
        XCTAssertNil(AKRecordingRecoveryJobsAtRootWithError(self.root, &error)); XCTAssertNotNil(error);
    } @finally { XCTAssertEqual(chmod(self.root.fileSystemRepresentation, 0700), 0); }
    NSURL *manifest = [directory URLByAppendingPathComponent:@"recovery.plist"];
    XCTAssertEqual(chmod(manifest.fileSystemRepresentation, 0000), 0); error = nil;
    @try {
        XCTAssertNil(AKRecordingRecoveryJobsAtRootWithError(self.root, &error)); XCTAssertNotNil(error);
    } @finally { XCTAssertEqual(chmod(manifest.fileSystemRepresentation, 0600), 0); }
    error = nil;
    XCTAssertEqual(AKRecordingRecoveryJobsAtRootWithError(self.root, &error).count, 1u); XCTAssertNil(error);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"local.wav"]], [NSMutableData dataWithLength:5]);
}
- (void)testMetadataIdentifiesEachJobAndCountsOnlyRetainedTracks {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000];
    NSURL *directory = [self makeJob:@"Synthetic caller.wav" bytes:17 date:date];
    XCTAssertTrue([[NSMutableData dataWithLength:1000] writeToURL:[directory URLByAppendingPathComponent:@"unrelated.bin"] atomically:YES]);
    NSDictionary *job = [self jobAt:directory];
    XCTAssertEqualObjects(job[@"title"], @"Synthetic caller.wav"); XCTAssertEqualObjects(job[@"created"], date);
    XCTAssertEqualObjects(job[@"retainedRawBytes"], @35); XCTAssertGreaterThan([job[@"directoryIdentity"] length], 0u);
    XCTAssertTrue([job[@"phase"] isKindOfClass:NSString.class]); XCTAssertGreaterThan([job[@"lastErrorDescription"] length], 0u);
    XCTAssertEqualObjects([self jobAt:directory][@"directoryIdentity"], job[@"directoryIdentity"]);
}
- (void)testMalformedManifestStillIdentifiesSafeOrphanTracksWithoutInventingError {
    NSURL *directory = [self makeJob:@"Before.wav" bytes:4 date:NSDate.date];
    XCTAssertTrue([[@"damaged metadata" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[directory URLByAppendingPathComponent:@"recovery.plist"] atomically:YES]);
    NSDictionary *job = [self jobAt:directory];
    XCTAssertTrue([job[@"needsNewDestination"] boolValue]); XCTAssertEqualObjects(job[@"retainedRawBytes"], @9);
    XCTAssertTrue([job[@"created"] isKindOfClass:NSDate.class]); XCTAssertNil(job[@"lastError"]);
    XCTAssertGreaterThan([job[@"lastErrorDescription"] length], 0u);
}
- (void)testEnumerationHasAStableOrderAcrossRepeatedScans {
    [self makeJob:@"Later.wav" bytes:2 date:[NSDate dateWithTimeIntervalSince1970:2000]];
    [self makeJob:@"Earlier.wav" bytes:3 date:[NSDate dateWithTimeIntervalSince1970:1000]];
    NSError *error = nil;
    NSArray *first = AKRecordingRecoveryJobsAtRootWithError(self.root, &error);
    NSArray *second = AKRecordingRecoveryJobsAtRootWithError(self.root, &error);
    XCTAssertEqualObjects([first valueForKey:@"directoryIdentity"], [second valueForKey:@"directoryIdentity"]);
    XCTAssertEqual(first.count, 2u);
}
- (void)testActualKnownExportErrorSurvivesRediscovery {
    NSURL *directory = [self makeJob:@"Denied.wav" bytes:2 date:NSDate.date];
    NSError *original = [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:@{NSLocalizedDescriptionKey:@"Synthetic write denial"}];
    XCTestExpectation *notification = [self expectationForNotification:AKRecordingExportDidFailNotification object:nil handler:^BOOL(NSNotification *note) {
        return [note.userInfo[@"recoveryDirectoryURL"] isEqual:directory];
    }];
    AKReportRecordingExportFailure(directory, [self.scratch URLByAppendingPathComponent:@"Denied.wav"], original);
    [self waitForExpectations:@[notification] timeout:3];
    NSDictionary *job = [self jobAt:directory]; NSError *remembered = job[@"lastError"];
    XCTAssertEqualObjects(remembered.domain, original.domain); XCTAssertEqual(remembered.code, original.code);
    XCTAssertTrue([job[@"lastErrorDescription"] containsString:@"Synthetic write denial"]);
}
- (void)testDiscardOnlyTheChosenUnownedJob {
    NSURL *chosen = [self makeJob:@"Chosen.wav" bytes:2 date:NSDate.date];
    NSURL *other = [self makeJob:@"Keep.wav" bytes:3 date:NSDate.date];
    NSDictionary *snapshot = [self jobAt:chosen]; NSError *error = nil;
    XCTAssertTrue(AKDiscardPendingRecordingRecoveryJob(snapshot, &error)); XCTAssertNil(error);
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:chosen.path]);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[other URLByAppendingPathComponent:@"local.wav"].path]);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRootWithError(self.root, &error).count, 1u);
}
- (void)testDiscardRejectsOwnedAndMissingIdentitySnapshotsWithoutDeletingTracks {
    NSURL *directory = [self makeJob:@"Busy.wav" bytes:5 date:NSDate.date]; NSDictionary *snapshot = [self jobAt:directory];
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil); XCTAssertNotNil(owner); NSError *error = nil;
    XCTAssertFalse(AKDiscardPendingRecordingRecoveryJob(snapshot, &error)); XCTAssertNotNil(error);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"local.wav"].path]);
    owner = nil;
    NSMutableDictionary *missing = [snapshot mutableCopy]; [missing removeObjectForKey:@"directoryIdentity"]; error = nil;
    XCTAssertFalse(AKDiscardPendingRecordingRecoveryJob(missing, &error)); XCTAssertNotNil(error);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:directory.path]);
}
- (void)testDiscardRejectsAReplacedDirectoryAtTheSamePath {
    NSURL *directory = [self makeJob:@"Old.wav" bytes:2 date:NSDate.date]; NSDictionary *snapshot = [self jobAt:directory];
    NSURL *retired = [self.root URLByAppendingPathComponent:@"Retired" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager moveItemAtURL:directory toURL:retired error:nil]);
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:nil]);
    NSData *keep = [@"replacement raw" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([keep writeToURL:[directory URLByAppendingPathComponent:@"local.wav"] atomically:YES]);
    XCTAssertTrue([keep writeToURL:[directory URLByAppendingPathComponent:@"remote.wav"] atomically:YES]);
    NSError *error = nil; XCTAssertFalse(AKDiscardPendingRecordingRecoveryJob(snapshot, &error)); XCTAssertNotNil(error);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"local.wav"]], keep);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:retired.path]);
}
- (void)testDiscardRejectsSymlinkJobAndNeverTouchesItsTarget {
    NSURL *directory = [self makeJob:@"Real.wav" bytes:6 date:NSDate.date]; NSDictionary *snapshot = [self jobAt:directory];
    NSURL *alias = [self.root URLByAppendingPathComponent:@"Alias" isDirectory:YES];
    XCTAssertEqual(symlink(directory.fileSystemRepresentation, alias.fileSystemRepresentation), 0);
    NSMutableDictionary *forged = [snapshot mutableCopy]; forged[@"directoryURL"] = alias; NSError *error = nil;
    XCTAssertFalse(AKDiscardPendingRecordingRecoveryJob(forged, &error)); XCTAssertNotNil(error);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"local.wav"].path]);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRootWithError(self.root, &error).count, 1u);
}
- (void)testDiscardFailureRestoresChosenDirectoryAndRetainsRawTracks {
    NSURL *directory = [self makeJob:@"Keep on failure.wav" bytes:6 date:NSDate.date]; NSDictionary *snapshot = [self jobAt:directory];
    NSURL *nested = [directory URLByAppendingPathComponent:@"unexpected" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:nested withIntermediateDirectories:NO attributes:nil error:nil]);
    NSError *error = nil; XCTAssertFalse(AKDiscardPendingRecordingRecoveryJob(snapshot, &error)); XCTAssertNotNil(error);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"local.wav"].path]);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"remote.wav"].path]);
    XCTAssertEqual(AKRecordingRecoveryJobsAtRootWithError(self.root, &error).count, 1u);
}
- (void)testActiveClaimAndCompletedJobStayOutsideRecoveryAndCannotBeDiscarded {
    NSURL *directory = [self makeJob:@"Finished.wav" bytes:2 date:NSDate.date]; NSDictionary *snapshot = [self jobAt:directory];
    AKRecordingJobOwnership *owner = AKClaimRecordingJob(directory, nil); NSError *error = nil;
    XCTAssertEqual(AKRecordingRecoveryJobsAtRootWithError(self.root, &error).count, 0u);
    XCTAssertFalse(AKDiscardPendingRecordingRecoveryJob(snapshot, &error));
    owner = nil;
    NSURL *manifestURL = [directory URLByAppendingPathComponent:@"recovery.plist"];
    NSMutableDictionary *manifest = [[NSDictionary dictionaryWithContentsOfURL:manifestURL] mutableCopy];
    manifest[@"version"] = @2; manifest[@"state"] = @"completed"; XCTAssertTrue([manifest writeToURL:manifestURL atomically:YES]);
    error = nil; XCTAssertEqual(AKRecordingRecoveryJobsAtRootWithError(self.root, &error).count, 0u);
    XCTAssertFalse(AKDiscardPendingRecordingRecoveryJob(snapshot, &error)); XCTAssertNotNil(error);
    XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:directory.path]);
}
@end
