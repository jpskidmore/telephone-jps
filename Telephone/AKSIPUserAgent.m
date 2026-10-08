//
//  AKSIPUserAgent.m
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

#import "AKSIPUserAgent.h"
#import "AKAudioDeviceController.h"
#import <CoreAudio/AudioHardwareBase.h>
#import <pjmedia-audiodev/errno.h>

// The Foundation-only policy/harness use these audited numeric constants. Fail
// compilation if a future SDK/vendor update changes their production meaning.
_Static_assert(PJMEDIA_AUDIODEV_ERRNO_START == 420000, "Review audio error range");
_Static_assert(PJMEDIA_AUDIODEV_ERRNO_END == 469999, "Review audio error range");
_Static_assert(PJMEDIA_AUDIODEV_COREAUDIO_ERRNO_START == 440000, "Review CoreAudio mapping");
_Static_assert(kAudioHardwareNotRunningError == 1937010544, "Review CoreAudio stop mapping");

@import UseCases;

#import "AKNSString+PJSUA.h"
#import "AKSIPAccount.h"
#import "AKSIPCall.h"
#import "AKSIPURIParser.h"
#import "PJSUACallbacks.h"

#import "Telephone-Swift.h"

#define THIS_FILE "AKSIPUserAgent.m"

enum {
  kAKRingbackFrequency1  = 440,
  kAKRingbackFrequency2  = 480,
  kAKRingbackOnDuration  = 2000,
  kAKRingbackOffDuration = 4000,
  kAKRingbackCount       = 1,
  kAKRingbackInterval    = 4000
};

const NSInteger kAKSIPUserAgentInvalidIdentifier = PJSUA_INVALID_ID;

// Maximum number of name servers to take into account.
static const NSInteger kAKSIPUserAgentNameServersMax = 4;

// User agent defaults.
static const NSInteger kAKSIPUserAgentDefaultOutboundProxyPort = 5060;
static const NSInteger kAKSIPUserAgentDefaultSTUNServerPort = 3478;
static const NSInteger kAKSIPUserAgentDefaultLogLevel = 3;
static const NSInteger kAKSIPUserAgentDefaultConsoleLogLevel = 0;
static const BOOL kAKSIPUserAgentDefaultDetectsVoiceActivity = YES;
static const BOOL kAKSIPUserAgentDefaultUsesICE = NO;
static const BOOL kAKSIPUserAgentDefaultUsesQoS = YES;
static const NSInteger kAKSIPUserAgentDefaultTransportPort = 0;
static const BOOL kAKSIPUserAgentDefaultUsesG711Only = NO;
static const BOOL kAKSIPUserAgentDefaultLocksCodec = YES;


// The injected backend lets the recovery policy run in a headless harness
// without initializing PJSUA, using the microphone, or making a SIP call.
@interface AKPJSUAAudioBackend : NSObject <AKAudioDeviceBackend>
@end
@implementation AKPJSUAAudioBackend
- (int)selectInput:(int)input output:(int)output { return pjsua_set_snd_dev(input, output); }
- (int)useNullSoundDevice { return pjsua_set_null_snd_dev(); }
- (int)connectSource:(int)source destination:(int)destination { return pjsua_conf_connect(source, destination); }
@end

@interface AKSIPUserAgent ()

// Read-write redeclaration.
@property(nonatomic) AKSIPUserAgentState state;
@property(nonatomic, strong) AKAudioDeviceController *audioDeviceController;
@property(atomic) BOOL audioRecoveryPending;
@property(atomic) pj_status_t audioFailureStatus;
@property(atomic, readwrite) NSUInteger audioGeneration;
@property(nonatomic) NSInteger requestedInputDevice;
@property(nonatomic) NSInteger requestedOutputDevice;
@property(atomic) BOOL mediaEndpointReady;
@property(atomic) BOOL audioCommandPending;
@property(atomic) NSUInteger audioSelectionRevision;
@property(atomic) NSUInteger audioSelectionGeneration;
@property(atomic) BOOL ownsPJLIBReference;
@property(atomic) NSUInteger codecRevision;
@property(atomic) NSUInteger appliedCodecRevision;
@property(atomic) NSUInteger lifecycleGeneration;
- (void)restoreCurrentAudioConnections;
- (NSArray<AKSIPAccount *> *)accountCollectionsSnapshot;
- (void)audioDidFail:(int)status;

@property(nonatomic) pj_pool_t *pool;

@property(nonatomic, readonly) NSMutableArray *accounts;
@property(nonatomic, readonly) NSMutableArray<AKSIPAccount *> *retiredAccounts;

// Ringback slot.
@property(nonatomic, assign) pjsua_conf_port_id ringbackSlot;

// Ringback port.
@property(nonatomic, assign) pjmedia_port *ringbackPort;

// Ringback count.
@property(nonatomic, assign) NSInteger ringbackCount;

// Transport identifiers.
@property(nonatomic) pjsua_transport_id UDP4TransportIdentifier;
@property(nonatomic) pjsua_transport_id UDP6TransportIdentifier;
@property(nonatomic) pjsua_transport_id TCP4TransportIdentifier;
@property(nonatomic) pjsua_transport_id TCP6TransportIdentifier;
@property(nonatomic) pjsua_transport_id TLS4TransportIdentifier;
@property(nonatomic) pjsua_transport_id TLS6TransportIdentifier;

@property(nonatomic, readonly) NSThread *thread;

/// Updates codecs according to usesG711Only property value.
- (void)updateCodecs;

/// Returns default priority for codec with specified identifier.
- (NSUInteger)priorityForCodec:(NSString *)identifier;

@end


@implementation AKSIPUserAgent

- (void)setDelegate:(id <AKSIPUserAgentDelegate>)aDelegate {
    if (_delegate == aDelegate) {
        return;
    }
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    if (_delegate != nil) {
        [notificationCenter removeObserver:_delegate name:nil object:self];
    }
    
    if (aDelegate != nil) {
        if ([aDelegate respondsToSelector:@selector(SIPUserAgentDidFinishStarting:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPUserAgentDidFinishStarting:)
                                       name:AKSIPUserAgentDidFinishStartingNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPUserAgentDidFinishStopping:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPUserAgentDidFinishStopping:)
                                       name:AKSIPUserAgentDidFinishStoppingNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPUserAgentDidDetectNAT:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPUserAgentDidDetectNAT:)
                                       name:AKSIPUserAgentDidDetectNATNotification
                                     object:self];
        }
    }
    
    _delegate = aDelegate;
}

- (BOOL)isStarted {
    return self.state == AKSIPUserAgentStateStarted;
}

- (NSInteger)activeCallsCount {
    NSInteger count = 0;
    for (AKSIPAccount *account in [self accountCollectionsSnapshot]) {
        count += [account activeCallsCount];
    }
    return count;
}

