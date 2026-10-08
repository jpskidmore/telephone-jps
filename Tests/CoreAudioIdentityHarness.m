// Bounded native UID regression: compile the exact patched driver into this
// translation unit, substituting only subsystem and CoreAudio query boundaries.
// No endpoint, SDK startup, device discovery or hardware operation is performed.
#import <Foundation/Foundation.h>
#define pjmedia_get_aud_subsys JPSFixtureAudioSubsystem
#define AudioObjectGetPropertyData JPSFixturePropertyData
#include JPS_COREAUDIO_SOURCE
#undef pjmedia_get_aud_subsys
#undef AudioObjectGetPropertyData

static pjmedia_aud_subsys fixtureSubsystem;
static unsigned queries;
static OSStatus queryStatus;
static BOOL returnLongUID;

pjmedia_aud_subsys *JPSFixtureAudioSubsystem(void) { return &fixtureSubsystem; }
OSStatus JPSFixturePropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address,
                               UInt32 qualifierSize, const void *qualifier, UInt32 *size, void *data) {
    if (address->mSelector != kAudioDevicePropertyDeviceUID || address->mScope != kAudioObjectPropertyScopeGlobal) { abort(); }
    queries++;
    if (queryStatus != noErr) { return queryStatus; }
    NSString *value = returnLongUID ? @"UID-LONGER-THAN-BUFFER" : object == 101 ? @"UID-A" : @"UID-B";
    *((CFStringRef *)data) = CFStringCreateWithCString(NULL, value.UTF8String, kCFStringEncodingUTF8);
    *size = sizeof(CFStringRef);
    return noErr;
}

#define CHECK(condition) do { checks++; if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); return 1; } } while (0)
int main(void) { @autoreleasepool {
    unsigned checks = 0;
    struct coreaudio_factory factory = {0};
    struct coreaudio_dev_info devices[2] = {0};
    pjmedia_aud_dev_factory otherFactory = {0};
    devices[0].dev_id = 101; devices[1].dev_id = 202;
    strcpy(devices[0].info.name, "Duplicate Headset"); strcpy(devices[1].info.name, "Duplicate Headset");
    factory.base.op = &factory_op; factory.dev_count = 2; factory.dev_info = devices;
    fixtureSubsystem.pf = (pj_pool_factory *)(uintptr_t)1; fixtureSubsystem.drv_cnt = 3; fixtureSubsystem.dev_cnt = 3;
    fixtureSubsystem.drv[1].f = &otherFactory; fixtureSubsystem.drv[2].f = &factory.base;
    fixtureSubsystem.dev_list[0] = (1 << 16); fixtureSubsystem.dev_list[1] = (2 << 16) | 1; fixtureSubsystem.dev_list[2] = (2 << 16);
    char uid[64];
    CHECK(jps_coreaudio_device_uid(1, uid, sizeof(uid)) == PJ_SUCCESS); CHECK(strcmp(uid, "UID-B") == 0);
    CHECK(jps_coreaudio_device_uid(2, uid, sizeof(uid)) == PJ_SUCCESS); CHECK(strcmp(uid, "UID-A") == 0);
    CHECK(queries == 2);
    CHECK(jps_coreaudio_device_uid(0, uid, sizeof(uid)) != PJ_SUCCESS); CHECK(queries == 2);
    CHECK(jps_coreaudio_device_uid(-1, uid, sizeof(uid)) != PJ_SUCCESS);
    CHECK(jps_coreaudio_device_uid(3, uid, sizeof(uid)) != PJ_SUCCESS);
    CHECK(queries == 2);
    fixtureSubsystem.dev_list[1] = (2 << 16); fixtureSubsystem.dev_list[2] = (2 << 16) | 1;
    CHECK(jps_coreaudio_device_uid(1, uid, sizeof(uid)) == PJ_SUCCESS); CHECK(strcmp(uid, "UID-A") == 0);
    CHECK(jps_coreaudio_device_uid(2, uid, sizeof(uid)) == PJ_SUCCESS); CHECK(strcmp(uid, "UID-B") == 0);
    queryStatus = kAudioHardwareBadObjectError;
    CHECK(jps_coreaudio_device_uid(1, uid, sizeof(uid)) != PJ_SUCCESS); CHECK(uid[0] == '\0');
    queryStatus = noErr; returnLongUID = YES;
    CHECK(jps_coreaudio_device_uid(1, uid, 4) == PJ_ETOOSMALL);
    fixtureSubsystem.pf = NULL;
    CHECK(jps_coreaudio_device_uid(1, uid, sizeof(uid)) != PJ_SUCCESS);
    printf("CoreAudio identity regression: %u assertions passed; synthetic physical UIDs only.\n", checks);
} return 0; }
