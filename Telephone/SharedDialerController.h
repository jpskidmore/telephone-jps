#import <Cocoa/Cocoa.h>
@class JPSDiallerContacts, AccountControllers, AsyncCallHistoryViewEventTargetFactory, DialPlanRoute, DialPlanAccount;
NS_ASSUME_NONNULL_BEGIN
// Standard collapsed dialler footprint, shared with compact call cards. Native
// window-frame conversion supplies each window's actual titlebar/chrome.
FOUNDATION_EXPORT NSSize JPSCompactDiallerContentSize(void);

typedef DialPlanRoute * _Nonnull (^SharedDialerRouteResolver)(NSString *input, NSArray<DialPlanAccount *> *accounts);
@interface SharedDialerController : NSWindowController
@property(nonatomic, strong, nullable) JPSDiallerContacts *contactCompletions;
- (instancetype)initWithAccounts:(AccountControllers *)accounts historyFactory:(nullable AsyncCallHistoryViewEventTargetFactory *)factory;
- (instancetype)initWithAccounts:(AccountControllers *)accounts
                 historyFactory:(nullable AsyncCallHistoryViewEventTargetFactory *)factory
                  routeResolver:(nullable SharedDialerRouteResolver)routeResolver;
- (void)refreshAccounts;
- (void)presentFailure:(NSString *)message;
@end
NS_ASSUME_NONNULL_END