- (BOOL)hasUnansweredIncomingCalls {
    for (AKSIPAccount *account in [self accountCollectionsSnapshot]) {
        if (account.hasUnansweredIncomingCalls) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<AKSIPAccount *> *)accountCollectionsSnapshot {
    @synchronized(self) {
        return [self.accounts arrayByAddingObjectsFromArray:self.retiredAccounts];
    }
}

- (AKSIPUserAgentCallData *)callData {
    return _callData;
}

- (void)setNameServers:(NSArray *)newNameServers {
    if (_nameServers != newNameServers) {
        
        if ([newNameServers count] > kAKSIPUserAgentNameServersMax) {
            _nameServers = [newNameServers subarrayWithRange:NSMakeRange(0, kAKSIPUserAgentNameServersMax)];
        } else {
            _nameServers = [newNameServers copy];
        }
    }
}

- (void)setOutboundProxyPort:(NSUInteger)port {
    if (port > 0 && port <= 65535) {
        _outboundProxyPort = port;
    } else {
        _outboundProxyPort = kAKSIPUserAgentDefaultOutboundProxyPort;
    }
}

- (void)setSTUNServerPort:(NSUInteger)port {
    if (port > 0 && port <= 65535) {
        _STUNServerPort = port;
    } else {
        _STUNServerPort = kAKSIPUserAgentDefaultSTUNServerPort;
    }
}

- (void)setLogFileName:(NSString *)pathToFile {
    if (_logFileName != pathToFile) {
        if ([pathToFile length] > 0) {
            _logFileName = [pathToFile copy];
        } else {
            _logFileName = nil;
        }
    }
}

- (void)setTransportPort:(NSUInteger)port {
    if (port >= 0 && port <= 65535) {
        _transportPort = port;
    } else {
        _transportPort = kAKSIPUserAgentDefaultTransportPort;
    }
}

- (void)setUsesG711Only:(BOOL)usesG711Only {
    if (_usesG711Only != usesG711Only) {
        _usesG711Only = usesG711Only;
        self.codecRevision++;
        if (self.isStarted) {
            [self performSIPOperation:^{ [self updateCodecs]; return PJ_SUCCESS; } completion:nil];
        }
    }
}


#pragma mark AKSIPUserAgent singleton instance

+ (AKSIPUserAgent *)sharedUserAgent {
    static AKSIPUserAgent *__sharedUserAgent = nil;
    static dispatch_once_t __onceToken;
    dispatch_once(&__onceToken, ^{
        __sharedUserAgent = [[AKSIPUserAgent alloc] init];
    });
    
    return __sharedUserAgent;
}


#pragma mark -

- (instancetype)initWithDelegate:(id<AKSIPUserAgentDelegate>)aDelegate {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    [self setDelegate:aDelegate];
    _accounts = [[NSMutableArray alloc] init];
    _retiredAccounts = [[NSMutableArray alloc] init];
    _requestedInputDevice = PJMEDIA_AUD_DEFAULT_CAPTURE_DEV;
    _requestedOutputDevice = PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
    __weak AKSIPUserAgent *weakSelf = self;
    _audioDeviceController = [[AKAudioDeviceController alloc] initWithBackend:[[AKPJSUAAudioBackend alloc] init]
        logger:^(NSString *message) {
            if (weakSelf.isStarted) {
                // Default level 3 reaches Telephone.log without enabling SIP
                // packet logging. Every field in this message is non-secret.
                PJ_LOG(3, ("AKAudio", "%s", message.UTF8String));
            } else {
                NSLog(@"%@", message);
            }
        }];
    _audioDeviceController.failureHandler = ^(int status) { [weakSelf audioDidFail:status]; };
    [self setDetectedNATType:kAKNATTypeUnknown];

    [self setOutboundProxyPort:kAKSIPUserAgentDefaultOutboundProxyPort];
    [self setSTUNServerPort:kAKSIPUserAgentDefaultSTUNServerPort];
    [self setLogLevel:kAKSIPUserAgentDefaultLogLevel];
    [self setConsoleLogLevel:kAKSIPUserAgentDefaultConsoleLogLevel];
    [self setDetectsVoiceActivity:kAKSIPUserAgentDefaultDetectsVoiceActivity];
    [self setUsesICE:kAKSIPUserAgentDefaultUsesICE];
    [self setUsesQoS:kAKSIPUserAgentDefaultUsesQoS];
    [self setTransportPort:kAKSIPUserAgentDefaultTransportPort];
    [self setUsesG711Only:kAKSIPUserAgentDefaultUsesG711Only];
    [self setLocksCodec:kAKSIPUserAgentDefaultLocksCodec];
    
    [self setRingbackSlot:PJSUA_INVALID_ID];
    [self setUDP4TransportIdentifier:PJSUA_INVALID_ID];
    [self setUDP6TransportIdentifier:PJSUA_INVALID_ID];
    [self setTCP4TransportIdentifier:PJSUA_INVALID_ID];
    [self setTCP6TransportIdentifier:PJSUA_INVALID_ID];
    [self setTLS4TransportIdentifier:PJSUA_INVALID_ID];
    [self setTLS6TransportIdentifier:PJSUA_INVALID_ID];

    _parser = [[AKSIPURIParser alloc] initWithUserAgent:self];

    _thread = [[WaitingThread alloc] init];
    _thread.qualityOfService = NSQualityOfServiceUserInitiated;
    [_thread start];

    return self;
}

- (instancetype)init {
    return [self initWithDelegate:nil];
}

- (void)start {
    if ([self.delegate respondsToSelector:@selector(SIPUserAgentShouldStart)] &&
        ![self.delegate SIPUserAgentShouldStart]) {
        return;
    }
    if (self.state != AKSIPUserAgentStateStopped) {
        return;
    }
    self.audioGeneration++;
    self.state = AKSIPUserAgentStateStarting;
    self.lifecycleGeneration++;
    void (^completion)(BOOL) = ^(BOOL didStart) {
        self.state = didStart ? AKSIPUserAgentStateStarted : AKSIPUserAgentStateStopped;
        if (didStart && self.codecRevision != self.appliedCodecRevision) {
            [self performSIPOperation:^{ [self updateCodecs]; return PJ_SUCCESS; } completion:nil];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPUserAgentDidFinishStartingNotification object:self];
    };
    [self performSelector:@selector(thread_startWithCompletion:) onThread:self.thread withObject:completion waitUntilDone:NO];
}

- (void)thread_startWithCompletion:(void (^ _Nonnull)(BOOL didStart))completion {
    @autoreleasepool {
        [self thread_startInAutoreleasePoolWithCompletion:completion];
    }
}

- (void)thread_startInAutoreleasePoolWithCompletion:(void (^ _Nonnull)(BOOL didStart))completion {
    pj_status_t status;

    status = pj_init();
    if (status != PJ_SUCCESS) {
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }
    self.ownsPJLIBReference = YES;
    self.mediaEndpointReady = NO;

    if (!pj_thread_is_registered()) {
        pj_thread_t *thread;
        status = pj_thread_register("AKSIPUserAgent-pjsip-control", _descriptor, &thread);
        if (status != PJ_SUCCESS) {
            NSLog(@"Error registering thread at PJSUA");
            [self thread_callOnMain:completion withFlag:NO];
            return;
        }
    }

    status = pjsua_create();
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating PJSUA");
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }

    self.pool = pjsua_pool_create("AKSIPUserAgent", 4000, 1000);
    if (!self.pool) {
        NSLog(@"Could not create memory pool");
        [self thread_stop];
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }

    pjsua_config userAgentConfig;
    pjsua_logging_config loggingConfig;
    pjsua_media_config mediaConfig;
    pjsua_transport_config transportConfig;

    pjsua_config_default(&userAgentConfig);
    pjsua_logging_config_default(&loggingConfig);
    pjsua_media_config_default(&mediaConfig);
    pjsua_transport_config_default(&transportConfig);

    userAgentConfig.max_calls = (unsigned)self.maxCalls;
    userAgentConfig.use_timer = PJSUA_SIP_TIMER_INACTIVE;

    if ([[self nameServers] count] > 0) {
        userAgentConfig.nameserver_count = (unsigned)[[self nameServers] count];
        for (NSUInteger i = 0; i < [[self nameServers] count]; ++i) {
            userAgentConfig.nameserver[i] = [[self nameServers][i] pjString];
        }
    }

    if ([[self outboundProxyHost] length] > 0) {
        userAgentConfig.outbound_proxy_cnt = 1;
        
        if ([self outboundProxyPort] == kAKSIPUserAgentDefaultOutboundProxyPort) {
            userAgentConfig.outbound_proxy[0] = [URI URIWithHost:self.outboundProxyHost
                                                       transport:TransportUDP].stringValue.pjString;
        } else {
            userAgentConfig.outbound_proxy[0] = [URI URIWithHost:self.outboundProxyHost
                                                            port:@(self.outboundProxyPort).stringValue
                                                       transport:TransportUDP].stringValue.pjString;
        }
    }

    if ([[self STUNServerHost] length] > 0) {
        userAgentConfig.stun_srv_cnt = 1;

        if ([self STUNServerPort] == kAKSIPUserAgentDefaultSTUNServerPort) {
            userAgentConfig.stun_srv[0] = [[ServiceAddress alloc] initWithHost:self.STUNServerHost].stringValue.pjString;
        } else {
            userAgentConfig.stun_srv[0] = [[ServiceAddress alloc] initWithHost:self.STUNServerHost
                                                                          port:@(self.STUNServerPort).stringValue].stringValue.pjString;
        }
    }
    userAgentConfig.stun_try_ipv6 = PJ_TRUE;

    userAgentConfig.user_agent = [[self userAgentString] pjString];

    if ([[self logFileName] length] > 0) {
        loggingConfig.log_filename = [[[self logFileName] stringByExpandingTildeInPath] pjString];
    }

    loggingConfig.level = (unsigned)[self logLevel];
    loggingConfig.console_level = (unsigned)[self consoleLogLevel];
    mediaConfig.no_vad = ![self detectsVoiceActivity];
    mediaConfig.enable_ice = [self usesICE];
    mediaConfig.snd_auto_close_time = 1;
    mediaConfig.ec_options = PJMEDIA_ECHO_USE_SW_ECHO;

    if (self.usesQoS) {
        transportConfig.qos_params.flags = PJ_QOS_PARAM_HAS_DSCP;
        transportConfig.qos_params.dscp_val = 24;
    }

    transportConfig.port = (unsigned)[self transportPort];

    userAgentConfig.cb.on_incoming_call = &PJSUAOnIncomingCall;
    userAgentConfig.cb.on_call_state = &PJSUAOnCallState;
    userAgentConfig.cb.on_call_media_state = &PJSUAOnCallMediaState;
    userAgentConfig.cb.on_call_transfer_status = &PJSUAOnCallTransferStatus;
    userAgentConfig.cb.on_call_replaced = &PJSUAOnCallReplaced;
    userAgentConfig.cb.on_reg_state = &PJSUAOnAccountRegistrationState;
    userAgentConfig.cb.on_nat_detect = &PJSUAOnNATDetect;
    userAgentConfig.cb.on_acc_find_for_incoming = &PJSUAOnAccountFindForIncoming;

    // Initialize PJSUA.
    status = pjsua_init(&userAgentConfig, &loggingConfig, &mediaConfig);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error initializing PJSUA");
        [self thread_stop];
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }
    self.mediaEndpointReady = YES;

    // Create ringback tones.
    unsigned i, samplesPerFrame;
    pjmedia_tone_desc tone[kAKRingbackCount];
    pj_str_t name;

    samplesPerFrame = mediaConfig.audio_frame_ptime * mediaConfig.clock_rate * mediaConfig.channel_count / 1000;

    name = pj_str("ringback");
    pjmedia_port *aRingbackPort;
    status = pjmedia_tonegen_create2(self.pool,
                                     &name,
                                     mediaConfig.clock_rate,
                                     mediaConfig.channel_count,
                                     samplesPerFrame,
                                     16,
                                     PJMEDIA_TONEGEN_LOOP,
                                     &aRingbackPort);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating ringback tones");
        [self thread_stop];
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }

    [self setRingbackPort:aRingbackPort];

    pj_bzero(&tone, sizeof(tone));
    for (i = 0; i < kAKRingbackCount; ++i) {
        tone[i].freq1 = kAKRingbackFrequency1;
        tone[i].freq2 = kAKRingbackFrequency2;
        tone[i].on_msec = kAKRingbackOnDuration;
        tone[i].off_msec = kAKRingbackOffDuration;
    }
    tone[kAKRingbackCount - 1].off_msec = kAKRingbackInterval;

    pjmedia_tonegen_play([self ringbackPort], kAKRingbackCount, tone, PJMEDIA_TONEGEN_LOOP);

    pjsua_conf_port_id aRingbackSlot;
    status = pjsua_conf_add_port(self.pool, [self ringbackPort], &aRingbackSlot);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error adding media port for ringback tones");
        [self thread_stop];
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }

    [self setRingbackSlot:aRingbackSlot];

    // Add UDP4 transport.
    pjsua_transport_id UDP4TransportIdentifier = PJSUA_INVALID_ID;
    status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &transportConfig, &UDP4TransportIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating UDP4 transport");
        [self thread_stop];
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }
    self.UDP4TransportIdentifier = UDP4TransportIdentifier;

    // Get UDP4 transport port chosen by PJSUA.
    if ([self transportPort] == 0) {
        pjsua_transport_info transportInfo;
        status = pjsua_transport_get_info(UDP4TransportIdentifier, &transportInfo);
        if (status != PJ_SUCCESS) {
            NSLog(@"Error getting UDP4 transport info");
        }
        
        [self setTransportPort:transportInfo.local_name.port];
        
        // Set chosen port back to transportConfig to add TCP transport below.
        transportConfig.port = (unsigned)[self transportPort];
    }

    // Add UDP6 transport.
    pjsua_transport_id UDP6TransportIdentifier = PJSUA_INVALID_ID;
    status = pjsua_transport_create(PJSIP_TRANSPORT_UDP6, &transportConfig, &UDP6TransportIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating UDP6 transport");
    }
    self.UDP6TransportIdentifier = UDP6TransportIdentifier;

    // Add TCP4 transport.
    pjsua_transport_id TCP4TransportIdentifier = PJSUA_INVALID_ID;
    status = pjsua_transport_create(PJSIP_TRANSPORT_TCP, &transportConfig, &TCP4TransportIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating TCP4 transport");
    }
    self.TCP4TransportIdentifier = TCP4TransportIdentifier;

    // Add TCP6 transport.
    pjsua_transport_id TCP6TransportIdentifier = PJSUA_INVALID_ID;
    status = pjsua_transport_create(PJSIP_TRANSPORT_TCP6, &transportConfig, &TCP6TransportIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating TCP6 transport");
    }
    self.TCP6TransportIdentifier = TCP6TransportIdentifier;

    // Add TLS transport.
    transportConfig.tls_setting.verify_server = PJ_TRUE;
    transportConfig.tls_setting.verify_client = PJ_TRUE;
    NSURL *cert = [NSBundle.mainBundle URLForResource:@"PublicCAs" withExtension:@"pem"];
    transportConfig.tls_setting.ca_list_file = cert.path.pjString;
    transportConfig.port++;
    pjsua_transport_id TLS4TransportIdentifier = PJSUA_INVALID_ID;
    status = pjsua_transport_create(PJSIP_TRANSPORT_TLS, &transportConfig, &TLS4TransportIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating TLS4 transport");
    }
    self.TLS4TransportIdentifier = TLS4TransportIdentifier;

    // Add TLS6 transport.
    pjsua_transport_id TLS6TransportIdentifier = PJSUA_INVALID_ID;
    status = pjsua_transport_create(PJSIP_TRANSPORT_TLS6, &transportConfig, &TLS6TransportIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error creating TLS6 transport");
    }
    self.TLS6TransportIdentifier = TLS6TransportIdentifier;

    // Update codecs.
    [self updateCodecs];

    // Start PJSUA.
    status = pjsua_start();
    if (status != PJ_SUCCESS) {
        NSLog(@"Error starting PJSUA");
        [self thread_stop];
        [self thread_callOnMain:completion withFlag:NO];
        return;
    }

    [self thread_callOnMain:completion withFlag:YES];
}

