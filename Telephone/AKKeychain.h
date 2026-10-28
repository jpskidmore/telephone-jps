//
//  AKKeychain.h
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

@import Foundation;
@import Security;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AKCredentialReadStatus) {
    AKCredentialReadStatusSuccess,
    AKCredentialReadStatusMissing,
    AKCredentialReadStatusCancelled,
    AKCredentialReadStatusDenied,
    AKCredentialReadStatusInvalidData,
    AKCredentialReadStatusFailure,
    AKCredentialReadStatusSuperseded
};

// A failed read never supplies a password. In particular, cancellation is not
// interchangeable with a successfully read, legitimately empty password.
@interface AKCredentialReadResult : NSObject
@property(nonatomic, readonly) AKCredentialReadStatus status;
@property(nonatomic, readonly, copy, nullable) NSString *password;
@property(nonatomic, readonly) OSStatus securityStatus;
@property(nonatomic, readonly, nullable) NSError *error;
+ (instancetype)successWithPassword:(NSString *)password;
+ (instancetype)failureWithStatus:(AKCredentialReadStatus)status securityStatus:(OSStatus)securityStatus;
- (instancetype)init NS_UNAVAILABLE;
@end

typedef AKCredentialReadResult * _Nonnull (^AKCredentialReader)(NSString *service, NSString *account);
typedef void (^AKCredentialReadCompletion)(AKCredentialReadResult *result);
typedef NSTimeInterval (^AKCredentialClock)(void);

// The reader runs on one serial utility worker. Every completion is delivered
// asynchronously on main. A blocked OS prompt cannot be cancelled by the broker;
// invalidation cancels delivery immediately and fences its eventual result.
@interface AKCredentialBroker : NSObject
+ (instancetype)sharedBroker;
- (instancetype)initWithReader:(AKCredentialReader)reader;
- (instancetype)initWithReader:(AKCredentialReader)reader
                 cacheLifetime:(NSTimeInterval)cacheLifetime
          maximumCachedEntries:(NSUInteger)maximumCachedEntries
                         clock:(AKCredentialClock)clock NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)readPasswordForService:(NSString *)service account:(NSString *)account completion:(AKCredentialReadCompletion)completion;
- (void)invalidateService:(NSString *)service account:(NSString *)account;
- (void)invalidateAll;
- (void)shutdown;
@end

// A Keychain Services wrapper.
@interface AKKeychain : NSObject

// Returns password for the first Keychain item with a specified service and account.
+ (NSString *)passwordForService:(NSString *)service account:(NSString *)account;

// Synchronous boundary for the broker's worker; UI consumers use the broker.
+ (AKCredentialReadResult *)readResultForService:(NSString *)service account:(NSString *)account;
// Pure status/data conversion, also used by synthetic Security fixtures.
+ (AKCredentialReadResult *)resultForSecurityStatus:(OSStatus)status data:(nullable id)data;

// Adds an item to the Keychain with a specified service, account, and password. If the same item already
// exists, its password will be replaced with the new one.
+ (BOOL)addItemWithService:(NSString *)service account:(NSString *)account password:(NSString *)password;
+ (BOOL)addItemWithService:(NSString *)service account:(NSString *)account password:(NSString *)password
                    error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
