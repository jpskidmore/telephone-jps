//
//  AKSIPCall.m
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

#import "AKSIPCall.h"

#import "AKNSString+PJSUA.h"
#import "AKSIPAccount.h"
#import "AKStereoRecording.h"
#import "AKSIPURI.h"
#import "AKSIPUserAgent.h"
#import "PJSUACallInfo.h"

#import "Telephone-Swift.h"

#define THIS_FILE "AKSIPCall.m"

@interface AKSIPCall () {
    URI *_remote;
    BOOL _incoming;
    BOOL _missed;
    pjsua_recorder_id _localRecorderIdentifier;
    pjsua_conf_port_id _localRecorderPort;
    pjsua_recorder_id _remoteRecorderIdentifier;
    pjsua_conf_port_id _remoteRecorderPort;
}

@property(nonatomic, getter=isMicrophoneMuted) BOOL microphoneMuted;
@property(nonatomic, readwrite, copy, nullable) NSURL *recordingURL;
@property(nonatomic, copy, nullable) NSURL *localRecordingURL;
@property(nonatomic, copy, nullable) NSURL *remoteRecordingURL;
@property(nonatomic, copy, nullable) NSURL *recordingTemporaryDirectoryURL;

@end

@implementation AKSIPCall

- (void)setDelegate:(id<AKSIPCallDelegate>)aDelegate {
    if (_delegate == aDelegate) {
        return;
    }
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    if (_delegate != nil) {
        [notificationCenter removeObserver:_delegate name:nil object:self];
    }
    
    if (aDelegate != nil) {
        // Subscribe to notifications
        if ([aDelegate respondsToSelector:@selector(SIPCallCalling:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallCalling:)
                                       name:AKSIPCallCallingNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallIncoming:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallIncoming:)
                                       name:AKSIPCallIncomingNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallEarly:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallEarly:)
                                       name:AKSIPCallEarlyNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallConnecting:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallConnecting:)
                                       name:AKSIPCallConnectingNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallDidConfirm:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallDidConfirm:)
                                       name:AKSIPCallDidConfirmNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallDidDisconnect:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallDidDisconnect:)
                                       name:AKSIPCallDidDisconnectNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallMediaDidBecomeActive:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallMediaDidBecomeActive:)
                                       name:AKSIPCallMediaDidBecomeActiveNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallDidLocalHold:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallDidLocalHold:)
                                       name:AKSIPCallDidLocalHoldNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallDidRemoteHold:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallDidRemoteHold:)
                                       name:AKSIPCallDidRemoteHoldNotification
                                     object:self];
        }
        if ([aDelegate respondsToSelector:@selector(SIPCallTransferStatusDidChange:)]) {
            [notificationCenter addObserver:aDelegate
                                   selector:@selector(SIPCallTransferStatusDidChange:)
                                       name:AKSIPCallTransferStatusDidChangeNotification
                                     object:self];
        }
    }
    
    _delegate = aDelegate;
}

- (URI *)remote {
    return _remote;
}

- (BOOL)isIncoming {
    return _incoming;
}

- (BOOL)isMissed {
    return _missed;
}

- (void)setMissed:(BOOL)flag {
    _missed = flag;
}

- (BOOL)isActive {
    if ([self identifier] == kAKSIPUserAgentInvalidIdentifier) {
        return NO;
    }
    
    return (pjsua_call_is_active((pjsua_call_id)[self identifier])) ? YES : NO;
}

- (BOOL)isOnLocalHold {
    if ([self identifier] == kAKSIPUserAgentInvalidIdentifier) {
        return NO;
    }
    
    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)[self identifier], &callInfo);
    
    return (callInfo.media[0].status == PJSUA_CALL_MEDIA_LOCAL_HOLD) ? YES : NO;
}

- (BOOL)isOnRemoteHold {
    if ([self identifier] == kAKSIPUserAgentInvalidIdentifier) {
        return NO;
    }
    
    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)[self identifier], &callInfo);
    
    return (callInfo.media[0].status == PJSUA_CALL_MEDIA_REMOTE_HOLD) ? YES : NO;
}


#pragma mark -