- (void)thread_callOnMain:(void (^ _Nonnull)(BOOL))block withFlag:(BOOL)flag {
    if (!flag && self.ownsPJLIBReference) {
        self.mediaEndpointReady = NO;
        self.ownsPJLIBReference = NO;
        pj_shutdown();
    }
    dispatch_async(dispatch_get_main_queue(), ^{ block(flag); });
}

- (void)performSIPOperation:(pj_status_t (^)(void))operation completion:(void (^)(pj_status_t))completion {
    NSUInteger generation = self.audioGeneration;
    void (^command)(void) = ^{
        pj_status_t status = PJ_ECANCELLED;
        if (generation == self.audioGeneration && self.isStarted) {
            status = operation();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(generation == self.audioGeneration ? status : PJ_ECANCELLED);
        });
    };
    [self performSelector:@selector(thread_performCommand:) onThread:self.thread withObject:[command copy] waitUntilDone:NO];
}

- (void)thread_performCommand:(void (^)(void))command {
    @autoreleasepool { command(); }
}

- (void)performSIPCleanupOperation:(pj_status_t (^)(void))operation completion:(void (^)(pj_status_t))completion {
    NSUInteger generation = self.lifecycleGeneration;
    void (^command)(void) = ^{
        pj_status_t status = generation == self.lifecycleGeneration && self.mediaEndpointReady
            ? operation() : PJ_ECANCELLED;
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(status); });
    };
    [self performSelector:@selector(thread_performCommand:) onThread:self.thread withObject:[command copy] waitUntilDone:NO];
}

