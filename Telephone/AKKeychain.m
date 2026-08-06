//
//  AKKeychain.m
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

#import "AKKeychain.h"

@implementation AKKeychain

+ (nonnull NSDictionary *)queryForService:(nonnull NSString *)service account:(nonnull NSString *)account {
    // Keep this ad-hoc-signed local build independent from the App Store app,
    // earlier development builds, and their keychain access-control entries.
    // SecItem uses the user's login keychain here because the Data Protection
    // keychain requires an Apple-issued application-identifier entitlement.
    NSString *localService = [@"jps Telephone 1.7.2 blue icon v4: " stringByAppendingString:service];
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: localService,
        (__bridge id)kSecAttrAccount: account
    };
}

+ (nonnull NSString *)passwordForService:(nonnull NSString *)service account:(nonnull NSString *)account {
    NSParameterAssert(service);
    NSParameterAssert(account);

    NSMutableDictionary *query = [[self queryForService:service account:account] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        if (status != errSecItemNotFound) {
            NSLog(@"Telephone keychain read failed (%d): %@",
                  (int)status,
                  CFBridgingRelease(SecCopyErrorMessageString(status, NULL)));
        }
        return @"";
    }

    NSData *passwordData = CFBridgingRelease(result);
    if (![passwordData isKindOfClass:NSData.class]) {
        return @"";
    }

    return [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding] ?: @"";
}

+ (BOOL)addItemWithService:(nonnull NSString *)service account:(nonnull NSString *)account password:(nonnull NSString *)password {
    NSParameterAssert(service);
    NSParameterAssert(account);
    NSParameterAssert(password);
    
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *item = [[self queryForService:service account:account] mutableCopy];
    item[(__bridge id)kSecValueData] = passwordData;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status == errSecSuccess) {
        return YES;
    }

    if (status == errSecDuplicateItem) {
        NSDictionary *attributes = @{(__bridge id)kSecValueData: passwordData};
        status = SecItemUpdate((__bridge CFDictionaryRef)[self queryForService:service account:account],
                               (__bridge CFDictionaryRef)attributes);
    }

    if (status != errSecSuccess) {
        NSLog(@"Telephone keychain write failed (%d): %@",
              (int)status,
              CFBridgingRelease(SecCopyErrorMessageString(status, NULL)));
    }

    return status == errSecSuccess;
}

@end
