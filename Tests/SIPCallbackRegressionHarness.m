#import <Foundation/Foundation.h>
#import <pjsua-lib/pjsua.h>
#import "PJSUACallbacks.h"
#import "PJSUACallInfo.h"
#import "AKSIPCallNotifications.h"

// Exact application callback objects; deliberately inert collaborators.
// No UserAgent implementation, accounts, transports, media or UI are linked.
@interface ProbeCall : NSObject
@property(nonatomic) NSInteger identifier, state, lastStatus, duration, transferStatus;
@property(nonatomic, copy) NSString *stateText, *lastStatusText, *transferStatusText, *dialogIdentifier;
@property(nonatomic, weak) id delegate;
@property(nonatomic) NSUInteger hangups;
- (void)hangUp;
@property(nonatomic, weak) id account;
@end
@implementation ProbeCall
- (void)hangUp { self.hangups++; pjsua_call_hangup((pjsua_call_id)self.identifier,0,NULL,NULL); }
@end
@interface ProbeDelegate : NSObject
@property(nonatomic) NSUInteger incomingCount, replacements;
@end
@implementation ProbeDelegate
- (void)SIPAccount:(id)account didReceiveCall:(id)call { self.incomingCount++; }
- (void)SIPAccount:(id)account didReceiveReplacementCall:(id)call replacingIdentifier:(NSInteger)oldIdentifier { self.replacements++; }
@end
@interface ProbeAccount : NSObject
@property(nonatomic) NSInteger identifier;
@property(nonatomic, strong) NSMutableDictionary *calls;
@property(nonatomic, strong) ProbeDelegate *delegate;
- (ProbeCall *)addCallWithInfo:(PJSUACallInfo *)info;
@end
@implementation ProbeAccount
- (ProbeCall *)addCallWithInfo:(PJSUACallInfo *)info {
    ProbeCall *call = [ProbeCall new]; call.identifier = info.identifier; call.state = info.state; call.account = self; call.dialogIdentifier = info.dialogIdentifier;
    self.calls[@(call.identifier)] = call; return call;
}
- (void)removeCall:(ProbeCall *)call { [self.calls removeObjectForKey:@(call.identifier)]; }
@end
@interface ProbeParser : NSObject
@end
@implementation ProbeParser
- (id)SIPURIFromString:(NSString *)input { return @"synthetic URI"; }
@end
@interface AKSIPUserAgent : NSObject
@property(nonatomic, strong) ProbeParser *parser;
@property(nonatomic, strong) ProbeAccount *account;
+ (instancetype)sharedUserAgent;
@end
@implementation AKSIPUserAgent
+ (instancetype)sharedUserAgent { static AKSIPUserAgent *agent; if (!agent) { agent = [self new]; agent.parser = [ProbeParser new]; } return agent; }
- (id)accountWithIdentifier:(NSInteger)identifier { return self.account.identifier == identifier ? self.account : nil; }
- (id)callWithIdentifier:(NSInteger)identifier { return self.account.calls[@(identifier)]; }
- (id)callWithIdentifier:(NSInteger)identifier dialogIdentifier:(NSString *)dialog { ProbeCall *call = self.account.calls[@(identifier)]; return [call.dialogIdentifier isEqualToString:dialog] ? call : nil; }
- (void)forgetRetiredAccountIfUnused:(id)account {}
- (void)performSIPOperation:(pj_status_t (^)(void))operation completion:(void (^)(pj_status_t))completion { pj_status_t status = operation(); if (completion) completion(status); }
- (void)stopRingbackForCall:(id)call {}
- (void)startRingbackForCall:(id)call {}
@end
static NSMutableDictionary *nativeStates;
PJ_DEF(pj_status_t) pjsua_call_get_info(pjsua_call_id call, pjsua_call_info *info) {
    if (nativeStates[@(call)] == nil) return PJ_EINVALIDOP;
    memset(info, 0, sizeof(*info)); info->id = call; info->acc_id = 7;
    info->state = (pjsip_inv_state)[nativeStates[@(call)] intValue];
    info->role = PJSIP_ROLE_UAS; info->call_id = pj_str("synthetic-dialog");
    info->local_info = pj_str("sip:local@example.invalid"); info->remote_info = pj_str("sip:remote@example.invalid");
    info->state_text = pj_str("synthetic state"); info->last_status_text = pj_str("synthetic status");
    info->last_status = info->state == PJSIP_INV_STATE_DISCONNECTED ? 410 : 200; return PJ_SUCCESS;
}
PJ_DEF(pj_status_t) pjsua_call_dump(pjsua_call_id call, pj_bool_t media, char *buffer, unsigned size, const char *indent) {
    snprintf(buffer, size, "synthetic dump"); return PJ_SUCCESS;
}
PJ_DEF(pj_status_t) pjsua_call_hangup(pjsua_call_id call, unsigned status, const pj_str_t *reason, const pjsua_msg_data *data) {
    // PJSIP2.17 pjsua_call.c3304–3313 invokes on_call_state synchronously
    // after marking hanging_up. Its get_info then reports DISCONNECTED.
    nativeStates[@(call)] = @(PJSIP_INV_STATE_DISCONNECTED);
    pjsip_event event; PJSIP_EVENT_INIT_USER(event, 0, 0, 0, 0);
    PJSUAOnCallState(call, &event); return PJ_SUCCESS;
}
static void drain(void) {
    __block BOOL complete = NO; dispatch_async(dispatch_get_main_queue(), ^{ complete = YES; });
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!complete && timeout.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    if (!complete) abort();
}
static ProbeAccount *reset(void) {
    ProbeAccount *account = [ProbeAccount new]; account.identifier = 7; account.calls = [NSMutableDictionary new]; account.delegate = [ProbeDelegate new];
    [AKSIPUserAgent sharedUserAgent].account = account; nativeStates = [NSMutableDictionary new]; return account;
}
int main(void) {
    @autoreleasepool {
        pj_log_set_level(0);
        NSMutableArray *events = [NSMutableArray new];
        NSMutableArray *observers = [NSMutableArray new];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[AKSIPCallIncomingNotification, AKSIPCallDidDisconnectNotification, AKSIPCallTransferStatusDidChangeNotification, AKSIPCallDidConfirmNotification]) {
            [observers addObject:[center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                [events addObject:@{@"name": note.name, @"call": note.object ? @(((ProbeCall *)note.object).identifier) : NSNull.null, @"transferStatus": @(((ProbeCall *)note.object).transferStatus)}];
            }]];
        }
        NSMutableDictionary *results = [NSMutableDictionary new];
        ProbeAccount *account = reset(); nativeStates[@1] = @(PJSIP_INV_STATE_INCOMING);
        PJSUAOnIncomingCall(7, 1, NULL); drain();
        results[@"ordinaryIncoming"] = @{@"delegateCount": @(account.delegate.incomingCount), @"events": events.copy, @"modelCount": @(account.calls.count)};
        [events removeAllObjects];
        account = reset(); nativeStates[@1] = @(PJSIP_INV_STATE_CONFIRMED); nativeStates[@2] = @(PJSIP_INV_STATE_INCOMING);
        PJSUAOnCallReplaced(1, 2); drain(); nativeStates[@2] = @(PJSIP_INV_STATE_CONFIRMED);
        pjsip_event event; PJSIP_EVENT_INIT_USER(event, 0, 0, 0, 0); PJSUAOnCallState(2, &event); drain();
        results[@"replacementIncoming"] = @{@"delegateCount": @(account.delegate.incomingCount), @"replacementCount": @(account.delegate.replacements), @"events": events.copy, @"modelCount": @(account.calls.count)};
        [events removeAllObjects];
        account = reset(); nativeStates[@3] = @(PJSIP_INV_STATE_CONFIRMED); pjsua_call_info info; pjsua_call_get_info(3, &info);
        ProbeCall *source = [account addCallWithInfo:[[PJSUACallInfo alloc] initWithInfo:info parser:(id)[AKSIPUserAgent sharedUserAgent].parser]];
        __block NSUInteger sourceOnlyCount = 0;
        id filtered = [center addObserverForName:AKSIPCallTransferStatusDidChangeNotification object:source queue:nil usingBlock:^(NSNotification *note) { sourceOnlyCount++; }];
        pj_bool_t wantsMore = PJ_TRUE; pj_str_t ok = pj_str("OK"); PJSUAOnCallTransferStatus(3, 200, &ok, PJ_TRUE, &wantsMore); drain(); drain();
        results[@"successfulTransfer"] = @{@"events": events.copy, @"sourceFilteredNotificationCount": @(sourceOnlyCount), @"sourceTransferStatus": @(source.transferStatus), @"wantsMore": @(wantsMore), @"modelCount": @(account.calls.count), @"hangups": @(source.hangups)};
        [center removeObserver:filtered]; [events removeAllObjects];
        account = reset(); nativeStates[@4] = @(PJSIP_INV_STATE_INCOMING);
        PJSUAOnIncomingCall(7, 4, NULL); [AKSIPUserAgent sharedUserAgent].account = nil; drain();
        results[@"accountRemovedBeforeQueuedIncoming"] = @{@"delegateCount": @(account.delegate.incomingCount), @"events": events.copy, @"modelCount": @(account.calls.count)};
        [events removeAllObjects];
        account = reset(); nativeStates[@5] = @(PJSIP_INV_STATE_INCOMING);
        PJSUAOnIncomingCall(7, 5, NULL);
        ProbeAccount *oldAccount = account;
        ProbeAccount *newAccount = reset(); nativeStates[@5] = @(PJSIP_INV_STATE_INCOMING);
        drain();
        results[@"reusedAccountSlotRejectsOldIncoming"] = @{@"oldDelegate": @(oldAccount.delegate.incomingCount), @"newDelegate": @(newAccount.delegate.incomingCount), @"newModels": @(newAccount.calls.count)};
        [events removeAllObjects];
        account = reset(); nativeStates[@3] = @(PJSIP_INV_STATE_CONFIRMED); pjsua_call_get_info(3,&info);
        source = [account addCallWithInfo:[[PJSUACallInfo alloc] initWithInfo:info parser:(id)[AKSIPUserAgent sharedUserAgent].parser]];
        wantsMore = PJ_TRUE;
        PJSUAOnCallTransferStatus(3, 202, &ok, PJ_FALSE, &wantsMore); drain();
        results[@"provisionalTransfer"] = @{@"status": @(source.transferStatus), @"hangups": @(source.hangups), @"wantsMore": @(wantsMore), @"events": events.copy};
        [events removeAllObjects];
        PJSUAOnCallTransferStatus(3, 486, &ok, PJ_TRUE, &wantsMore); drain();
        results[@"failedTransfer"] = @{@"status": @(source.transferStatus), @"hangups": @(source.hangups), @"events": events.copy};
        for (id observer in observers) [center removeObserver:observer];
        NSData *json = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
    }
    return 0;
}