- (void)stop {
    if (self.state != AKSIPUserAgentStateStarted) {
         return;
    }
    self.audioGeneration++;
    [self.audioDeviceController finishOutgoingCall];
    self.state = AKSIPUserAgentStateStopping;
    [self performSelector:@selector(thread_stopWithCompletion:) onThread:self.thread withObject:^{[self finishStopping];} waitUntilDone:NO];
}

- (void)stopAndWait {
    if ([NSThread isMainThread]) { [self stop]; return; }
    if (self.state != AKSIPUserAgentStateStarted) {
         return;
    }
    self.audioGeneration++;
    [self.audioDeviceController finishOutgoingCall];
    self.state = AKSIPUserAgentStateStopping;
    [self performSelector:@selector(thread_stop) onThread:self.thread withObject:nil waitUntilDone:YES];
    [self finishStopping];
}

- (void)thread_stopWithCompletion:(void (^ _Nonnull)(void))completion {
    [self thread_stop];
    dispatch_async(dispatch_get_main_queue(), completion);
}

- (void)thread_stop {
    @autoreleasepool {
        [self thread_stopInAutoreleasePool];
    }
}

- (void)thread_stopInAutoreleasePool {
    // Recorder destruction finalizes WAV tracks. Do this on the control worker
    // before deleting conference ports/pools or the native media endpoint;
    // window completions may arrive only after teardown has already queued.
    for (AKSIPAccount *account in [self accountCollectionsSnapshot]) {
        for (AKSIPCall *call in account.callsSnapshot) {
            if (call.isRecording) [call stopRecording];
        }
    }
    self.mediaEndpointReady = NO;
    if (self.ringbackSlot != PJSUA_INVALID_ID) {
        pjsua_conf_remove_port(self.ringbackSlot);
        self.ringbackSlot = PJSUA_INVALID_ID;
    }
    if (self.ringbackPort) {
        pjmedia_port_destroy(self.ringbackPort);
        self.ringbackPort = NULL;
    }
    self.UDP4TransportIdentifier = PJSUA_INVALID_ID;
    self.UDP6TransportIdentifier = PJSUA_INVALID_ID;
    self.TCP4TransportIdentifier = PJSUA_INVALID_ID;
    self.TCP6TransportIdentifier = PJSUA_INVALID_ID;
    self.TLS4TransportIdentifier = PJSUA_INVALID_ID;
    self.TLS6TransportIdentifier = PJSUA_INVALID_ID;
    if (self.pool) {
        pj_pool_release(self.pool);
        self.pool = NULL;
    }
    if (pjsua_destroy() != PJ_SUCCESS) {
        NSLog(@"Error stopping SIP user agent");
    }
    if (self.ownsPJLIBReference) {
        self.ownsPJLIBReference = NO;
        pj_shutdown();
    }
}

