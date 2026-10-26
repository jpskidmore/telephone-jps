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

static void AKRemoveEmptyRecordingReservation(NSURL *URL) {
    if (!URL.isFileURL) return;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:URL.path error:nil];
    if ([attributes[NSFileType] isEqual:NSFileTypeRegular] && [attributes[NSFileSize] unsignedLongLongValue] == 0)
        [NSFileManager.defaultManager removeItemAtURL:URL error:nil];
}

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
@property(atomic) BOOL nativeRecordingActive;
@property(atomic) BOOL recordingStartPending;
@property(atomic, strong, nullable) NSObject *recordingStartAttempt;
@property(atomic, copy, nullable) NSURL *recordingStartDestinationURL;
@property(nonatomic) AKRecordingStartResult recordingStartResult;
@property(nonatomic, readwrite, copy, nullable) NSURL *recordingURL;
@property(nonatomic, copy, nullable) NSURL *localRecordingURL;
@property(nonatomic, copy, nullable) NSURL *remoteRecordingURL;
@property(nonatomic, copy, nullable) NSURL *recordingTemporaryDirectoryURL;
@property(nonatomic, strong, nullable) AKRecordingJobOwnership *recordingJobOwnership;
@property(nonatomic, strong, nullable) NSURL *accessedRecordingDirectoryURL;

- (BOOL)stopNativeRecorders;
- (BOOL)hasRecordingAudioFailure;
- (pjsua_conf_port_id)recordingCallPort;
- (nullable NSURL *)createRecordingRecoveryDirectoryWithError:(NSError **)error;
- (pj_status_t)createRecordingRecorderAtURL:(NSURL *)URL identifier:(pjsua_recorder_id *)identifier;
- (pjsua_conf_port_id)recordingPortForRecorder:(pjsua_recorder_id)identifier;
- (pj_status_t)connectRecordingAudioSource:(pjsua_conf_port_id)source destination:(pjsua_conf_port_id)destination;
- (void)destroyRecordingRecorder:(pjsua_recorder_id)identifier;
- (void)finalizeRecordingFromLocalURL:(NSURL *)localURL remoteURL:(NSURL *)remoteURL
                     destinationURL:(NSURL *)destinationURL completion:(void (^)(BOOL))completion;

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
    return self.identifier != kAKSIPUserAgentInvalidIdentifier && self.state > kAKSIPCallNullState && self.state < kAKSIPCallDisconnectedState;
}

- (BOOL)isOnLocalHold { return self.localHold; }
- (BOOL)isOnRemoteHold { return self.remoteHold; }


#pragma mark -

