#import <Cocoa/Cocoa.h>
@class AccountControllers, AsyncCallHistoryViewEventTargetFactory;
NS_ASSUME_NONNULL_BEGIN
@interface SharedDialerController : NSWindowController
- (instancetype)initWithAccounts:(AccountControllers *)accounts historyFactory:(nullable AsyncCallHistoryViewEventTargetFactory *)factory;
- (void)refreshAccounts;
- (void)presentFailure:(NSString *)message;
@end
NS_ASSUME_NONNULL_END