- (void)finishStopping {
    for (AKSIPAccount *account in [self accountCollectionsSnapshot]) {
        [account cancelPendingOutgoingCalls];
        [account updateIdentifier:PJSUA_INVALID_ID];
        account.registrationStatus = 0;
        account.registrationExpireTime = kAKSIPAccountRegistrationExpireTimeNotSpecified;
        account.registrationStatusText = @"";
        for (AKSIPCall *call in account.callsSnapshot) {
            call.identifier = PJSUA_INVALID_ID;
            call.state = kAKSIPCallDisconnectedState;
        }
    }
    @synchronized(self) {
        [self.accounts removeAllObjects];
        [self.retiredAccounts removeAllObjects];
    }
    memset(self.callData, 0, sizeof(AKSIPUserAgentCallData) * PJSUA_MAX_CALLS);
    self.ringbackCount = 0;
    self.state = AKSIPUserAgentStateStopped;
    BOOL hadAudioFailure = self.hasAudioFailure;
    [self.audioDeviceController resetFailure];
    self.audioRecoveryPending = NO;
    self.audioFailureStatus = PJ_SUCCESS;
    if (hadAudioFailure) {
        [self publishAudioState];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPUserAgentDidFinishStoppingNotification object:self];
}

- (pj_status_t)thread_addAccount:(AKSIPAccount *)anAccount withPassword:(NSString *)aPassword identifier:(pjsua_acc_id *)identifier {
    pjsua_acc_config accountConfig;
    pjsua_acc_config_default(&accountConfig);
    // Publish model ownership on main before REGISTER can produce callbacks.
    // The desired availability is re-read after attachment, so Offline while
    // native creation was pending cannot accidentally register the account.
    accountConfig.register_on_acc_add = PJ_FALSE;
    
    accountConfig.id = anAccount.uri.stringValue.pjString;

    accountConfig.reg_uri = [[URI alloc] initWithAddress:anAccount.registrar
                                               transport:anAccount.transport].stringValue.pjString;
    accountConfig.cred_count = 1;
    if ([[anAccount realm] length] > 0) {
        accountConfig.cred_info[0].realm = [[anAccount realm] pjString];
    } else {
        accountConfig.cred_info[0].realm = pj_str("*");
    }
    accountConfig.cred_info[0].scheme = pj_str("digest");
    accountConfig.cred_info[0].username = [[anAccount username] pjString];
    accountConfig.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    accountConfig.cred_info[0].data = [aPassword pjString];
    
    accountConfig.rtp_cfg.port = 4000;

    if (self.usesQoS) {
        accountConfig.rtp_cfg.qos_params.flags = PJ_QOS_PARAM_HAS_DSCP;
        accountConfig.rtp_cfg.qos_params.dscp_val = 46;
    }
    
    if ([[anAccount proxyHost] length] > 0) {
        accountConfig.proxy_cnt = 1;
        
        if ([anAccount proxyPort] == kAKSIPAccountDefaultSIPProxyPort) {
            accountConfig.proxy[0] = [URI URIWithHost:anAccount.proxyHost
                                            transport:anAccount.transport].stringValue.pjString;
        } else {
            accountConfig.proxy[0] = [URI URIWithHost:anAccount.proxyHost
                                                 port:@(anAccount.proxyPort).stringValue
                                            transport:anAccount.transport].stringValue.pjString;
        }
    }
    
    accountConfig.reg_timeout = (unsigned)[anAccount reregistrationTime];
    
    switch (anAccount.transport) {
        case TransportUDP:
            accountConfig.transport_id = anAccount.usesIPv6 ? self.UDP6TransportIdentifier : self.UDP4TransportIdentifier;
            break;
        case TransportTCP:
            accountConfig.transport_id = anAccount.usesIPv6 ? self.TCP6TransportIdentifier : self.TCP4TransportIdentifier;
            break;
        case TransportTLS:
            accountConfig.transport_id = anAccount.usesIPv6 ? self.TLS6TransportIdentifier : self.TLS4TransportIdentifier;
            break;
        default:
            break;
    }

    accountConfig.use_srtp = anAccount.transport == TransportTLS ? PJMEDIA_SRTP_MANDATORY : PJMEDIA_SRTP_DISABLED;

    accountConfig.ipv6_media_use = anAccount.usesIPv6 ? PJSUA_IPV6_ENABLED : PJSUA_IPV6_DISABLED;

    accountConfig.allow_contact_rewrite = anAccount.updatesContactHeader ? PJ_TRUE : PJ_FALSE;
    accountConfig.allow_via_rewrite = anAccount.updatesViaHeader ? PJ_TRUE : PJ_FALSE;
    accountConfig.allow_sdp_nat_rewrite = anAccount.updatesSDP ? PJ_TRUE : PJ_FALSE;

    accountConfig.lock_codec = self.locksCodec ? PJ_TRUE : PJ_FALSE;
    
    pjsua_acc_id accountIdentifier;
    pj_status_t status = pjsua_acc_add(&accountConfig, PJ_FALSE, &accountIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error adding account %@ with status %d", anAccount, status);
        return status;
    }
    
    *identifier = accountIdentifier;
    return PJ_SUCCESS;
}

- (BOOL)addAccount:(AKSIPAccount *)account withPassword:(NSString *)password {
    [self addAccount:account withPassword:password completion:^(BOOL added) {}];
    return self.isStarted;
}

