#import <Cocoa/Cocoa.h>
@class AccountControllers, AsyncCallHistoryViewEventTargetFactory, DialPlanRoute;
NS_ASSUME_NONNULL_BEGIN
typedef DialPlanRoute * _Nonnull (^SharedDialerRouteResolver)(NSString *input);
@interface SharedDialerController : NSWindowController
- (instancetype)initWithAccounts:(AccountControllers *)accounts historyFactory:(nullable AsyncCallHistoryViewEventTargetFactory *)factory;
- (instancetype)initWithAccounts:(AccountControllers *)accounts
                 historyFactory:(nullable AsyncCallHistoryViewEventTargetFactory *)factory
                  routeResolver:(nullable SharedDialerRouteResolver)routeResolver;
- (void)refreshAccounts;
- (void)presentFailure:(NSString *)message;
@end
NS_ASSUME_NONNULL_END
