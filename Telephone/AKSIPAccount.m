//
//  AKSIPAccount.m
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

#import "AKSIPAccount.h"

#import "AKNSString+PJSUA.h"
#import "AKSIPURI.h"
#import "AKSIPUserAgent.h"
#import "AKSIPCall.h"
#import "PJSUACallInfo.h"

#import "Telephone-Swift.h"

NS_ASSUME_NONNULL_BEGIN

const NSInteger kAKSIPAccountDefaultSIPProxyPort = 0;
const NSInteger kAKSIPAccountDefaultReregistrationTime = 300;
const Transport kAKSIPAccountDefaultTransport = TransportUDP;
const NSInteger kAKSIPAccountRegistrationExpireTimeNotSpecified = PJSIP_EXPIRES_NOT_SPECIFIED;

@interface AKSIPCallParameters : NSObject

@property(nonatomic, readonly) URI *destination;
@property(nonatomic, readonly) pjsua_acc_id account;
@property(nonatomic) NSUInteger audioGeneration;
@property(nonatomic) NSUInteger accountGeneration;
@property(nonatomic, readonly) void (^ _Nonnull completion)(BOOL, PJSUACallInfo * _Nullable);

- (instancetype)initWithDestination:(URI *)destination
                            account:(pjsua_acc_id)account
                         completion:(void (^ _Nonnull)(BOOL, PJSUACallInfo * _Nullable))completion;

@end

@interface AKSIPAccount () {
    NSString *_uuid;
}

@property(nonatomic, copy) NSString *username;
@property(nonatomic) NSInteger identifier;
@property(atomic) NSUInteger outgoingGeneration;
@property(nonatomic) NSMutableOrderedSet<NSString *> *disconnectedDialogIdentifiers;

@property(nonatomic, readonly) NSMutableArray *calls;
@property(nonatomic, readonly) AKSIPURIParser *parser;

@end

NS_ASSUME_NONNULL_END

@implementation AKSIPAccount

- (NSString *)uuid {
    return _uuid;
}

- (void)setProxyPort:(NSUInteger)port {
    if (port >= 0 && port <= 65535) {
        _proxyPort = port;
    } else {
        _proxyPort = kAKSIPAccountDefaultSIPProxyPort;
    }
}

- (void)setReregistrationTime:(NSUInteger)seconds {
    const NSInteger reregistrationTimeMin = 60;
    const NSInteger reregistrationTimeMax = 3600;
    if (seconds == 0) {
        _reregistrationTime = kAKSIPAccountDefaultReregistrationTime;
    } else if (seconds < reregistrationTimeMin) {
        _reregistrationTime = reregistrationTimeMin;
    } else if (seconds > reregistrationTimeMax) {
        _reregistrationTime = reregistrationTimeMax;
    } else {
        _reregistrationTime = seconds;
    }
}

- (BOOL)isRegistered {
    return self.registrationStatus / 100 == 2 && self.registrationExpireTime > 0;
}

- (void)setRegistered:(BOOL)value {
    self.desiredRegistered = value;
    NSInteger identifier = self.identifier;
    if (identifier == kAKSIPUserAgentInvalidIdentifier) return;
    NSUInteger generation = self.outgoingGeneration;
    [[AKSIPUserAgent sharedUserAgent] performSIPOperation:^pj_status_t {
        if (self.identifier != identifier || self.outgoingGeneration != generation) return PJ_ECANCELLED;
        pj_status_t status = pjsua_acc_set_registration((pjsua_acc_id)identifier, value ? PJ_TRUE : PJ_FALSE);
        if (status == PJ_SUCCESS) pjsua_acc_set_online_status((pjsua_acc_id)identifier, value ? PJ_TRUE : PJ_FALSE);
        return status;
    } completion:^(pj_status_t status) {
        if (status == PJ_SUCCESS) self.online = value;
    }];
}

- (void)setOnline:(BOOL)value {
    _online = value;
    NSInteger identifier = self.identifier;
    if (identifier == kAKSIPUserAgentInvalidIdentifier) return;
    NSUInteger generation = self.outgoingGeneration;
    [[AKSIPUserAgent sharedUserAgent] performSIPOperation:^pj_status_t {
        if (self.identifier != identifier || self.outgoingGeneration != generation) return PJ_ECANCELLED;
        return pjsua_acc_set_online_status((pjsua_acc_id)identifier, value ? PJ_TRUE : PJ_FALSE);
    } completion:nil];
}

- (NSString *)onlineStatusText { return self.isOnline ? @"Online" : @"Offline"; }