- (void)addAccount:(AKSIPAccount *)account withPassword:(NSString *)password completion:(void (^)(BOOL))completion {
    if (!self.isStarted || ([self.delegate respondsToSelector:@selector(SIPUserAgentShouldAddAccount:)] &&
                            ![self.delegate SIPUserAgentShouldAddAccount:account])) { completion(NO); return; }
    NSUInteger generation = account.outgoingGeneration;
    __block pjsua_acc_id identifier = PJSUA_INVALID_ID;
    __block NSInteger registrationStatus = 0, registrationError = 0, registrationExpires = -1;
    __block NSString *registrationText = @"";
    [self performSIPOperation:^pj_status_t {
        if (account.outgoingGeneration != generation) return PJ_ECANCELLED;
        pj_status_t result = [self thread_addAccount:account withPassword:password identifier:&identifier];
        pjsua_acc_info info;
        if (result == PJ_SUCCESS && pjsua_acc_get_info(identifier, &info) == PJ_SUCCESS) {
            registrationStatus = info.status; registrationError = info.reg_last_err; registrationExpires = info.expires;
            registrationText = [NSString stringWithPJString:info.status_text];
        }
        return result;
    } completion:^(pj_status_t status) {
        if (status == PJ_SUCCESS && account.outgoingGeneration == generation) {
            [account updateIdentifier:identifier];
            account.thread = self.thread;
            @synchronized(self) { if (![self.accounts containsObject:account]) [self.accounts addObject:account]; }
            account.registrationStatus = registrationStatus;
            account.registrationErrorCode = registrationError;
            account.registrationExpireTime = registrationExpires;
            account.registrationStatusText = registrationText;
            account.online = account.desiredRegistered;
            account.registered = account.desiredRegistered;
            completion(YES);
            if (registrationStatus > 0) [account.delegate SIPAccountRegistrationDidChange:account];
        } else {
            if (identifier != PJSUA_INVALID_ID) {
                [self performSIPOperation:^pj_status_t { return pjsua_acc_del(identifier); } completion:nil];
            }
            completion(NO);
        }
    }];
}

- (BOOL)removeAccount:(AKSIPAccount *)account {
    [self removeAccount:account completion:^(BOOL removed) {}];
    return self.isStarted && account.identifier != kAKSIPUserAgentInvalidIdentifier;
}

- (void)removeAccount:(AKSIPAccount *)account completion:(void (^)(BOOL))completion {
    [account cancelPendingOutgoingCalls];
    if (!self.isStarted || account.identifier == kAKSIPUserAgentInvalidIdentifier) { completion(NO); return; }
    [account.delegate SIPAccountWillRemove:account];
    NSInteger identifier = account.identifier;
    NSUInteger generation = account.outgoingGeneration;
    // Retain call ownership independently from account registration/deletion.
    @synchronized(self) { if (account.callsSnapshot.count > 0 && ![self.retiredAccounts containsObject:account]) [self.retiredAccounts addObject:account]; }
    [self performSIPCleanupOperation:^pj_status_t {
        if (account.identifier != identifier || account.outgoingGeneration != generation) return PJ_ECANCELLED;
        for (AKSIPCall *call in account.callsSnapshot) {
            if (call.isRecording) [call stopRecording];
        }
        return pjsua_acc_del((pjsua_acc_id)identifier);
    }
                completion:^(pj_status_t status) {
        if (status == PJ_SUCCESS && account.identifier == identifier) {
            @synchronized(self) { [self.accounts removeObject:account]; }
            [account updateIdentifier:kAKSIPUserAgentInvalidIdentifier];
        }
        [self forgetRetiredAccountIfUnused:account];
        completion(status == PJ_SUCCESS);
    }];
}

- (void)forgetRetiredAccountIfUnused:(AKSIPAccount *)account {
    @synchronized(self) { if (account.callsSnapshot.count == 0) [self.retiredAccounts removeObject:account]; }
}

- (AKSIPAccount *)accountWithIdentifier:(NSInteger)identifier {
    NSArray *registry;
    @synchronized(self) { registry = self.accounts.copy; }
    for (AKSIPAccount *account in registry) {
        if (account.identifier == identifier) {
            return account;
        }
    }
    
    return nil;
}

- (AKSIPCall *)callWithIdentifier:(NSInteger)identifier {
    NSArray *registry;
    @synchronized(self) { registry = [self.accounts arrayByAddingObjectsFromArray:self.retiredAccounts ?: @[]]; }
    for (AKSIPAccount *account in registry) {
        AKSIPCall *call = [account callWithIdentifier:identifier];
        if (call) {
            return call;
        }
    }
    
    return nil;
}

- (AKSIPCall *)callWithIdentifier:(NSInteger)identifier dialogIdentifier:(NSString *)dialogIdentifier {
    NSArray *registry;
    @synchronized(self) { registry = [self.accounts arrayByAddingObjectsFromArray:self.retiredAccounts ?: @[]]; }
    for (AKSIPAccount *account in registry) {
        for (AKSIPCall *call in account.callsSnapshot) {
            if (call.identifier == identifier && [call.dialogIdentifier isEqualToString:dialogIdentifier]) return call;
        }
    }
    return nil;
}

- (void)hangUpAllCalls {
    [self performSIPOperation:^{ pjsua_call_hangup_all(); return PJ_SUCCESS; } completion:nil];
}

- (void)startRingbackForCall:(AKSIPCall *)call {
    if ([NSThread isMainThread]) {
        [self performSIPOperation:^{ [self startRingbackForCall:call]; return PJ_SUCCESS; } completion:nil];
        return;
    }
    if (call.identifier < 0 || call.identifier >= PJSUA_MAX_CALLS) return;
    if (self.callData[call.identifier].ringbackOn) {
        return;
    }
    
    if (self.hasAudioFailure || self.ringbackSlot == PJSUA_INVALID_ID) {
        return;
    }
    if (self.ringbackCount == 0 && [self connectAudioSource:self.ringbackSlot destination:0] != PJ_SUCCESS) {
        return;
    }
    self.callData[call.identifier].ringbackOn = PJ_TRUE;
    self.ringbackCount = self.ringbackCount + 1;
}

- (void)stopRingbackForCall:(AKSIPCall *)call {
    if ([NSThread isMainThread]) {
        [self performSIPOperation:^{ [self stopRingbackForCall:call]; return PJ_SUCCESS; } completion:nil];
        return;
    }
    if (call.identifier < 0 || call.identifier >= PJSUA_MAX_CALLS) return;
    if (self.callData[call.identifier].ringbackOn) {
        self.callData[call.identifier].ringbackOn = PJ_FALSE;
        
        pj_assert(self.ringbackCount > 0);
        
        self.ringbackCount = self.ringbackCount - 1;
        if (self.ringbackCount == 0 && self.ringbackSlot != PJSUA_INVALID_ID) {
            pjsua_conf_disconnect(self.ringbackSlot, 0);
            pjmedia_tonegen_rewind(self.ringbackPort);
        }
    }
}

- (BOOL)isAudioSelectionCurrent:(NSUInteger)revision {
    return self.isStarted && revision == self.audioSelectionRevision &&
        self.audioSelectionGeneration == self.audioGeneration;
}

