// Opt-in native fixture; compile with Telephone/AKKeychain.m, -I Telephone,
// -fobjc-arc -fmodules -framework Foundation -framework Security.
// Creates/deletes only its own mkdtemp file Keychain, disables prompts, scopes
// every item operation explicitly and verifies the search list stays unchanged.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "AKKeychain.h"
@interface AKKeychain (PrivateFixture)
+ (OSStatus)prepareAccessForNewItem:(SecAccessRef)access;
@end
static BOOL checked(OSStatus status, const char *stage) {
    printf("%s: %d\n", stage, (int)status); return status == errSecSuccess;
}
int main(void) { @autoreleasepool {
    // Private absolute filename: Security's shouldAddToSearchList excludes it.
    // No default/search-list setter, implicit query, or UI interaction is used.
    char folder[] = "/private/tmp/jps-acl-fixture-XXXXXX";
    if (!mkdtemp(folder)) return 1;
    NSString *path = [@(folder) stringByAppendingPathComponent:@"fixture.keychain"];
    SecKeychainRef kc = NULL; SecKeychainItemRef legacy = NULL; SecAccessRef original = NULL, prepared = NULL;
    CFArrayRef before = NULL, after = NULL; int result = 1;
    if (!checked(SecKeychainSetUserInteractionAllowed(false), "disable fixture prompts")) return 1;
    if (!checked(SecKeychainCopySearchList(&before), "snapshot search list")) return 1;
    const char *password = "disposable synthetic fixture password";
    if (!checked(SecKeychainCreate(path.fileSystemRepresentation, (UInt32)strlen(password), password, false, NULL, &kc), "create private fixture")) goto done;
    {
        NSData *data = [@"synthetic credential" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *base = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrAccount:@"synthetic-account", (__bridge id)kSecValueData:data,
            (__bridge id)kSecUseKeychain:(__bridge id)kc};
        NSMutableDictionary *add = [base mutableCopy]; add[(__bridge id)kSecAttrService] = @"synthetic-legacy";
        add[(__bridge id)kSecReturnRef] = @YES;
        CFTypeRef ref = NULL;
        if (!checked(SecItemAdd((__bridge CFDictionaryRef)add, &ref), "create synthetic legacy")) goto done;
        legacy = (SecKeychainItemRef)ref;
        if (!checked(SecKeychainItemCopyAccess(legacy, &original), "copy original ACL")) goto done;
        add = [base mutableCopy]; add[(__bridge id)kSecAttrService] = @"synthetic-original-copy";
        add[(__bridge id)kSecAttrAccess] = (__bridge id)original;
        OSStatus baseline = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        printf("unchanged whole-ACL copy: %d\n", (int)baseline);
        if (!checked(SecKeychainItemCopyAccess(legacy, &prepared), "copy detached candidate ACL")) goto done;
        if (!checked([AKKeychain prepareAccessForNewItem:prepared], "prepare destination ACL")) goto done;
        add[(__bridge id)kSecAttrService] = @"synthetic-prepared-copy";
        add[(__bridge id)kSecAttrAccess] = (__bridge id)prepared;
        if (!checked(SecItemAdd((__bridge CFDictionaryRef)add, NULL), "create prepared copy")) goto done;
        for (NSString *service in @[@"synthetic-legacy", @"synthetic-prepared-copy"]) {
            NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrService:service, (__bridge id)kSecAttrAccount:@"synthetic-account",
                (__bridge id)kSecMatchSearchList:@[(__bridge id)kc], (__bridge id)kSecReturnData:@YES};
            CFTypeRef value = NULL;
            if (!checked(SecItemCopyMatching((__bridge CFDictionaryRef)query, &value), "scoped fixture readback")) goto done;
            BOOL same = [(__bridge id)value isEqual:data]; if (value) CFRelease(value);
            if (!same) goto done;
        }
        result = 0;
    }
 done:
    if (original) CFRelease(original); if (prepared) CFRelease(prepared); if (legacy) CFRelease(legacy);
    if (kc) { if (!checked(SecKeychainDelete(kc), "delete private fixture")) result = 1; CFRelease(kc); }
    if (!checked(SecKeychainCopySearchList(&after), "recheck search list") || !before || !after || !CFEqual(before, after)) result = 1;
    if (before) CFRelease(before); if (after) CFRelease(after);
    [[NSFileManager defaultManager] removeItemAtPath:@(folder) error:NULL];
    printf("private fixture result: %s\n", result ? "FAIL" : "PASS"); return result;
} }