- (instancetype)initWithSIPAccount:(AKSIPAccount *)account info:(PJSUACallInfo *)info {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _account = account;
    _identifier = info.identifier;
    _dialogIdentifier = [info.dialogIdentifier copy];

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

- (void)performDialogOperation:(pj_status_t (^)(pjsua_call_info *))operation completion:(void (^)(pj_status_t))completion {
    NSInteger identifier = self.identifier;
    NSString *dialog = self.dialogIdentifier;
    [[AKSIPUserAgent sharedUserAgent] performSIPOperation:^pj_status_t {
        pjsua_call_info info;
        if (pjsua_call_get_info((pjsua_call_id)identifier, &info) != PJ_SUCCESS ||
            ![[NSString stringWithPJString:info.call_id] isEqualToString:dialog]) return PJ_ECANCELLED;
        return operation(&info);
    } completion:completion];
}

- (void)answer {
    [self performDialogOperation:^pj_status_t(pjsua_call_info *info) {
        return pjsua_call_answer(info->id, PJSIP_SC_OK, NULL, NULL);
    } completion:^(pj_status_t status) {
        if (status == PJ_SUCCESS) self.missed = NO;
        else [[AKSIPUserAgent sharedUserAgent] reportAudioFailure:status operation:@"answer-call"];
    }];
}

- (void)hangUp {
    [self requestHangUpWithCompletion:^(BOOL accepted) {}];
}

- (void)requestHangUpWithCompletion:(void (^)(BOOL))completion {
    if (self.state == kAKSIPCallDisconnectedState || self.identifier == kAKSIPUserAgentInvalidIdentifier) {
        completion(self.state == kAKSIPCallDisconnectedState);
        return;
    }
    NSInteger identifier = self.identifier;
    NSString *dialog = self.dialogIdentifier;
    [[AKSIPUserAgent sharedUserAgent] performSIPCleanupOperation:^pj_status_t {
        pjsua_call_info info;
        if (pjsua_call_get_info((pjsua_call_id)identifier, &info) != PJ_SUCCESS ||
            ![[NSString stringWithPJString:info.call_id] isEqualToString:dialog]) return PJ_ECANCELLED;
        return pjsua_call_hangup((pjsua_call_id)identifier, 0, NULL, NULL);
    } completion:^(pj_status_t status) {
        if (status == PJ_SUCCESS) self.missed = NO;
        completion(status == PJ_SUCCESS);
    }];
}

- (void)requestToggleHoldWithCompletion:(void (^)(BOOL))completion {
    if (self.state != kAKSIPCallConfirmedState || self.isOnRemoteHold) { completion(NO); return; }
    NSInteger identifier = self.identifier;
    NSString *dialog = self.dialogIdentifier;
    BOOL wasHeld = self.isOnLocalHold;
    [[AKSIPUserAgent sharedUserAgent] performSIPOperation:^pj_status_t {
        pjsua_call_info info;
        if (pjsua_call_get_info((pjsua_call_id)identifier, &info) != PJ_SUCCESS ||
            info.state != PJSIP_INV_STATE_CONFIRMED ||
            ![[NSString stringWithPJString:info.call_id] isEqualToString:dialog]) return PJ_ECANCELLED;
        return wasHeld ? pjsua_call_reinvite((pjsua_call_id)identifier, PJ_TRUE, NULL)
                       : pjsua_call_set_hold((pjsua_call_id)identifier, NULL);
    } completion:^(pj_status_t status) { completion(status == PJ_SUCCESS); }];
}

- (void)attendedTransferToCall:(AKSIPCall *)destinationCall {
    self.transferStatus = kAKSIPUserAgentInvalidIdentifier;
    self.transferStatusText = @"";
    NSInteger destination = destinationCall.identifier;
    NSString *dialog = destinationCall.dialogIdentifier;
    [self performDialogOperation:^pj_status_t(pjsua_call_info *info) {
        pjsua_call_info target;
        if (pjsua_call_get_info((pjsua_call_id)destination, &target) != PJ_SUCCESS ||
            ![[NSString stringWithPJString:target.call_id] isEqualToString:dialog]) return PJ_ECANCELLED;
        return pjsua_call_xfer_replaces(info->id, (pjsua_call_id)destination, PJSUA_XFER_NO_REQUIRE_REPLACES, NULL);
    } completion:^(pj_status_t status) {
        if (status != PJ_SUCCESS) {
            self.transferStatus = PJSIP_SC_INTERNAL_SERVER_ERROR;
            self.transferStatusText = @"Could not transfer call";
            [NSNotificationCenter.defaultCenter postNotificationName:AKSIPCallTransferStatusDidChangeNotification object:self
                userInfo:@{@"AKFinalTransferNotification": @YES}];
        }
    }];
}

- (void)sendRingingNotification { [self sendReply:PJSIP_SC_RINGING]; }
- (void)replyWithTemporarilyUnavailable { [self sendReply:PJSIP_SC_TEMPORARILY_UNAVAILABLE]; }
- (void)replyWithBusyHere { [self sendReply:PJSIP_SC_BUSY_HERE]; }
- (void)sendReply:(unsigned)code {
    [self performDialogOperation:^pj_status_t(pjsua_call_info *info) {
        return pjsua_call_answer(info->id, code, NULL, NULL);
    } completion:nil];
}

- (void)sendDTMFDigits:(NSString *)digits {
    NSString *copiedDigits = [digits copy];
    [self performDialogOperation:^pj_status_t(pjsua_call_info *info) {
        pj_str_t pjDigits = copiedDigits.pjString;
        pj_status_t status = pjsua_call_dial_dtmf(info->id, &pjDigits);
        if (status == PJ_SUCCESS) return status;
        const pj_str_t SIPINFO = pj_str("INFO");
        for (NSUInteger i = 0; i < copiedDigits.length; i++) {
            pjsua_msg_data data; pjsua_msg_data_init(&data);
            data.content_type = pj_str("application/dtmf-relay");
            NSString *body = [NSString stringWithFormat:@"Signal=%C\r\nDuration=300", [copiedDigits characterAtIndex:i]];
            data.msg_body = body.pjString;
            status = pjsua_call_send_request(info->id, &SIPINFO, &data);
            if (status != PJ_SUCCESS) return status;
        }
        return PJ_SUCCESS;
    } completion:nil];
}

- (void)toggleMicrophoneMute { [self requestToggleMicrophoneMuteWithCompletion:^(BOOL accepted) {}]; }

- (void)requestToggleMicrophoneMuteWithCompletion:(void (^)(BOOL))completion {
    if (self.state != kAKSIPCallConfirmedState) { completion(NO); return; }
    BOOL mute = !self.isMicrophoneMuted;
    [self performDialogOperation:^pj_status_t(pjsua_call_info *info) {
        if (info->state != PJSIP_INV_STATE_CONFIRMED || info->media_cnt == 0 || info->media[0].type != PJMEDIA_TYPE_AUDIO) return PJ_EINVALIDOP;
        pj_status_t status = mute ? pjsua_conf_disconnect(0, info->media[0].stream.aud.conf_slot)
            : [[AKSIPUserAgent sharedUserAgent] connectAudioSource:0 destination:info->media[0].stream.aud.conf_slot];
        if (status == PJ_SUCCESS && self.isRecording) {
            if (mute) pjsua_conf_disconnect(0, _localRecorderPort);
            else if (!self.isOnLocalHold) [[AKSIPUserAgent sharedUserAgent] connectAudioSource:0 destination:_localRecorderPort];
        }
        return status;
    } completion:^(pj_status_t status) {
        if (status == PJ_SUCCESS) self.microphoneMuted = mute;
        completion(status == PJ_SUCCESS);
    }];
}

- (void)toggleHold { [self requestToggleHoldWithCompletion:^(BOOL accepted) {}]; }

- (BOOL)isRecording { return self.nativeRecordingActive; }

- (BOOL)requiresSIPControlThread { return YES; }

- (void)startRecordingToURL:(NSURL *)URL accessedDirectoryURL:(NSURL *)directoryURL completion:(void (^)(BOOL))completion {
    [self startRecordingToURL:URL accessedDirectoryURL:directoryURL resultCompletion:^(AKRecordingStartResult result) {
        completion(result == AKRecordingStartResultSuccess);
    }];
}

- (void)discardUnusedRecordingReservationAtURL:(NSURL *)URL {
    if (!URL.isFileURL) return;
    NSURL *canonical = URL.URLByResolvingSymlinksInPath.standardizedURL;
    if ([canonical isEqual:self.recordingURL.URLByResolvingSymlinksInPath.standardizedURL] ||
        [canonical isEqual:self.recordingStartDestinationURL.URLByResolvingSymlinksInPath.standardizedURL]) return;
    AKRemoveEmptyRecordingReservation(URL);
}

- (void)startRecordingToURL:(NSURL *)URL accessedDirectoryURL:(NSURL *)directoryURL
          resultCompletion:(void (^)(AKRecordingStartResult))completion {
    if (self.recordingStartPending || self.isRecording) {
        [self discardUnusedRecordingReservationAtURL:URL];
        [directoryURL stopAccessingSecurityScopedResource];
        completion(AKRecordingStartResultBusy);
        return;
    }
    NSObject *attempt = [NSObject new];
    self.recordingStartAttempt = attempt;
    self.recordingStartDestinationURL = URL;
    self.recordingStartPending = YES;
    __block BOOL executed = NO;
    __block AKRecordingStartResult result = AKRecordingStartResultStaleCall;
    [self performDialogOperation:^pj_status_t(pjsua_call_info *info) {
        if (self.recordingStartAttempt != attempt || info->state != PJSIP_INV_STATE_CONFIRMED) return PJ_ECANCELLED;
        executed = YES;
        // A legacy BOOL override still fails closed; the production setup sets
        // the precise result at the operation that actually failed.
        self.recordingStartResult = AKRecordingStartResultRecorderCreationFailure;
        BOOL succeeded = [self startRecordingToURL:URL accessedDirectoryURL:directoryURL];
        result = succeeded ? AKRecordingStartResultSuccess : self.recordingStartResult;
        return succeeded ? PJ_SUCCESS : PJ_EUNKNOWN;
    } completion:^(pj_status_t status) {
        if (self.recordingStartAttempt != attempt || status == PJ_ECANCELLED ||
            (status != PJ_SUCCESS && result == AKRecordingStartResultSuccess)) result = AKRecordingStartResultStaleCall;
        self.recordingStartDestinationURL = nil;
        self.recordingStartAttempt = nil;
        self.recordingStartPending = NO;
        if (!executed) {
            [self discardUnusedRecordingReservationAtURL:URL];
            [directoryURL stopAccessingSecurityScopedResource];
        }
        completion(result);
    }];
}

- (BOOL)startRecordingToURL:(NSURL *)URL accessedDirectoryURL:(NSURL *)directoryURL {
    // Do not replace an existing recording's access token, even for an equal URL.
    if ([self isRecording]) {
        self.recordingStartResult = AKRecordingStartResultBusy;
        [self discardUnusedRecordingReservationAtURL:URL];
        [directoryURL stopAccessingSecurityScopedResource];
        return NO;
    }
    if (![self startRecordingToURL:URL]) {
        // Remove the reserved placeholder while the consumed scope is valid.
        // This is the admitted attempt, whose reservation is no longer needed.
        AKRemoveEmptyRecordingReservation(URL);
        [directoryURL stopAccessingSecurityScopedResource];
        return NO;
    }
    self.accessedRecordingDirectoryURL = directoryURL;
    return YES;
}

- (BOOL)startRecordingToURL:(NSURL *)URL {
    if ([self isRecording]) {
        self.recordingStartResult = AKRecordingStartResultBusy;
        return NO;
    }
    if (!URL.isFileURL || URL.path.length == 0 || URL.hasDirectoryPath) {
        self.recordingStartResult = AKRecordingStartResultInvalidDestination;
        return NO;
    }
    BOOL isDirectory = NO;
    [NSFileManager.defaultManager fileExistsAtPath:URL.path isDirectory:&isDirectory];
    if (isDirectory) {
        self.recordingStartResult = AKRecordingStartResultInvalidDestination;
        return NO;
    }
    if (self.state != kAKSIPCallConfirmedState) {
        self.recordingStartResult = AKRecordingStartResultStaleCall;
        return NO;
    }
    if ([self hasRecordingAudioFailure]) {
        self.recordingStartResult = AKRecordingStartResultAudioFailure;
        return NO;
    }

    pjsua_conf_port_id callPort = [self recordingCallPort];
    if (callPort == PJSUA_INVALID_ID) {
        self.recordingStartResult = AKRecordingStartResultConnectionFailure;
        return NO;
    }

    NSError *directoryError = nil;
    NSURL *temporaryDirectoryURL = [self createRecordingRecoveryDirectoryWithError:&directoryError];
    if (temporaryDirectoryURL == nil) {
        self.recordingStartResult = AKRecordingStartResultPrivateStorageFailure;
        NSLog(@"Could not create a private call-recording folder (error %ld)", (long)directoryError.code);
        return NO;
    }
    NSURL *localURL = [temporaryDirectoryURL URLByAppendingPathComponent:@"local.wav" isDirectory:NO];
    NSURL *remoteURL = [temporaryDirectoryURL URLByAppendingPathComponent:@"remote.wav" isDirectory:NO];
    AKRecordingJobOwnership *ownership = AKClaimRecordingJob(temporaryDirectoryURL, &directoryError);
    if (!ownership) {
        self.recordingStartResult = AKRecordingStartResultPrivateStorageFailure;
        return NO;
    }
    if (!AKPersistOwnedRecordingRecoveryJob(ownership, localURL, remoteURL, URL,
                                           AKRecordingJobPhaseCapturing, &directoryError)) {
        AKFinishRecordingRecoveryJob(ownership, NO);
        AKReportRecordingExportFailure(temporaryDirectoryURL, URL, directoryError);
        self.recordingStartResult = AKRecordingStartResultPrivateStorageFailure;
        return NO;
    }

    pjsua_recorder_id localRecorderIdentifier = PJSUA_INVALID_ID;
    pj_status_t status = [self createRecordingRecorderAtURL:localURL identifier:&localRecorderIdentifier];
    if (status != PJ_SUCCESS) {
        NSLog(@"Could not create local call recorder (PJSIP error %d)", status);
        AKDiscardRecordingRecoveryJob(ownership);
        self.recordingStartResult = AKRecordingStartResultRecorderCreationFailure;
        return NO;
    }

    pjsua_recorder_id remoteRecorderIdentifier = PJSUA_INVALID_ID;
    status = [self createRecordingRecorderAtURL:remoteURL identifier:&remoteRecorderIdentifier];
    if (status != PJ_SUCCESS) {
        NSLog(@"Could not create remote call recorder (PJSIP error %d)", status);
        [self destroyRecordingRecorder:localRecorderIdentifier];
        AKDiscardRecordingRecoveryJob(ownership);
        self.recordingStartResult = AKRecordingStartResultRecorderCreationFailure;
        return NO;
    }

    pjsua_conf_port_id localRecorderPort = [self recordingPortForRecorder:localRecorderIdentifier];
    pjsua_conf_port_id remoteRecorderPort = [self recordingPortForRecorder:remoteRecorderIdentifier];
    status = [self connectRecordingAudioSource:callPort destination:remoteRecorderPort];
    if (status != PJ_SUCCESS) {
        NSLog(@"Could not connect remote call audio to recorder (PJSIP error %d)", status);
        [self destroyRecordingRecorder:localRecorderIdentifier];
        [self destroyRecordingRecorder:remoteRecorderIdentifier];
        AKDiscardRecordingRecoveryJob(ownership);
        self.recordingStartResult = AKRecordingStartResultConnectionFailure;
        return NO;
    }

    if (![self isMicrophoneMuted] && ![self isOnLocalHold]) {
        status = [self connectRecordingAudioSource:0 destination:localRecorderPort];
        if (status != PJ_SUCCESS) {
            NSLog(@"Could not connect microphone audio to recorder (PJSIP error %d)", status);
            [self destroyRecordingRecorder:localRecorderIdentifier];
            [self destroyRecordingRecorder:remoteRecorderIdentifier];
            AKDiscardRecordingRecoveryJob(ownership);
            self.recordingStartResult = AKRecordingStartResultConnectionFailure;
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
    self.recordingJobOwnership = ownership;
    self.nativeRecordingActive = YES;
    self.recordingStartResult = AKRecordingStartResultSuccess;
    NSLog(@"Recording separate local and remote call tracks");
    return YES;
}

// Narrow native boundaries also let isolated tests exercise the real setup and
// recovery ownership without initialising PJSUA or opening an audio device.
- (BOOL)hasRecordingAudioFailure { return [AKSIPUserAgent sharedUserAgent].hasAudioFailure; }
- (pjsua_conf_port_id)recordingCallPort { return pjsua_call_get_conf_port((pjsua_call_id)self.identifier); }
- (NSURL *)createRecordingRecoveryDirectoryWithError:(NSError **)error { return AKCreateRecordingRecoveryDirectory(error); }
- (pj_status_t)createRecordingRecorderAtURL:(NSURL *)URL identifier:(pjsua_recorder_id *)identifier {
    pj_str_t filename = URL.path.pjString;
    return pjsua_recorder_create(&filename, 0, NULL, 0, 0, identifier);
}
- (pjsua_conf_port_id)recordingPortForRecorder:(pjsua_recorder_id)identifier { return pjsua_recorder_get_conf_port(identifier); }
- (pj_status_t)connectRecordingAudioSource:(pjsua_conf_port_id)source destination:(pjsua_conf_port_id)destination {
    return [[AKSIPUserAgent sharedUserAgent] connectAudioSource:source destination:destination];
}
- (void)destroyRecordingRecorder:(pjsua_recorder_id)identifier { pjsua_recorder_destroy(identifier); }

- (void)stopRecording {
    [self stopRecordingWithCompletion:nil];
}

- (void)stopRecordingWithCompletion:(void (^)(BOOL))completion {
    BOOL pendingStart = self.recordingStartPending;
    if (pendingStart && NSThread.isMainThread) self.recordingStartAttempt = nil;
    if ((self.isRecording || pendingStart) && self.requiresSIPControlThread && NSThread.isMainThread) {
        [[AKSIPUserAgent sharedUserAgent] performSIPCleanupOperation:^pj_status_t {
            [self stopRecordingWithCompletion:completion]; return PJ_SUCCESS;
        } completion:^(pj_status_t status) {
            if (status != PJ_SUCCESS && completion) completion(NO);
        }];
        return;
    }
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
    AKRecordingJobOwnership *ownership = self.recordingJobOwnership;

    if (![self stopNativeRecorders]) {
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    NSURL *accessedDirectoryURL = self.accessedRecordingDirectoryURL;
    self.accessedRecordingDirectoryURL = nil;
    self.recordingURL = nil;
    self.localRecordingURL = nil;
    self.remoteRecordingURL = nil;
    self.recordingTemporaryDirectoryURL = nil;
    if (localURL == nil || remoteURL == nil || destinationURL == nil) {
        self.recordingJobOwnership = nil;
        if (ownership) AKFinishRecordingRecoveryJob(ownership, NO);
        [accessedDirectoryURL stopAccessingSecurityScopedResource];
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    NSError *recoveryError = nil;
    if (![self persistRecordingRecoveryJobAtDirectory:temporaryDirectoryURL localURL:localURL remoteURL:remoteURL
                                     destinationURL:destinationURL error:&recoveryError]) {
        self.recordingJobOwnership = nil;
        if (ownership) AKFinishRecordingRecoveryJob(ownership, NO);
        AKReportRecordingExportFailure(temporaryDirectoryURL, destinationURL, recoveryError);
        [accessedDirectoryURL stopAccessingSecurityScopedResource];
        if (completion) completion(NO);
        return;
    }
    // Transfer the same claim to this finalizer before another segment starts.
    self.recordingJobOwnership = nil;
    [self finalizeRecordingFromLocalURL:localURL remoteURL:remoteURL destinationURL:destinationURL completion:^(BOOL succeeded) {
        AKFinishRecordingRecoveryJob(ownership, succeeded);
        if (succeeded) {
            NSLog(@"Saved stereo call recording (local left, remote right)");
        } else {
            AKReportRecordingExportFailure(temporaryDirectoryURL, destinationURL, nil);
            NSLog(@"Could not create the stereo recording; private durable recovery tracks were retained");
        }
        // This captured token belongs to this recording, not the controller's
        // current call or another recording using the same directory.
        [accessedDirectoryURL stopAccessingSecurityScopedResource];
        if (completion != nil) {
            completion(succeeded);
        }
    }];
}
// Kept separate from conversion so native stop failures retain their resources
// for a later stop request. The bundled PJSIP destroy has no transient retry case.
- (BOOL)persistRecordingRecoveryJobAtDirectory:(NSURL *)directory localURL:(NSURL *)local
                                    remoteURL:(NSURL *)remote destinationURL:(NSURL *)destination error:(NSError **)error {
    return self.recordingJobOwnership &&
        AKPersistOwnedRecordingRecoveryJob(self.recordingJobOwnership, local, remote, destination,
                                          AKRecordingJobPhaseFinalising, error);
}

- (BOOL)stopNativeRecorders {
    pj_status_t localStatus = PJ_SUCCESS;
    pj_status_t remoteStatus = PJ_SUCCESS;
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
    if (_localRecorderIdentifier != PJSUA_INVALID_ID || _remoteRecorderIdentifier != PJSUA_INVALID_ID) {
        NSLog(@"Could not finalize call tracks (PJSIP errors %d and %d)", localStatus, remoteStatus);
        return NO;
    }
    self.nativeRecordingActive = NO;
    return YES;
}

- (void)finalizeRecordingFromLocalURL:(NSURL *)localURL
                          remoteURL:(NSURL *)remoteURL
                     destinationURL:(NSURL *)destinationURL
                         completion:(void (^)(BOOL))completion {
    AKMergeMonoRecordingsIntoStereoAsync(localURL, remoteURL, destinationURL, completion);
}

- (void)refreshRecordingConnections {
    if (!self.isRecording || [AKSIPUserAgent sharedUserAgent].hasAudioFailure) return;
    [self performDialogOperation:^pj_status_t(pjsua_call_info *info) {
        if (info->media_cnt == 0 || info->media[0].type != PJMEDIA_TYPE_AUDIO) return PJ_EINVALIDOP;
        pjsua_conf_port_id callPort = info->media[0].stream.aud.conf_slot;
        AKSIPUserAgent *agent = [AKSIPUserAgent sharedUserAgent];
        pj_status_t result = [agent connectAudioSource:callPort destination:_remoteRecorderPort];
        if (result == PJ_SUCCESS && !self.isMicrophoneMuted && !self.isOnLocalHold)
            result = [agent connectAudioSource:0 destination:_localRecorderPort];
        return result;
    } completion:nil];
}

@end