- (BOOL)performAudioSelection:(pj_status_t (^)(NSUInteger))operation {
    NSAssert(NSThread.isMainThread, @"Audio selection must be admitted on the main thread.");
    if (!self.isStarted) return NO;
    NSUInteger revision = ++self.audioSelectionRevision;
    self.audioSelectionGeneration = self.audioGeneration;
    self.audioCommandPending = YES;
    [self publishAudioState];
    [self performSIPOperation:^{
        if (![self isAudioSelectionCurrent:revision]) return PJ_ECANCELLED;
        return operation(revision);
    } completion:^(pj_status_t status) {
        // An older completion must not unlock a newer queued device selection.
        if (revision == self.audioSelectionRevision) {
            self.audioCommandPending = NO;
            [self publishAudioState];
        }
    }];
    return YES;
}

- (BOOL)setSoundInputDevice:(NSInteger)input soundOutputDevice:(NSInteger)output {
    if ([NSThread isMainThread]) {
        if (!self.isStarted || self.audioDeviceController.hasFailed) return NO;
        return [self performAudioSelection:^pj_status_t(NSUInteger revision) {
            if (![self isAudioSelectionCurrent:revision]) return PJ_ECANCELLED;
            return [self setSoundInputDevice:input soundOutputDevice:output] ? PJ_SUCCESS : PJ_EUNKNOWN;
        }];
    }
    if (![self isStarted]) {
        return NO;
    }

    NSUInteger generation = self.audioGeneration;
    NSUInteger revision = self.audioSelectionRevision;
    self.requestedInputDevice = input;
    self.requestedOutputDevice = output;
    pj_status_t status = [self.audioDeviceController selectInput:[self inputDeviceIDWithID:input]
                                                        output:[self outputDeviceIDWithID:output]];
    // Native device opening can block while main admits a newer selection or
    // stops this endpoint. Its completion must not clear errors or reconnect
    // conference routes that belong to the new request/lifecycle.
    if (!self.isStarted || generation != self.audioGeneration || revision != self.audioSelectionRevision) return NO;
    if (status == PJ_SUCCESS && self.audioRecoveryPending) {
        self.audioRecoveryPending = NO;
        self.audioFailureStatus = PJ_SUCCESS;
        [self publishAudioState];
        [self restoreCurrentAudioConnections];
    }
    return status == PJ_SUCCESS;
}

- (BOOL)beginOutgoingCall {
    if (!self.isStarted || self.hasAudioFailure || self.audioCommandPending) return NO;
    return [self.audioDeviceController beginOutgoingCall];
}

- (void)finishOutgoingCallForGeneration:(NSUInteger)generation {
    if (self.audioGeneration == generation) [self.audioDeviceController finishOutgoingCall];
}

- (BOOL)hasAudioFailure {
    return self.audioRecoveryPending || self.audioDeviceController.hasFailed;
}

- (void)publishAudioState {
    void (^publish)(void) = ^{ [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPUserAgentAudioStateDidChangeNotification object:self]; };
    if ([NSThread isMainThread]) publish();
    else dispatch_async(dispatch_get_main_queue(), publish);
}

- (void)audioDidFail:(int)status {
    self.audioRecoveryPending = YES;
    self.audioFailureStatus = status;
    [self publishAudioState];
}

- (void)resetAudioFailure {
    // Unlock one user-requested attempt; the visible error remains until an
    // actual hardware selection succeeds. Null sound is never success here.
    [self.audioDeviceController resetFailure];
}

- (BOOL)retrySoundAfterFailure {
    if ([NSThread isMainThread]) {
        if (!self.isStarted || !self.hasAudioFailure || self.audioCommandPending) return NO;
        NSUInteger revision = ++self.audioSelectionRevision;
        self.audioSelectionGeneration = self.audioGeneration;
        self.audioCommandPending = YES;
        [self publishAudioState];
        [self performSIPOperation:^{
            if (![self isAudioSelectionCurrent:revision]) return PJ_ECANCELLED;
            [self resetAudioFailure];
            [self updateAudioDevices];
            if (![self isAudioSelectionCurrent:revision]) return PJ_ECANCELLED;
            return self.audioDeviceController.hasFailed ? PJ_EUNKNOWN : PJ_SUCCESS;
        } completion:^(pj_status_t status) {
            if (revision != self.audioSelectionRevision) return;
            self.audioCommandPending = NO;
            if (![self isAudioSelectionCurrent:revision]) {
                [self publishAudioState];
                return;
            }
            if (status == PJ_SUCCESS && self.soundIOSelectionRetry) {
                if (!self.soundIOSelectionRetry()) [self reportAudioSelectionFailure];
            }
            [self publishAudioState];
        }];
        return YES;
    }
    if (!self.isStarted || !self.hasAudioFailure) {
        return NO;
    }
    [self resetAudioFailure];
    // Device IDs are an enumeration snapshot. Refresh after an explicit retry,
    // then map the current saved names rather than reusing possibly stale IDs.
    [self updateAudioDevices];
    if (self.audioDeviceController.hasFailed) return NO;
    BOOL succeeded = self.soundIOSelectionRetry ? self.soundIOSelectionRetry() :
        [self setSoundInputDevice:self.requestedInputDevice soundOutputDevice:self.requestedOutputDevice];
    if (!succeeded && !self.audioDeviceController.hasFailed) {
        // Mapping/enumeration may fail before a backend attempt. Keep the gate
        // closed rather than silently allowing a later implicit hardware open.
        [self.audioDeviceController reportDeviceFailure:self.audioFailureStatus operation:@"retry-selection"];
    }
    if (succeeded && !self.hasAudioFailure && self.activeCallsCount == 0 && self.ringbackSlot != PJSUA_INVALID_ID) {
        // Remove our idle ringback route. PJSUA's disconnect path schedules its
        // normal idle-close check, releasing the mic without replacing the
        // real device IDs with null IDs. An already-absent edge is harmless;
        // its graph error must not be treated as a new hardware failure.
        pjsua_conf_disconnect(self.ringbackSlot, 0);
    }
    return succeeded && !self.hasAudioFailure;
}

- (pj_status_t)connectAudioSource:(pjsua_conf_port_id)source destination:(pjsua_conf_port_id)destination {
    if ([NSThread isMainThread]) {
        if (!self.isStarted || self.hasAudioFailure) return PJ_EINVALIDOP;
        [self performSIPOperation:^{ return [self connectAudioSource:source destination:destination]; } completion:nil];
        return PJ_SUCCESS;
    }
    if (!self.isStarted) return PJ_EINVALIDOP;
    if (self.audioRecoveryPending && !self.audioDeviceController.hasFailed) return self.audioFailureStatus;
    return [self.audioDeviceController connectSource:source destination:destination];
}