- (instancetype)initWithSIPAccount:(AKSIPAccount *)account info:(PJSUACallInfo *)info {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _account = account;
    _identifier = info.identifier;

    _date = [NSDate date];

    _incoming = info.isIncoming;
    _missed = _incoming;
    _localRecorderIdentifier = PJSUA_INVALID_ID;
    _localRecorderPort = PJSUA_INVALID_ID;
    _remoteRecorderIdentifier = PJSUA_INVALID_ID;
    _remoteRecorderPort = PJSUA_INVALID_ID;
    _state = info.state;
    _stateText = info.stateText;
    _lastStatus = info.lastStatus;
    _lastStatusText = info.lastStatusText;
    _localURI = info.localURI;
    _remoteURI = info.remoteURI;
    _remote = [[URI alloc] initWithURI:_remoteURI];

    return self;
}

- (void)dealloc {
    [self stopRecording];
    [self setDelegate:nil];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ <=> %@", [self localURI], [self remoteURI]];
}

- (void)answer {
    pj_status_t status = pjsua_call_answer((pjsua_call_id)[self identifier], PJSIP_SC_OK, NULL, NULL);
    if (status == PJ_SUCCESS) {
        self.missed = NO;
    } else {
        NSLog(@"Error answering call %@", self);
    }
}

- (void)hangUp {
    if (([self identifier] == kAKSIPUserAgentInvalidIdentifier) || ([self state] == kAKSIPCallDisconnectedState)) {
        return;
    }
    
    pj_status_t status = pjsua_call_hangup((pjsua_call_id)[self identifier], 0, NULL, NULL);
    if (status == PJ_SUCCESS) {
        self.missed = NO;
    } else {
        NSLog(@"Error hanging up call %@", self);
    }
}

- (void)attendedTransferToCall:(AKSIPCall *)destinationCall {
    [self setTransferStatus:kAKSIPUserAgentInvalidIdentifier];
    [self setTransferStatusText:@""];
    pj_status_t status = pjsua_call_xfer_replaces((pjsua_call_id)[self identifier],
                                                  (pjsua_call_id)[destinationCall identifier],
                                                  PJSUA_XFER_NO_REQUIRE_REPLACES,
                                                  NULL);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error transfering call %@", self);
    }
}

- (void)sendRingingNotification {
    pj_status_t status = pjsua_call_answer((pjsua_call_id)[self identifier], PJSIP_SC_RINGING, NULL, NULL);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error sending ringing notification in call %@", self);
    }
}

- (void)replyWithTemporarilyUnavailable {
    pj_status_t status = pjsua_call_answer((pjsua_call_id)[self identifier], PJSIP_SC_TEMPORARILY_UNAVAILABLE, NULL, NULL);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error replying with 480 Temporarily Unavailable");
    }
}

- (void)replyWithBusyHere {
    pj_status_t status = pjsua_call_answer((pjsua_call_id)[self identifier], PJSIP_SC_BUSY_HERE, NULL, NULL);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error replying with 486 Busy Here");
    }
}

- (void)sendDTMFDigits:(NSString *)digits {
    pj_status_t status;
    pj_str_t pjDigits = [digits pjString];
    
    // Try to send RFC2833 DTMF first.
    status = pjsua_call_dial_dtmf((pjsua_call_id)[self identifier], &pjDigits);
    
    if (status != PJ_SUCCESS) {  // Okay, that didn't work. Send INFO DTMF.
        const pj_str_t kSIPINFO = pj_str("INFO");
        
        for (NSUInteger i = 0; i < [digits length]; ++i) {
            pjsua_msg_data messageData;
            pjsua_msg_data_init(&messageData);
            messageData.content_type = pj_str("application/dtmf-relay");
            
            NSString *messageBody = [NSString stringWithFormat:@"Signal=%C\r\nDuration=300",
                                     [digits characterAtIndex:i]];
            messageData.msg_body = [messageBody pjString];
            
            status = pjsua_call_send_request((pjsua_call_id)[self identifier], &kSIPINFO, &messageData);
            if (status != PJ_SUCCESS) {
                NSLog(@"Error sending DTMF");
            }
        }
    }
}

- (void)muteMicrophone {
    if ([self isMicrophoneMuted] || [self state] != kAKSIPCallConfirmedState) {
        return;
    }
    
    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)[self identifier], &callInfo);
    
    pj_status_t status = pjsua_conf_disconnect(0, callInfo.media[0].stream.aud.conf_slot);
    if (status == PJ_SUCCESS) {
        [self setMicrophoneMuted:YES];
        if ([self isRecording]) {
            pjsua_conf_disconnect(0, _localRecorderPort);
        }
    } else {
        NSLog(@"Error muting microphone in call %@", self);
    }
}

