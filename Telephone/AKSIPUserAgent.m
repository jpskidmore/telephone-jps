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
@property(nonatomic) BOOL audioRecoveryPending;
@property(nonatomic) pj_status_t audioFailureStatus;
@property(atomic, readwrite) NSUInteger audioGeneration;
@property(nonatomic) NSInteger requestedInputDevice;
@property(nonatomic) NSInteger requestedOutputDevice;
- (void)restoreCurrentAudioConnections;
- (void)audioDidFail:(int)status;

@property(nonatomic) pj_pool_t *pool;

@property(nonatomic, readonly) NSMutableArray *accounts;

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
    for (AKSIPAccount *account in self.accounts) {
        count += [account activeCallsCount];
    }
    return count;
}

- (BOOL)hasUnansweredIncomingCalls {
    for (AKSIPAccount *account in self.accounts) {
        if (account.hasUnansweredIncomingCalls) {
            return YES;
        }
    }
    return NO;
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
        [self updateCodecs];
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
    if (pj_init() != PJ_SUCCESS) {
        NSLog(@"Error initializing PJSIP");
        return;
    }
    self.audioGeneration++;
    self.state = AKSIPUserAgentStateStarting;
    void (^completion)(BOOL) = ^(BOOL didStart) {
        self.state = didStart ? AKSIPUserAgentStateStarted : AKSIPUserAgentStateStopped;
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
    dispatch_async(dispatch_get_main_queue(), ^{ block(flag); });
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
    if (self.ringbackPort && self.ringbackSlot != PJSUA_INVALID_ID) {
        pjsua_conf_remove_port(self.ringbackSlot);
        self.ringbackSlot = PJSUA_INVALID_ID;
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
}

- (void)finishStopping {
    pj_shutdown();
    [self.accounts removeAllObjects];
    self.state = AKSIPUserAgentStateStopped;
    BOOL hadAudioFailure = self.hasAudioFailure;
    [self.audioDeviceController resetFailure];
    self.audioRecoveryPending = NO;
    self.audioFailureStatus = PJ_SUCCESS;
    if (hadAudioFailure) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPUserAgentAudioStateDidChangeNotification object:self];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPUserAgentDidFinishStoppingNotification object:self];
}

- (BOOL)addAccount:(AKSIPAccount *)anAccount withPassword:(NSString *)aPassword {
    if ([[self delegate] respondsToSelector:@selector(SIPUserAgentShouldAddAccount:)]) {
        if (![[self delegate] SIPUserAgentShouldAddAccount:anAccount]) {
            return NO;
        }
    }
    
    pjsua_acc_config accountConfig;
    pjsua_acc_config_default(&accountConfig);
    
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
        return NO;
    }
    
    [anAccount updateIdentifier:accountIdentifier];
    [anAccount setThread:self.thread];
    
    [[self accounts] addObject:anAccount];
    
    [anAccount setOnline:YES];

    return YES;
}

- (BOOL)removeAccount:(AKSIPAccount *)anAccount {
    if (![self isStarted] ||
        [anAccount identifier] == kAKSIPUserAgentInvalidIdentifier) {
        return NO;
    }

    [anAccount.delegate SIPAccountWillRemove:anAccount];
    
    [anAccount removeAllCalls];
    
    pj_status_t status = pjsua_acc_del((pjsua_acc_id)[anAccount identifier]);
    if (status != PJ_SUCCESS) {
        return NO;
    }
    
    [[self accounts] removeObject:anAccount];
    [anAccount updateIdentifier:kAKSIPUserAgentInvalidIdentifier];
    
    return YES;
}

- (AKSIPAccount *)accountWithIdentifier:(NSInteger)identifier {
    for (AKSIPAccount *account in self.accounts) {
        if (account.identifier == identifier) {
            return account;
        }
    }
    
    return nil;
}

- (AKSIPCall *)callWithIdentifier:(NSInteger)identifier {
    for (AKSIPAccount *account in self.accounts) {
        AKSIPCall *call = [account callWithIdentifier:identifier];
        if (call) {
            return call;
        }
    }
    
    return nil;
}

- (void)hangUpAllCalls {
    pjsua_call_hangup_all();
}

- (void)startRingbackForCall:(AKSIPCall *)call {
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

- (BOOL)setSoundInputDevice:(NSInteger)input soundOutputDevice:(NSInteger)output {
    if (![self isStarted]) {
        return NO;
    }

    self.requestedInputDevice = input;
    self.requestedOutputDevice = output;
    pj_status_t status = [self.audioDeviceController selectInput:[self inputDeviceIDWithID:input]
                                                        output:[self outputDeviceIDWithID:output]];
    if (status == PJ_SUCCESS && self.audioRecoveryPending) {
        self.audioRecoveryPending = NO;
        self.audioFailureStatus = PJ_SUCCESS;
        [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPUserAgentAudioStateDidChangeNotification object:self];
        [self restoreCurrentAudioConnections];
    }
    return status == PJ_SUCCESS;
}

- (BOOL)beginOutgoingCall {
    if (!self.isStarted || self.hasAudioFailure) return NO;
    return [self.audioDeviceController beginOutgoingCall];
}

- (void)finishOutgoingCallForGeneration:(NSUInteger)generation {
    if (self.audioGeneration == generation) [self.audioDeviceController finishOutgoingCall];
}

- (BOOL)hasAudioFailure {
    return self.audioRecoveryPending || self.audioDeviceController.hasFailed;
}

- (void)audioDidFail:(int)status {
    self.audioRecoveryPending = YES;
    self.audioFailureStatus = status;
    [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPUserAgentAudioStateDidChangeNotification object:self];
}

- (void)resetAudioFailure {
    // Unlock one user-requested attempt; the visible error remains until an
    // actual hardware selection succeeds. Null sound is never success here.
    [self.audioDeviceController resetFailure];
}

- (BOOL)retrySoundAfterFailure {
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
    if (!self.isStarted) return PJ_EINVALIDOP;
    if (self.audioRecoveryPending && !self.audioDeviceController.hasFailed) return self.audioFailureStatus;
    return [self.audioDeviceController connectSource:source destination:destination];
}

- (void)reportAudioFailure:(pj_status_t)status operation:(NSString *)operation {
    if (!self.isStarted) return;
    [self.audioDeviceController reportAudioFailure:status operation:operation];
}

- (void)restoreCurrentAudioConnections {
    // The callback snapshots the native dialog identity and verifies it again
    // on main; numeric call slots alone are not safe across redial/replacement.
    for (AKSIPAccount *account in [self.accounts copy]) {
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
    if (self.state == AKSIPUserAgentStateStopped || self.state == AKSIPUserAgentStateStopping) {
        return;
    }
    enum { kCodecInfoSize = 64 };
    pjsua_codec_info codecInfo[kCodecInfoSize];
    unsigned codecCount = kCodecInfoSize;
    pj_status_t status = pjsua_enum_codecs(codecInfo, &codecCount);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error getting list of codecs");
    } else {
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