- (void)reportAudioSelectionFailure {
    if (!self.isStarted) return;
    self.audioRecoveryPending = YES;
    self.audioFailureStatus = PJ_EUNKNOWN;
    [self publishAudioState];
    [self performSIPOperation:^{
        [self.audioDeviceController reportDeviceFailure:PJ_EUNKNOWN operation:@"retry-selection"];
        return PJ_EUNKNOWN;
    } completion:nil];
}

- (void)reportAudioFailure:(pj_status_t)status operation:(NSString *)operation {
    if ([NSThread isMainThread]) {
        if ([AKAudioDeviceController isAudioDeviceFailure:status] && self.isStarted) {
            self.audioRecoveryPending = YES;
            self.audioFailureStatus = status;
            [self publishAudioState];
        }
        [self performSIPOperation:^{ [self reportAudioFailure:status operation:operation]; return status; } completion:nil];
        return;
    }
    if (!self.isStarted) return;
    [self.audioDeviceController reportAudioFailure:status operation:operation];
}

- (void)restoreCurrentAudioConnections {
    // The callback snapshots the native dialog identity and verifies it again
    // on main; numeric call slots alone are not safe across redial/replacement.
    for (AKSIPAccount *account in [self accountCollectionsSnapshot]) {
        for (AKSIPCall *call in [account callsSnapshot]) {
            if (call.state != kAKSIPCallDisconnectedState && call.isActive) {
                pjsua_call_info info;
                if (pjsua_call_get_info((pjsua_call_id)call.identifier, &info) != PJ_SUCCESS ||
                    ![[NSString stringWithPJString:info.call_id] isEqualToString:call.dialogIdentifier]) continue;
                // NONE must not synthesize a callback that stops the ringback
                // we are about to restore for a still-ringing outgoing call.
                if (info.media_cnt > 0 && info.media[0].type == PJMEDIA_TYPE_AUDIO &&
                    (info.media[0].status == PJSUA_CALL_MEDIA_ACTIVE ||
                     info.media[0].status == PJSUA_CALL_MEDIA_LOCAL_HOLD ||
                     info.media[0].status == PJSUA_CALL_MEDIA_REMOTE_HOLD)) {
                    PJSUAOnCallMediaState((pjsua_call_id)call.identifier);
                }
                if (info.role == PJSIP_ROLE_UAC && call.state == kAKSIPCallEarlyState &&
                    call.lastStatus == PJSIP_SC_RINGING &&
                    (info.media_cnt == 0 || info.media[0].status == PJSUA_CALL_MEDIA_NONE)) {
                    [self startRingbackForCall:call];
                }
            }
        }
    }
}

- (int)inputDeviceIDWithID:(NSInteger)deviceID {
    return deviceID >= 0 ? (int)deviceID : PJMEDIA_AUD_DEFAULT_CAPTURE_DEV;
}

- (int)outputDeviceIDWithID:(NSInteger)deviceID {
    return deviceID >= 0 ? (int)deviceID : PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
}

- (BOOL)stopSound {
    if ([NSThread isMainThread]) {
        if (!self.isStarted) return NO;
        [self performSIPOperation:^{ return [self stopSound] ? PJ_SUCCESS : PJ_EUNKNOWN; } completion:nil];
        return YES;
    }
    if (![self isStarted]) {
        return NO;
    }
    
    pj_status_t status = [self.audioDeviceController useNullSoundDevice];
    return status == PJ_SUCCESS;
}

// This method will leave application silent. |setSoundInputDevice:soundOutputDevice:| must be called after calling this
// method to set sound IO. Usually application controller is responsible of sending
// |setSoundInputDevice:soundOutputDevice:| to set sound IO after this method is called.
- (void)updateAudioDevices {
    if ([NSThread isMainThread]) {
        [self performSIPOperation:^{ [self updateAudioDevices]; return PJ_SUCCESS; } completion:nil];
        return;
    }
    if (![self isStarted]) {
        return;
    }
    
    // Never tear down a backend whose stream could not be stopped. Preserve
    // the failure latch across device-list events: they are not user retries.
    if (![self stopSound]) {
        return;
    }
    pjmedia_snd_deinit();
    pj_status_t status = pjmedia_snd_init(pjsua_get_pool_factory());
    if (status != PJ_SUCCESS) {
        [self.audioDeviceController reportDeviceFailure:status operation:@"device-refresh"];
    }
}

- (void)updateCodecs {
    if (!self.mediaEndpointReady || [NSThread isMainThread] ||
        self.state == AKSIPUserAgentStateStopped || self.state == AKSIPUserAgentStateStopping) {
        return;
    }
    enum { kCodecInfoSize = 64 };
    pjsua_codec_info codecInfo[kCodecInfoSize];
    unsigned codecCount = kCodecInfoSize;
    pj_status_t status = pjsua_enum_codecs(codecInfo, &codecCount);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error getting list of codecs");
    } else {
        NSUInteger revision = self.codecRevision;
        static NSString * const kPCMU = @"PCMU/8000/1";
        static NSString * const kPCMA = @"PCMA/8000/1";
        for (NSUInteger i = 0; i < codecCount; i++) {
            NSString *codecIdentifier = [NSString stringWithPJString:codecInfo[i].codec_id];
            pj_uint8_t defaultPriority = (pj_uint8_t)[self priorityForCodec:codecIdentifier];
            if (self.usesG711Only) {
                pj_uint8_t priority = 0;
                if ([codecIdentifier isEqualToString:kPCMU] || [codecIdentifier isEqualToString:kPCMA]) {
                    priority = defaultPriority;
                }
                status = pjsua_codec_set_priority(&codecInfo[i].codec_id, priority);
                if (status != PJ_SUCCESS) {
                    NSLog(@"Error setting codec priority to zero");
                }
            } else {
                status = pjsua_codec_set_priority(&codecInfo[i].codec_id, defaultPriority);
                if (status != PJ_SUCCESS) {
                    NSLog(@"Error setting codec priority to the default value");
                }
            }
        }
        self.appliedCodecRevision = revision;
    }
}

- (NSUInteger)priorityForCodec:(NSString *)identifier {
    static NSDictionary *priorities = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        priorities = @{
                       @"opus/48000/2":  @(130),
                       @"G722/16000/1":  @(129),
                       @"PCMA/8000/1":   @(128),
                       @"PCMU/8000/1":   @(127),
                       @"speex/32000/1": @(0),
                       @"speex/16000/1": @(0),
                       @"speex/8000/1":  @(0),
                       @"iLBC/8000/1":   @(0),
                       @"GSM/8000/1":    @(0)
                       };
    });
    
    return [priorities[identifier] unsignedIntegerValue];
}

@end