- (void)unmuteMicrophone {
    if (![self isMicrophoneMuted] || [self state] != kAKSIPCallConfirmedState) {
        return;
    }
    
    pjsua_call_info callInfo;
    pjsua_call_get_info((pjsua_call_id)[self identifier], &callInfo);
    
    pj_status_t status = pjsua_conf_connect(0, callInfo.media[0].stream.aud.conf_slot);
    if (status == PJ_SUCCESS) {
        [self setMicrophoneMuted:NO];
        if ([self isRecording] && ![self isOnLocalHold]) {
            pjsua_conf_connect(0, _localRecorderPort);
        }
    } else {
        NSLog(@"Error unmuting microphone in call %@", self);
    }
}

- (void)toggleMicrophoneMute {
    if ([self isMicrophoneMuted]) {
        [self unmuteMicrophone];
    } else {
        [self muteMicrophone];
    }
}

- (void)hold {
    if ([self state] == kAKSIPCallConfirmedState && ![self isOnRemoteHold]) {
        pj_status_t status = pjsua_call_set_hold((pjsua_call_id)[self identifier], NULL);
        if (status == PJ_SUCCESS && [self isRecording]) {
            pjsua_conf_disconnect(0, _localRecorderPort);
        }
    }
}

- (void)unhold {
    if ([self state] == kAKSIPCallConfirmedState) {
        pjsua_call_reinvite((pjsua_call_id)[self identifier], PJ_TRUE, NULL);
    }
}

- (void)toggleHold {
    if ([self isOnLocalHold]) {
        [self unhold];
    } else {
        [self hold];
    }
}

- (BOOL)isRecording {
    return _localRecorderIdentifier != PJSUA_INVALID_ID || _remoteRecorderIdentifier != PJSUA_INVALID_ID;
}

- (BOOL)startRecordingToURL:(NSURL *)URL {
    if ([self isRecording]) {
        return YES;
    }
    if (![URL isFileURL] || [self state] != kAKSIPCallConfirmedState) {
        return NO;
    }

    pjsua_conf_port_id callPort = pjsua_call_get_conf_port((pjsua_call_id)[self identifier]);
    if (callPort == PJSUA_INVALID_ID) {
        return NO;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *temporaryRootURL = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                               URLByAppendingPathComponent:@"jps Telephone Call Recordings" isDirectory:YES];
    NSURL *temporaryDirectoryURL = [temporaryRootURL URLByAppendingPathComponent:NSUUID.UUID.UUIDString
                                                                      isDirectory:YES];
    NSError *directoryError = nil;
    NSDictionary *privateDirectoryAttributes = @{NSFilePosixPermissions: @0700};
    if (![fileManager createDirectoryAtURL:temporaryDirectoryURL
               withIntermediateDirectories:YES
                                attributes:privateDirectoryAttributes
                                     error:&directoryError]) {
        NSLog(@"Could not create a private temporary call-recording folder: %@", directoryError.localizedDescription);
        return NO;
    }
    NSURL *localURL = [temporaryDirectoryURL URLByAppendingPathComponent:@"local.wav" isDirectory:NO];
    NSURL *remoteURL = [temporaryDirectoryURL URLByAppendingPathComponent:@"remote.wav" isDirectory:NO];

    pj_str_t localFilename = [localURL.path pjString];
    pjsua_recorder_id localRecorderIdentifier = PJSUA_INVALID_ID;
    pj_status_t status = pjsua_recorder_create(&localFilename, 0, NULL, 0, 0, &localRecorderIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Could not create local call recorder (PJSIP error %d)", status);
        [fileManager removeItemAtURL:temporaryDirectoryURL error:nil];
        return NO;
    }

    pj_str_t remoteFilename = [remoteURL.path pjString];
    pjsua_recorder_id remoteRecorderIdentifier = PJSUA_INVALID_ID;
    status = pjsua_recorder_create(&remoteFilename, 0, NULL, 0, 0, &remoteRecorderIdentifier);
    if (status != PJ_SUCCESS) {
        NSLog(@"Could not create remote call recorder (PJSIP error %d)", status);
        pjsua_recorder_destroy(localRecorderIdentifier);
        [fileManager removeItemAtURL:temporaryDirectoryURL error:nil];
        return NO;
    }

    pjsua_conf_port_id localRecorderPort = pjsua_recorder_get_conf_port(localRecorderIdentifier);
    pjsua_conf_port_id remoteRecorderPort = pjsua_recorder_get_conf_port(remoteRecorderIdentifier);
    status = pjsua_conf_connect(callPort, remoteRecorderPort);
    if (status != PJ_SUCCESS) {
        NSLog(@"Could not connect remote call audio to recorder (PJSIP error %d)", status);
        pjsua_recorder_destroy(localRecorderIdentifier);
        pjsua_recorder_destroy(remoteRecorderIdentifier);
        [fileManager removeItemAtURL:temporaryDirectoryURL error:nil];
        return NO;
    }

    if (![self isMicrophoneMuted] && ![self isOnLocalHold]) {
        status = pjsua_conf_connect(0, localRecorderPort);
        if (status != PJ_SUCCESS) {
            NSLog(@"Could not connect microphone audio to recorder (PJSIP error %d)", status);
            pjsua_recorder_destroy(localRecorderIdentifier);
            pjsua_recorder_destroy(remoteRecorderIdentifier);
            [fileManager removeItemAtURL:temporaryDirectoryURL error:nil];
            return NO;
        }
    }

    _localRecorderIdentifier = localRecorderIdentifier;
    _localRecorderPort = localRecorderPort;
    _remoteRecorderIdentifier = remoteRecorderIdentifier;
    _remoteRecorderPort = remoteRecorderPort;
    self.recordingURL = URL;
    self.localRecordingURL = localURL;
    self.remoteRecordingURL = remoteURL;
    self.recordingTemporaryDirectoryURL = temporaryDirectoryURL;
    NSLog(@"Recording separate local and remote call tracks");
    return YES;
}

