#import <Foundation/Foundation.h>
#import "AKRecordingCatalogue.h"
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 5) return 2;
        NSString *store = [NSString stringWithUTF8String:argv[1]], *prefix = [NSString stringWithUTF8String:argv[2]];
        NSString *barrier = [NSString stringWithUTF8String:argv[3]]; NSInteger count = [[NSString stringWithUTF8String:argv[4]] integerValue];
        NSString *ready = [barrier stringByAppendingFormat:@".ready.%@", prefix];
        if (![NSData.data writeToFile:ready atomically:NO]) return 3;
        for (NSUInteger attempt = 0; access(barrier.fileSystemRepresentation, F_OK) != 0; attempt++) { if (attempt >= 5000) return 4; usleep(1000); }
        AKRecordingCatalogue *catalogue = [[AKRecordingCatalogue alloc] initWithStoreURL:[NSURL fileURLWithPath:store]];
        for (NSInteger index = 0; index < count; index++) {
            NSString *segment = [NSString stringWithFormat:@"%@-%ld", prefix, (long)index];
            NSError *error = nil;
            if (![catalogue persistAttachment:@{@"callIdentifier":prefix, @"segmentIdentifier":segment, @"state":@"failed"} error:&error]) {
                fprintf(stderr, "%s\n", error.description.UTF8String); return 5;
            }
            usleep(1000);
        }
        return 0;
    }
}
