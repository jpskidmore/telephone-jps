#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "AKNetworkReachability.h"
#import "NameServers.h"

// Each injected handle is inert. No real SC registration, run-loop mutation,
// DNS/reachability query or native release occurs in this fixture.
static char reachMarker, storeMarker, sourceMarker;
static int step, reachReleases, storeReleases, sourceReleases;
static int schedules, unschedules, adds, removes, notifications, sourceCreates, afterRelease;
static void Require(BOOL value, NSString *reason) { NSCAssert(value, @"%@", reason); }
SCNetworkReachabilityRef TestReachabilityCreateName(CFAllocatorRef allocator, const char *name) {
    return step == 0 ? NULL : (SCNetworkReachabilityRef)&reachMarker;
}
SCNetworkReachabilityRef TestReachabilityCreateAddress(CFAllocatorRef allocator, const struct sockaddr *address) {
    return step == 0 ? NULL : (SCNetworkReachabilityRef)&reachMarker;
}
Boolean TestReachabilityCallback(SCNetworkReachabilityRef handle, SCNetworkReachabilityCallBack callback, SCNetworkReachabilityContext *context) {
    Require(handle == (SCNetworkReachabilityRef)&reachMarker, @"Callback needs an owned nonnull handle");
    return step != 1;
}
Boolean TestReachabilitySchedule(SCNetworkReachabilityRef handle, CFRunLoopRef loop, CFStringRef mode) {
    Require(handle == (SCNetworkReachabilityRef)&reachMarker, @"Schedule needs an owned nonnull handle"); schedules++;
    return step != 2;
}
Boolean TestReachabilityUnschedule(SCNetworkReachabilityRef handle, CFRunLoopRef loop, CFStringRef mode) {
    Require(handle == (SCNetworkReachabilityRef)&reachMarker, @"Unschedule needs an owned nonnull handle");
    unschedules++; if (reachReleases) afterRelease++;
    return true;
}
SCDynamicStoreRef TestStoreCreate(CFAllocatorRef allocator, CFStringRef name, SCDynamicStoreCallBack callback, SCDynamicStoreContext *context) {
    return step == 0 ? NULL : (SCDynamicStoreRef)&storeMarker;
}
Boolean TestStoreNotifications(SCDynamicStoreRef handle, CFArrayRef keys, CFArrayRef patterns) {
    Require(handle == (SCDynamicStoreRef)&storeMarker && !storeReleases, @"Keys need an owned nonnull store");
    notifications++; return step != 1;
}
CFRunLoopSourceRef TestStoreSource(CFAllocatorRef allocator, SCDynamicStoreRef handle, CFIndex order) {
    Require(handle == (SCDynamicStoreRef)&storeMarker && !storeReleases, @"Source creation needs an owned store");
    sourceCreates++; return step == 2 ? NULL : (CFRunLoopSourceRef)&sourceMarker;
}
void TestAddSource(CFRunLoopRef loop, CFRunLoopSourceRef source, CFRunLoopMode mode) {
    Require(source == (CFRunLoopSourceRef)&sourceMarker && !sourceReleases, @"Add needs owned nonnull source"); adds++;
}
void TestRemoveSource(CFRunLoopRef loop, CFRunLoopSourceRef source, CFRunLoopMode mode) {
    Require(source == (CFRunLoopSourceRef)&sourceMarker && !sourceReleases, @"Remove must precede release"); removes++;
}
CFPropertyListRef TestStoreCopyValue(SCDynamicStoreRef handle, CFStringRef key) {
    Require(handle == (SCDynamicStoreRef)&storeMarker && !storeReleases, @"Read needs an owned store"); return NULL;
}
void TestResourceRelease(CFTypeRef handle) {
    Require(handle != NULL, @"Never release NULL");
    if (handle == &reachMarker) { Require(!reachReleases, @"Reachability releases exactly once"); reachReleases++; }
    else if (handle == &storeMarker) { Require(!storeReleases, @"Store releases exactly once"); storeReleases++; }
    else if (handle == &sourceMarker) { Require(!sourceReleases, @"Source releases exactly once"); sourceReleases++; }
    else abort();
}
@interface ResourceTestBundle: NSObject
@property(readonly) NSDictionary *infoDictionary;
@end
@implementation ResourceTestBundle
- (NSDictionary *)infoDictionary { return @{@"CFBundleName": @"Synthetic resource tests"}; }
@end
@interface ResourceTestTarget: NSObject <NameServersChangeEventTarget>
@end
@implementation ResourceTestTarget
- (void)nameServersDidChange:(NameServers *)value {}
@end
void TestSetResourceFailure(int value) {
    step = value;
    reachReleases = storeReleases = sourceReleases = 0;
    schedules = unschedules = adds = removes = notifications = sourceCreates = afterRelease = 0;
}
#ifndef TELEPHONE_RESOURCE_NO_MAIN
int RunResourceLifecycleRegressions(void) {
    @autoreleasepool {
        for (NSString *host in @[@"audit.invalid", @"192.0.2.1", @"2001:db8::1"]) {
            for (step = 0; step <= 3; step++) {
                reachReleases = schedules = unschedules = afterRelease = 0;
                @autoreleasepool {
                    AKNetworkReachability *value = [[AKNetworkReachability alloc] initWithHost:host];
                    Require((value != nil) == (step == 3), @"Failure returns nil, success returns live object");
                    value = nil;
                }
                Require(reachReleases == (step == 0 ? 0 : 1), @"Reachability creator lifetime releases once");
                Require(afterRelease == 0, @"Never unschedule a released handle");
                printf("reachability host=%s failure=%d releases=%d schedule=%d unschedule=%d after_release=%d\n",
                       host.UTF8String, step, reachReleases, schedules, unschedules, afterRelease);
            }
        }
        for (step = 0; step <= 3; step++) {
            storeReleases = sourceReleases = adds = removes = notifications = sourceCreates = 0;
            @autoreleasepool {
                NameServers *value = [[NameServers alloc] initWithBundle:(id)[ResourceTestBundle new] target:[ResourceTestTarget new]];
                Require((value != nil) == (step == 3), @"DNS failures must return nil");
                if (value) Require(value.all.count == 0, @"Missing DNS value remains empty");
                value = nil;
            }
            Require(storeReleases == (step == 0 ? 0 : 1), @"Every successful store creator releases once");
            Require(sourceReleases == (step == 3 ? 1 : 0), @"Source release only after successful creation");
            Require(adds == (step == 3 ? 1 : 0) && removes == adds, @"Only owned scheduled source is removed");
            Require(notifications == (step == 0 ? 0 : 1), @"NULL store must not reach notification keys");
            Require(sourceCreates == (step >= 2 ? 1 : 0), @"Key failure must prevent source creation");
            printf("DNS failure=%d store_releases=%d source_releases=%d add=%d remove=%d keys=%d source_create=%d\n",
                   step, storeReleases, sourceReleases, adds, removes, notifications, sourceCreates);
        }
        puts("resource lifecycle regressions passed: 12 reachability cases and 4 DNS cases");
    }
    return 0;
}

int main(void) { return RunResourceLifecycleRegressions(); }
#endif