- (BOOL)hasUnansweredIncomingCalls {
    for (AKSIPCall *call in self.callsSnapshot) {
        if (call.isActive &&
            call.isIncoming &&
            (call.state == kAKSIPCallIncomingState || call.state == kAKSIPCallEarlyState)) {
            return YES;
        }
    }
    return NO;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict parser:(AKSIPURIParser *)parser {
    NSParameterAssert([dict[AKSIPAccountKeys.uuid] length] > 0);
    NSParameterAssert(dict[AKSIPAccountKeys.fullName]);
    NSParameterAssert(dict[AKSIPAccountKeys.realm]);
    NSParameterAssert(dict[AKSIPAccountKeys.username]);
    NSParameterAssert(dict[AKSIPAccountKeys.domain]);
    
    self = [super init];
    if (self == nil) {
        return nil;
    }

    SIPAddress *address = nil;
    if ([dict[AKSIPAccountKeys.sipAddress] length] > 0) {
        address = [[SIPAddress alloc] initWithString:dict[AKSIPAccountKeys.sipAddress]];
    } else {
        address = [[SIPAddress alloc] initWithUser:dict[AKSIPAccountKeys.username] host:dict[AKSIPAccountKeys.domain]];
    }

    _uuid = [dict[AKSIPAccountKeys.uuid] copy];
    if ([dict[AKSIPAccountKeys.transport] isEqualToString:AKSIPAccountKeys.transportTCP]) {
        _transport = TransportTCP;
    } else if ([dict[AKSIPAccountKeys.transport] isEqualToString:AKSIPAccountKeys.transportTLS]) {
        _transport = TransportTLS;
    } else {
        _transport = TransportUDP;
    }
    _uri = [[URI alloc] initWithUser:address.user
                                host:address.host
                         displayName:dict[AKSIPAccountKeys.fullName]
                           transport:_transport];

    _fullName = [dict[AKSIPAccountKeys.fullName] copy];
    _SIPAddress = address.stringValue;
    _registrar = [[ServiceAddress alloc] initWithString:([dict[AKSIPAccountKeys.registrar] length] > 0 ?
                                                         dict[AKSIPAccountKeys.registrar] :
                                                         dict[AKSIPAccountKeys.domain])];
    _realm = [dict[AKSIPAccountKeys.realm] copy];
    _username = [dict[AKSIPAccountKeys.username] copy];
    _domain = [dict[AKSIPAccountKeys.domain] copy];
    if ([dict[AKSIPAccountKeys.useProxy] boolValue]) {
        _proxyHost = [dict[AKSIPAccountKeys.proxyHost] copy];
        self.proxyPort = [dict[AKSIPAccountKeys.proxyPort] integerValue];
    }
    self.reregistrationTime = [dict[AKSIPAccountKeys.reregistrationTime] integerValue];
    _usesIPv6 = [dict[AKSIPAccountKeys.ipVersion] isEqualToString:AKSIPAccountKeys.ipVersion6];
    _updatesContactHeader = [dict[AKSIPAccountKeys.updateContactHeader] boolValue];
    _updatesViaHeader = [dict[AKSIPAccountKeys.updateViaHeader] boolValue];
    _updatesSDP = [dict[AKSIPAccountKeys.updateSDP] boolValue];

    _identifier = kAKSIPUserAgentInvalidIdentifier;
    _outgoingGeneration = 1;
    _desiredRegistered = YES;
    _registrationExpireTime = kAKSIPAccountRegistrationExpireTimeNotSpecified;
    _registrationStatusText = @"";
    
    _calls = [[NSMutableArray alloc] init];
    _disconnectedDialogIdentifiers = [NSMutableOrderedSet new];
    _parser = parser;
    
    return self;
}

- (NSString *)description {
    return [self SIPAddress];
}

- (void)updateUsername:(NSString *)username {
    self.username = username;
}

- (void)updateIdentifier:(NSInteger)identifier {
    if (self.identifier != identifier) [self cancelPendingOutgoingCalls];
    self.identifier = identifier;
}

- (void)cancelPendingOutgoingCalls { self.outgoingGeneration++; }

- (void)makeCallTo:(URI *)uri label:(NSString *)label {
    NSLog(@"Not calling %@", uri);
}

- (void)makeCallTo:(AKSIPURI *)destination completion:(void (^ _Nonnull)(AKSIPCall * _Nullable))completion {
    AKSIPUserAgent *agent = [AKSIPUserAgent sharedUserAgent];
    if (self.identifier == kAKSIPUserAgentInvalidIdentifier || ![agent beginOutgoingCall]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    NSUInteger accountGeneration = self.outgoingGeneration;
    URI *uri = [[URI alloc] initWithURI:destination transport:self.transport];
    void (^onCallMakeCompletion)(BOOL, PJSUACallInfo * _Nullable) = ^(BOOL success, PJSUACallInfo * _Nullable call) {
        if (success && self.outgoingGeneration == accountGeneration &&
            self.identifier != kAKSIPUserAgentInvalidIdentifier && call.state != kAKSIPCallDisconnectedState) {
            completion([self addCallWithInfo:call]);
        } else {
            NSLog(@"Error making call to %@ via account %@", uri, self);
            completion(nil);
        }
    };
    AKSIPCallParameters *parameters = [[AKSIPCallParameters alloc] initWithDestination:uri
                                                                               account:(pjsua_acc_id)self.identifier
                                                                            completion:onCallMakeCompletion];
    parameters.audioGeneration = agent.audioGeneration;
    parameters.accountGeneration = accountGeneration;
    assert(self.thread);
    [self performSelector:@selector(thread_makeCallWithParameters:) onThread:self.thread withObject:parameters waitUntilDone:NO];
}

- (void)thread_makeCallWithParameters:(AKSIPCallParameters *)parameters {
    // The owner may have requested shutdown while this request was queued.
    // audioGeneration is the only atomic cross-thread lifecycle token used here.
    if ([AKSIPUserAgent sharedUserAgent].audioGeneration != parameters.audioGeneration ||
        self.outgoingGeneration != parameters.accountGeneration || self.identifier != parameters.account) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AKSIPUserAgent sharedUserAgent] finishOutgoingCallForGeneration:parameters.audioGeneration];
            parameters.completion(NO, nil);
        });
        return;
    }
    pj_str_t uri = parameters.destination.stringValue.pjString;
    pjsua_call_id callID = PJSUA_INVALID_ID;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    pj_status_t makeStatus = pjsua_call_make_call(parameters.account, &uri, 0, NULL, NULL, &callID);
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - started;
    // No destination/account values in this audio diagnostic. The SDK can open
    // sound internally after idle auto-close, bypassing the conference wrapper.
    if (makeStatus != PJ_SUCCESS) {
        PJ_LOG(3, ("AKAudio", "make-call end status=%d elapsed=%.3fs thread=control", makeStatus, elapsed));
    }
    BOOL success = makeStatus == PJ_SUCCESS;
    PJSUACallInfo *infoWrapper = nil;
    if (success) {
        pjsua_call_info info;
        success = pjsua_call_get_info(callID, &info) == PJ_SUCCESS;
        if (success) {
            infoWrapper = [[PJSUACallInfo alloc] initWithInfo:info parser:self.parser];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // The controller is main-thread owned. Classify before changing audio
        // state; ordinary SIP failures must not disable a working device.
        AKSIPUserAgent *agent = [AKSIPUserAgent sharedUserAgent];
        [agent finishOutgoingCallForGeneration:parameters.audioGeneration];
        if (agent.isStarted && agent.audioGeneration == parameters.audioGeneration &&
            self.outgoingGeneration == parameters.accountGeneration && self.identifier == parameters.account) {
            [agent reportAudioFailure:makeStatus operation:@"make-call"];
            parameters.completion(success, infoWrapper);
        } else {
            // Never let a delayed result from the previous SIP instance latch
            // new audio or attach its obsolete call identifier after restart.
            if (success && infoWrapper != nil && agent.audioGeneration == parameters.audioGeneration) {
                NSInteger staleID = infoWrapper.identifier;
                NSString *dialog = infoWrapper.dialogIdentifier;
                [agent performSIPOperation:^pj_status_t {
                    pjsua_call_info current;
                    if (pjsua_call_get_info((pjsua_call_id)staleID, &current) != PJ_SUCCESS ||
                        ![[NSString stringWithPJString:current.call_id] isEqualToString:dialog]) return PJ_ECANCELLED;
                    return pjsua_call_hangup((pjsua_call_id)staleID, 0, NULL, NULL);
                } completion:nil];
            }
            parameters.completion(NO, nil);
        }
    });
}

