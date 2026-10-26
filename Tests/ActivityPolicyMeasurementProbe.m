// Isolated ProcessInfo overhead probe, not Telephone/App Nap/SIP acceptance.
#import <Foundation/Foundation.h>
#import <libproc.h>
#import <sys/resource.h>
#import <time.h>
#import <unistd.h>

static uint64_t MonotonicNS(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * NSEC_PER_SEC + (uint64_t)time.tv_nsec;
}
static void SleepNS(uint64_t duration) {
    struct timespec request = {(time_t)(duration / NSEC_PER_SEC), (long)(duration % NSEC_PER_SEC)};
    while (nanosleep(&request, &request) == -1 && errno == EINTR) {}
}
static BOOL Snapshot(struct rusage_info_v4 *info) {
    return proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)info) == 0;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) return 64;
        NSString *policy = @(argv[1]), *workload = @(argv[2]);
        double duration = strtod(argv[3], NULL);
        if (!([policy isEqual:@"none"] || [policy isEqual:@"session"]) ||
            !([workload isEqual:@"idle"] || [workload isEqual:@"paced"]) || duration < .1 || duration > 30) return 64;
        NSProcessInfo *process = NSProcessInfo.processInfo; // Equal initialisation before both baselines.
        struct rusage cpuBefore = {0}, cpuAfter = {0};
        if (getrusage(RUSAGE_SELF, &cpuBefore) != 0) return 69;
        struct rusage_info_v4 before = {0}, after = {0};
        if (!Snapshot(&before)) return 69; // API failure is not a zero measurement.
        uint64_t start = MonotonicNS(), end = start + (uint64_t)(duration * NSEC_PER_SEC);
        NSActivityOptions options = NSActivityUserInitiatedAllowingIdleSystemSleep;
        id<NSObject> token = [policy isEqual:@"session"]
            ? [process beginActivityWithOptions:options reason:@"Isolated SIP activity policy measurement"] : nil;
        NSUInteger ticks = 0;
        while (MonotonicNS() < end) {
            uint64_t remaining = end - MonotonicNS();
            if (remaining > (uint64_t)(duration * NSEC_PER_SEC)) break;
            SleepNS([workload isEqual:@"paced"] ? MIN(remaining, 200 * NSEC_PER_MSEC) : remaining);
            if ([workload isEqual:@"paced"]) ticks++;
        }
        if (token != nil) [process endActivity:token];
        token = nil;
        uint64_t elapsed = MonotonicNS() - start;
        if (!Snapshot(&after) || getrusage(RUSAGE_SELF, &cpuAfter) != 0) return 69;
        double userCPU = (cpuAfter.ru_utime.tv_sec - cpuBefore.ru_utime.tv_sec) +
            (cpuAfter.ru_utime.tv_usec - cpuBefore.ru_utime.tv_usec) / 1e6;
        double systemCPU = (cpuAfter.ru_stime.tv_sec - cpuBefore.ru_stime.tv_sec) +
            (cpuAfter.ru_stime.tv_usec - cpuBefore.ru_stime.tv_usec) / 1e6;
        NSDictionary *result = @{@"policy":policy, @"workload":workload,
            @"wallSeconds":@((double)elapsed / NSEC_PER_SEC),
            @"userCPUSeconds":@(userCPU),
            @"systemCPUSeconds":@(systemCPU),
            @"packageIdleWakeups":@(after.ri_pkg_idle_wkups - before.ri_pkg_idle_wkups),
            @"interruptWakeups":@(after.ri_interrupt_wkups - before.ri_interrupt_wkups),
            @"syntheticTicks":@(ticks), @"activityOptions":@([policy isEqual:@"none"] ? 0 : options),
            @"idleSystemSleepDisabled":@([policy isEqual:@"session"] && (options & NSActivityIdleSystemSleepDisabled) != 0)};
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}
