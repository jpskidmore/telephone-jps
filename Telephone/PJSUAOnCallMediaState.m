//
//  PJSUAOnCallMediaState.m
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

#import "PJSUACallbacks.h"

#import "AKSIPCall.h"
#import "AKNSString+PJSUA.h"
#import "AKSIPUserAgent.h"

#define THIS_FILE "PJSUAOnCallMediaState.m"

static void LogCallMedia(const pjsua_call_info *callInfo);
static void CallMediaStateChanged(pjsua_call_id identifier, NSString *dialogIdentifier);
static const char *MediaStatusTextWithStatus(pjsua_call_media_status status);
static void ConnectCallToSoundDevice(AKSIPCall *call, pjsua_call_media_status status, pjsua_conf_port_id port);
static void PostMediaStateChangeNotification(AKSIPCall *call, pjsua_call_media_status status);

void PJSUAOnCallMediaState(pjsua_call_id callID) {
    pjsua_call_info info;
    if (pjsua_call_get_info(callID, &info) != PJ_SUCCESS) return;
    LogCallMedia(&info);
    pjsua_call_id identifier = info.id;
    NSString *dialogIdentifier = [NSString stringWithPJString:info.call_id];
    dispatch_async(dispatch_get_main_queue(), ^{
        CallMediaStateChanged(identifier, dialogIdentifier);
    });
}

static void LogCallMedia(const pjsua_call_info *callInfo) {
    for (NSUInteger i = 0; i < callInfo->media_cnt; i++) {
        PJ_LOG(4, (THIS_FILE, "Call %d media %lu [type = %s], status is %s",
                   callInfo->id, (unsigned long)i, pjmedia_type_name(callInfo->media[i].type),
                   MediaStatusTextWithStatus(callInfo->media[i].status)));
    }
}

static void CallMediaStateChanged(pjsua_call_id identifier, NSString *dialogIdentifier) {
    AKSIPUserAgent *userAgent = [AKSIPUserAgent sharedUserAgent];
    if (!userAgent.isStarted) return;
    AKSIPCall *call = [userAgent callWithIdentifier:identifier];
    if (call == nil || ![call.dialogIdentifier isEqualToString:dialogIdentifier] ||
        call.state == kAKSIPCallDisconnectedState) {
        return;
    }
    // Main may have been blocked in a prior hardware open. Re-read current
    // native state; do not replay stale ports/hold transitions or reused IDs.
    pjsua_call_info info;
    if (pjsua_call_get_info(identifier, &info) != PJ_SUCCESS ||
        info.state == PJSIP_INV_STATE_DISCONNECTED || info.media_cnt == 0 ||
        info.media[0].type != PJMEDIA_TYPE_AUDIO ||
        ![[NSString stringWithPJString:info.call_id] isEqualToString:dialogIdentifier]) {
        return;
    }
    pjsua_call_media_status status = info.media[0].status;
    pjsua_conf_port_id port = info.media[0].stream.aud.conf_slot;
    ConnectCallToSoundDevice(call, status, port);
    [userAgent stopRingbackForCall:call];
    PostMediaStateChangeNotification(call, status);
}

static const char *MediaStatusTextWithStatus(pjsua_call_media_status status) {
    const char *texts[] = { "None", "Active", "Local hold", "Remote hold", "Error" };
    return status >= PJSUA_CALL_MEDIA_NONE && status <= PJSUA_CALL_MEDIA_ERROR ? texts[status] : "Unknown";
}

static void ConnectCallToSoundDevice(AKSIPCall *call, pjsua_call_media_status status, pjsua_conf_port_id port) {
    if (status == PJSUA_CALL_MEDIA_ACTIVE || status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        AKSIPUserAgent *agent = [AKSIPUserAgent sharedUserAgent];
        if ([agent connectAudioSource:port destination:0] != PJ_SUCCESS) return;
        if (!call.isMicrophoneMuted) {
            [agent connectAudioSource:0 destination:port];
        }
    }
}

static void PostMediaStateChangeNotification(AKSIPCall *call, pjsua_call_media_status status) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSString *notificationName = nil;
    switch (status) {
        case PJSUA_CALL_MEDIA_ACTIVE:
            notificationName = AKSIPCallMediaDidBecomeActiveNotification;
            break;
        case PJSUA_CALL_MEDIA_LOCAL_HOLD:
            notificationName = AKSIPCallDidLocalHoldNotification;
            break;
        case PJSUA_CALL_MEDIA_REMOTE_HOLD:
            notificationName = AKSIPCallDidRemoteHoldNotification;
            break;
        default:
            break;

    }
    if (notificationName != nil) {
        [nc postNotificationName:notificationName object:call];
    }
}