- (void)stopRecording {
    [self stopRecordingWithCompletion:nil];
}

- (void)stopRecordingWithCompletion:(void (^)(BOOL))completion {
    if (![self isRecording]) {
        if (completion != nil) {
            completion(YES);
        }
        return;
    }

    NSURL *localURL = self.localRecordingURL;
    NSURL *remoteURL = self.remoteRecordingURL;
    NSURL *destinationURL = self.recordingURL;
    NSURL *temporaryDirectoryURL = self.recordingTemporaryDirectoryURL;

    pj_status_t localStatus = PJ_SUCCESS;
    pj_status_t remoteStatus = PJ_SUCCESS;
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
        if (_localRecorderIdentifier != PJSUA_INVALID_ID) {
            localStatus = pjsua_recorder_destroy(_localRecorderIdentifier);
            if (localStatus == PJ_SUCCESS) {
                _localRecorderIdentifier = PJSUA_INVALID_ID;
                _localRecorderPort = PJSUA_INVALID_ID;
            }
        }
        if (_remoteRecorderIdentifier != PJSUA_INVALID_ID) {
            remoteStatus = pjsua_recorder_destroy(_remoteRecorderIdentifier);
            if (remoteStatus == PJ_SUCCESS) {
                _remoteRecorderIdentifier = PJSUA_INVALID_ID;
                _remoteRecorderPort = PJSUA_INVALID_ID;
            }
        }
        if (_localRecorderIdentifier == PJSUA_INVALID_ID && _remoteRecorderIdentifier == PJSUA_INVALID_ID) {
            break;
        }
    }
    if (_localRecorderIdentifier != PJSUA_INVALID_ID || _remoteRecorderIdentifier != PJSUA_INVALID_ID) {
        NSLog(@"Could not finalize call tracks after three attempts (PJSIP errors %d and %d)",
              localStatus, remoteStatus);
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    self.recordingURL = nil;
    self.localRecordingURL = nil;
    self.remoteRecordingURL = nil;
    self.recordingTemporaryDirectoryURL = nil;
    if (localURL == nil || remoteURL == nil || destinationURL == nil) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    AKMergeMonoRecordingsIntoStereoAsync(localURL, remoteURL, destinationURL, ^(BOOL succeeded) {
        if (succeeded) {
            [NSFileManager.defaultManager removeItemAtURL:temporaryDirectoryURL error:nil];
            NSLog(@"Saved stereo call recording (local left, remote right)");
        } else {
            NSLog(@"Could not create the stereo recording; private recovery tracks were retained temporarily");
        }
        if (completion != nil) {
            completion(succeeded);
        }
    });
}

- (void)refreshRecordingConnections {
    if (![self isRecording]) {
        return;
    }

    pjsua_conf_port_id callPort = pjsua_call_get_conf_port((pjsua_call_id)[self identifier]);
    if (callPort == PJSUA_INVALID_ID) {
        return;
    }
    pjsua_conf_connect(callPort, _remoteRecorderPort);
    if (![self isMicrophoneMuted] && ![self isOnLocalHold]) {
        pjsua_conf_connect(0, _localRecorderPort);
    }
}

@end
