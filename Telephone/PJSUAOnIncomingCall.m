//
//  PJSUAOnIncomingCall.m
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

#import "AKSIPAccount.h"
#import "AKNSString+PJSUA.h"
#import "AKSIPCall.h"
#import "AKSIPURIParser.h"
#import "AKSIPUserAgent.h"
#import "PJSUACallInfo.h"

#define THIS_FILE "PJSUAOnIncomingCall.m"

void PJSUAOnIncomingCall(pjsua_acc_id accountID, pjsua_call_id callID, pjsip_rx_data *invite) {
    PJ_LOG(3, (THIS_FILE, "Incoming call for account %d", accountID));
    pjsua_call_info info;
    if (pjsua_call_get_info(callID, &info) != PJ_SUCCESS) return;
    AKSIPUserAgent *agent = [AKSIPUserAgent sharedUserAgent];
    AKSIPAccount *capturedAccount = [agent accountWithIdentifier:accountID];
    PJSUACallInfo *infoWrapper = [[PJSUACallInfo alloc] initWithInfo:info parser:agent.parser];
    dispatch_async(dispatch_get_main_queue(), ^{
        AKSIPAccount *account = [agent accountWithIdentifier:accountID];
        if (account == nil || account != capturedAccount || account.identifier != accountID) {
            NSString *dialog = infoWrapper.dialogIdentifier;
            [agent performSIPOperation:^pj_status_t {
                pjsua_call_info current;
                if (pjsua_call_get_info(callID, &current) != PJ_SUCCESS ||
                    ![[NSString stringWithPJString:current.call_id] isEqualToString:dialog]) return PJ_ECANCELLED;
                return pjsua_call_hangup(callID, PJSIP_SC_TEMPORARILY_UNAVAILABLE, NULL, NULL);
            } completion:nil];
            return;
        }
        AKSIPCall *call = [account addCallWithInfo:infoWrapper];
        if (call == nil) return;
        [account.delegate SIPAccount:account didReceiveCall:call];
        [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPCallIncomingNotification object:call];
    });
}
