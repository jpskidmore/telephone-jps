// Fresh production user-agent lifecycle with inert C SDK boundaries. The real
// WaitingThread and main-queue completion paths run; no SIP endpoint is created.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "AKSIPUserAgent.h"
#import "Telephone-Swift.h"

static AKSIPUserAgent *agent;
static NSString *failure;
static BOOL endpoint, changeDuringStart;
static NSInteger references, acquired, released, enums, earlySDK, mainSDK, toneCreated, toneDestroyed;
static NSInteger recorderStops, unsafeRecorderStops, endpointDestroyedWithRecorder;
static NSMutableDictionary<NSString *, NSNumber *> *priorities;
@interface LifecycleRecordingCall : NSObject
@property(nonatomic,getter=isRecording) BOOL recording;
@property(nonatomic) NSInteger identifier, state;
- (void)stopRecording;
@end
@implementation LifecycleRecordingCall
- (void)stopRecording { recorderStops++; if (!endpoint || NSThread.isMainThread) unsafeRecorderStops++; self.recording=NO; }
@end
@interface LifecycleRecordingAccount : NSObject
@property(nonatomic) NSArray *callsSnapshot;
@property(nonatomic) BOOL registered;
@property(nonatomic) NSInteger registrationStatus, registrationExpireTime;
@property(nonatomic) NSString *registrationStatusText;
- (void)cancelPendingOutgoingCalls;
- (void)updateIdentifier:(NSInteger)identifier;
@end
@implementation LifecycleRecordingAccount
- (void)cancelPendingOutgoingCalls {}
- (void)updateIdentifier:(NSInteger)identifier {}
@end
static LifecycleRecordingCall *recordingCall;
static void Native(void) { if (!references) earlySDK++; if (NSThread.isMainThread) mainSDK++; }
static pj_status_t Status(NSString *stage) { return [failure isEqual:stage] ? PJ_EUNKNOWN : PJ_SUCCESS; }