- (NSArray<AKSIPCall *> *)callsSnapshot { @synchronized(self) { return [self.calls copy]; } }

- (AKSIPCall *)addCallWithInfo:(PJSUACallInfo *)info {
    @synchronized(self) {
    if ([self.disconnectedDialogIdentifiers containsObject:info.dialogIdentifier]) return nil;
    AKSIPCall *call = [self callWithIdentifier:info.identifier];
    if (call != nil && ![call.dialogIdentifier isEqualToString:info.dialogIdentifier]) call = nil;
    if (!call) {
        call = [[AKSIPCall alloc] initWithSIPAccount:self info:info];
        [self.calls addObject:call];
    }
    return call;
    }
}

- (nullable AKSIPCall *)callWithIdentifier:(NSInteger)identifier {
    for (AKSIPCall *call in self.callsSnapshot) {
        if (call.identifier == identifier) {
            return call;
        }
    }
    return nil;
}

- (void)removeCall:(AKSIPCall *)call {
    @synchronized(self) {
        if (call.state == kAKSIPCallDisconnectedState && call.dialogIdentifier.length > 0) {
            [self.disconnectedDialogIdentifiers addObject:call.dialogIdentifier];
            if (self.disconnectedDialogIdentifiers.count > 128) [self.disconnectedDialogIdentifiers removeObjectAtIndex:0];
        }
        [self.calls removeObject:call];
    }
}

- (void)removeAllCalls {
    @synchronized(self) { [self.calls removeAllObjects]; }
}

- (NSInteger)activeCallsCount {
    NSInteger count = 0;
    for (AKSIPCall *call in self.callsSnapshot) {
        if (call.isActive) {
            count++;
        }
    }
    return count;
}

@end

@implementation AKSIPCallParameters

- (instancetype)initWithDestination:(URI *)destination
                            account:(pjsua_acc_id)account
                         completion:(void (^ _Nonnull)(BOOL, PJSUACallInfo * _Nullable))completion {
    if ((self = [super init])) {
        _destination = destination;
        _account = account;
        _completion = completion;
    }
    return self;
}

@end