pj_status_t AKProbePJInit(void) {
    if (NSThread.isMainThread) mainSDK++;
    if ([failure isEqual:@"pj-init"]) return PJ_EUNKNOWN;
    references++; acquired++; return PJ_SUCCESS;
}
void AKProbePJShutdown(void) { Native(); references--; released++; }
pj_bool_t AKProbeThreadIsRegistered(void) { Native(); return PJ_FALSE; }
pj_status_t AKProbeThreadRegister(const char *name, pj_thread_desc desc, pj_thread_t **thread) {
    Native(); *thread = (pj_thread_t *)(uintptr_t)1; return Status(@"thread-register");
}
pj_status_t AKProbeCreate(void) { Native(); return Status(@"create"); }
pj_pool_t *AKProbePoolCreate(const char *name, pj_size_t initial, pj_size_t increment) {
    Native(); return [failure isEqual:@"pool"] ? NULL : (pj_pool_t *)(uintptr_t)1;
}
void AKProbePoolRelease(pj_pool_t *pool) { Native(); }
void AKProbeConfigDefault(pjsua_config *config) { Native(); memset(config, 0, sizeof(*config)); }
void AKProbeLoggingDefault(pjsua_logging_config *config) { Native(); memset(config, 0, sizeof(*config)); }
void AKProbeMediaDefault(pjsua_media_config *config) {
    Native(); memset(config, 0, sizeof(*config)); config->clock_rate=48000; config->channel_count=1; config->audio_frame_ptime=20;
}
void AKProbeTransportDefault(pjsua_transport_config *config) { Native(); memset(config, 0, sizeof(*config)); }
pj_status_t AKProbeInit(const pjsua_config *ua, const pjsua_logging_config *log, const pjsua_media_config *media) {
    Native(); pj_status_t result=Status(@"init"); endpoint=result==PJ_SUCCESS; return result;
}
pj_status_t AKProbeToneCreate(pj_pool_t *pool, const pj_str_t *name, unsigned rate, unsigned channels,
                             unsigned samples, unsigned bits, unsigned options, pjmedia_port **port) {
    Native(); static pjmedia_port tone; pj_status_t result=Status(@"tone");
    if (result==PJ_SUCCESS) { *port=&tone; toneCreated++; } return result;
}
pj_status_t AKProbeTonePlay(pjmedia_port *port, unsigned count, const pjmedia_tone_desc tones[], unsigned options) {
    Native(); return PJ_SUCCESS;
}
pj_status_t AKProbeConfAdd(pj_pool_t *pool, pjmedia_port *port, pjsua_conf_port_id *slot) {
    Native(); pj_status_t result=Status(@"conference"); if (result==PJ_SUCCESS) *slot=42; return result;
}
pj_status_t AKProbeConfRemove(pjsua_conf_port_id slot) { Native(); return PJ_SUCCESS; }
pj_status_t AKProbePortDestroy(pjmedia_port *port) { Native(); toneDestroyed++; return PJ_SUCCESS; }
pj_status_t AKProbeTransportCreate(pjsip_transport_type_e type, const pjsua_transport_config *config,
                                  pjsua_transport_id *identifier) {
    Native(); pj_status_t result=type==PJSIP_TRANSPORT_UDP ? Status(@"transport") : PJ_SUCCESS;
    if (result==PJ_SUCCESS) *identifier=7+(int)type; return result;
}
pj_status_t AKProbeTransportInfo(pjsua_transport_id identifier, pjsua_transport_info *info) {
    Native(); memset(info,0,sizeof(*info)); info->local_name.port=5060; return PJ_SUCCESS;
}
pj_status_t AKProbeEnumCodecs(pjsua_codec_info infos[], unsigned *count) {
    Native(); if (!endpoint) earlySDK++; enums++;
    memset(infos,0,sizeof(*infos)*3); *count=3;
    infos[0].codec_id=pj_str("PCMU/8000/1"); infos[1].codec_id=pj_str("PCMA/8000/1"); infos[2].codec_id=pj_str("opus/48000/2");
    return PJ_SUCCESS;
}
pj_status_t AKProbeSetPriority(const pj_str_t *identifier, pj_uint8_t priority) {
    Native(); if (!endpoint) earlySDK++;
    NSString *key=[[NSString alloc] initWithBytes:identifier->ptr length:identifier->slen encoding:NSUTF8StringEncoding];
    priorities[key]=@(priority); return PJ_SUCCESS;
}
pj_status_t AKProbeStart(void) {
    Native(); if (changeDuringStart) agent.usesG711Only=NO;
    return Status(@"start");
}
pj_status_t AKProbeDestroy(void) { Native(); if (recordingCall.isRecording) endpointDestroyedWithRecorder++; endpoint=NO; return PJ_SUCCESS; }

static BOOL Wait(BOOL (^condition)(void)) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:4];
    while (!condition() && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    return condition();
}
static NSDictionary *Snapshot(void) {
    return @{ @"references":@(references), @"acquired":@(acquired), @"released":@(released),
              @"codecEnumerations":@(enums), @"earlySDK":@(earlySDK), @"mainSDK":@(mainSDK),
              @"toneCreated":@(toneCreated), @"toneDestroyed":@(toneDestroyed),
              @"recorderStops":@(recorderStops), @"unsafeRecorderStops":@(unsafeRecorderStops), @"endpointDestroyedWithRecorder":@(endpointDestroyedWithRecorder),
              @"ownsReference":[agent valueForKey:@"ownsPJLIBReference"],
              @"mediaReady":[agent valueForKey:@"mediaEndpointReady"], @"priorities":[priorities copy] };
}
static void Reset(NSString *stage) {
    failure=stage; endpoint=NO; changeDuringStart=NO; references=acquired=released=enums=earlySDK=mainSDK=toneCreated=toneDestroyed=0;
    recorderStops=unsafeRecorderStops=endpointDestroyedWithRecorder=0; recordingCall=nil;
    [[agent valueForKey:@"retiredAccounts"] removeAllObjects];
    priorities=[NSMutableDictionary dictionary]; agent.usesG711Only=NO;
}
int main(void) {
    @autoreleasepool {
        // Bypass application/user-agent initializers (parser, audio and profile).
        agent=class_createInstance(AKSIPUserAgent.class,0);
        [agent setValue:[NSMutableArray array] forKey:@"accounts"];
        [agent setValue:[NSMutableArray array] forKey:@"retiredAccounts"];
        WaitingThread *thread=[[WaitingThread alloc] init]; [thread start];
        [agent setValue:thread forKey:@"thread"];
        [agent setValue:@(-1) forKey:@"ringbackSlot"]; agent.transportPort=5060; agent.maxCalls=4;
        agent.userAgentString=@"Telephone isolated regression";
        NSMutableDictionary *results=[NSMutableDictionary dictionary];
        for (NSString *stage in @[@"pj-init",@"thread-register",@"create",@"pool",@"init",@"tone",@"conference",@"transport",@"start"]) {
            Reset(stage); agent.usesG711Only=YES;
            BOOL deferred=enums==0; [agent start];
            BOOL returned=Wait(^BOOL { return agent.state==AKSIPUserAgentStateStopped; });
            NSMutableDictionary *result=[Snapshot() mutableCopy]; result[@"completionReturned"]=@(returned); result[@"codecDeferredBeforeStart"]=@(deferred);
            results[stage]=result;
        }
        Reset(nil); agent.usesG711Only=YES; changeDuringStart=YES;
        BOOL deferred=enums==0;
        [agent start]; BOOL started=Wait(^BOOL { return agent.isStarted; });
        __block BOOL barrier=NO;
        [agent performSIPOperation:^{ return PJ_SUCCESS; } completion:^(pj_status_t status) { barrier=status==PJ_SUCCESS; }];
        BOOL drained=Wait(^BOOL { return barrier; });
        NSDictionary *startup=Snapshot();
        NSUInteger revision=[[agent valueForKey:@"codecRevision"] unsignedIntegerValue];
        NSUInteger applied=[[agent valueForKey:@"appliedCodecRevision"] unsignedIntegerValue];
        recordingCall=[LifecycleRecordingCall new]; recordingCall.recording=YES;
        LifecycleRecordingAccount *retired=[LifecycleRecordingAccount new]; retired.callsSnapshot=@[recordingCall];
        [[agent valueForKey:@"retiredAccounts"] addObject:retired];
        // Main-queue stop must return before worker teardown; queued ordinary
        // work cancels after generation change while FIFO cleanup still runs.
        __block NSInteger ordinary=0, cleanup=0; __block pj_status_t cancelled=PJ_SUCCESS;
        dispatch_semaphore_t entered=dispatch_semaphore_create(0), release=dispatch_semaphore_create(0);
        [agent performSIPOperation:^{ dispatch_semaphore_signal(entered); dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC)); return PJ_SUCCESS; } completion:nil];
        BOOL workerBlocked=dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0;
        [agent performSIPOperation:^{ ordinary++; return PJ_SUCCESS; } completion:^(pj_status_t status) { cancelled=status; }];
        [agent performSIPCleanupOperation:^{ cleanup++; return PJ_SUCCESS; } completion:nil];
        [agent stopAndWait]; BOOL stopReturned=agent.state==AKSIPUserAgentStateStopping;
        dispatch_semaphore_signal(release);
        BOOL stopped=Wait(^BOOL { return agent.state==AKSIPUserAgentStateStopped; });
        results[@"successfulStartup"] = @{ @"started":@(started), @"drained":@(drained), @"codecDeferredBeforeStart":@(deferred),
            @"pendingCodecApplied":@(revision==applied && enums>=2 && [priorities[@"opus/48000/2"] intValue]==130),
            @"startup":startup, @"stopReturnedAsynchronously":@(stopReturned), @"stopped":@(stopped),
            @"cleanupExecuted":@(workerBlocked && cleanup==1), @"ordinaryCancelled":@(ordinary==0 && cancelled==PJ_ECANCELLED), @"afterStop":Snapshot() };
        Reset(nil);
        BOOL repeated=YES;
        for (NSUInteger i=0;i<4;i++) {
            [agent start]; repeated &= Wait(^BOOL { return agent.isStarted; });
            [agent stop]; repeated &= Wait(^BOOL { return agent.state==AKSIPUserAgentStateStopped; });
        }
        results[@"repeatedCycles"]=@{ @"completed":@(repeated), @"native":Snapshot() };
        NSData *json=[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(json.bytes,1,json.length,stdout); fputc('\n',stdout);
    }
    return 0;
}
