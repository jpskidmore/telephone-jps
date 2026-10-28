#import <XCTest/XCTest.h>
#import "AccountPreferencesViewController.h"
#import "AKKeychain.h"

@interface AccountPreferencesViewController (CP73Seams)
- (void)readPasswordForService:(NSString *)service account:(NSString *)account completion:(AKCredentialReadCompletion)completion;
- (AKCredentialBroker *)credentialBroker;
@end

@interface CP73Memory : NSObject
@property(nonatomic, copy) NSArray *accounts;
@property(nonatomic) NSUInteger writes;
@end
@implementation CP73Memory
- (NSArray *)arrayForKey:(NSString *)key { return self.accounts ?: @[]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.accounts = value; self.writes++; }
@end

@interface CP73Broker : NSObject
@property(nonatomic) NSMutableArray *completions;
@property(nonatomic) NSUInteger invalidations;
@end
@implementation CP73Broker
- (instancetype)init { if ((self = [super init])) _completions = [NSMutableArray array]; return self; }
- (void)readPasswordForService:(NSString *)service account:(NSString *)account completion:(AKCredentialReadCompletion)completion {
    [self.completions addObject:[completion copy]];
}
- (void)invalidateService:(NSString *)service account:(NSString *)account { self.invalidations++; }
- (void)finish:(NSUInteger)index result:(AKCredentialReadResult *)result {
    AKCredentialReadCompletion completion = self.completions[index]; completion(result);
}
@end

@interface CP73Table : NSTableView
@property(nonatomic) NSInteger row;
@end
@implementation CP73Table
- (NSInteger)selectedRow { return self.row; }
- (void)reloadData {}
@end

@interface CP73Editor : AccountPreferencesViewController
@property(nonatomic) CP73Memory *memory;
@property(nonatomic) CP73Broker *broker;
@property(nonatomic) CP73Table *table;
@property(nonatomic) NSUInteger saves, errors;
@property(nonatomic) BOOL allowsSave;
@property(nonatomic, copy) NSString *savedService, *savedAccount, *savedPassword;
@end
@implementation CP73Editor
- (NSUserDefaults *)accountDefaults { return (id)self.memory; }
- (AKCredentialBroker *)credentialBroker { return (id)self.broker; }
- (BOOL)savePassword:(NSString *)password service:(NSString *)service account:(NSString *)account error:(NSError **)error {
    self.saves++; self.savedService = service; self.savedAccount = account; self.savedPassword = password;
    if (!self.allowsSave && error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecReadOnly userInfo:nil];
    return self.allowsSave;
}
- (void)presentAccountEditError:(NSString *)message field:(NSTextField *)field {
    self.errors++; self.accountEnabledCheckBox.state = NSControlStateValueOff; field.accessibilityHelp = message;
}
@end

@interface CredentialPreferencesTests : XCTestCase @end
@implementation CredentialPreferencesTests
- (NSDictionary *)account:(NSString *)identifier {
    return @{@"UUID": identifier, @"AccountEnabled": @NO, @"Domain": @"synthetic.invalid", @"Username": identifier,
             @"FullName": @"Synthetic", @"Registrar": @""};
}
- (CP73Editor *)editorWithPresentation:(BOOL)present {
    CP73Editor *editor = [CP73Editor new];
    editor.memory = [CP73Memory new]; editor.memory.accounts = @[]; editor.broker = [CP73Broker new];
    editor.allowsSave = YES;
    (void)editor.view;
    editor.table = [CP73Table new]; editor.table.row = 0; editor.accountsTable = editor.table;
    editor.memory.accounts = @[[self account:@"one"], [self account:@"two"]];
    [editor.broker.completions removeAllObjects];
    [editor populateFieldsForAccountAtIndex:0];
    if (present) [editor viewWillAppear];
    return editor;
}
- (CP73Editor *)editor { return [self editorWithPresentation:YES]; }
- (void)editPassword:(NSString *)password editor:(CP73Editor *)editor {
    editor.passwordField.stringValue = password;
    [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:editor.passwordField];
}
- (void)enable:(CP73Editor *)editor { editor.accountEnabledCheckBox.state = NSControlStateValueOn; [editor changeAccountEnabled:nil]; }

- (void)testHiddenAccountsPaneDoesNotRequestPasswordUntilPresented {
    CP73Editor *editor = [CP73Editor new];
    editor.memory = [CP73Memory new]; editor.memory.accounts = @[[self account:@"one"]];
    editor.broker = [CP73Broker new]; editor.allowsSave = YES;
    (void)editor.view;
    editor.table = [CP73Table new]; editor.table.row = 0; editor.accountsTable = editor.table;
    [editor populateFieldsForAccountAtIndex:0];
    XCTAssertEqual(editor.broker.completions.count, 0);
    [editor viewWillAppear];
    XCTAssertEqual(editor.broker.completions.count, 1);
    [editor viewWillAppear];
    XCTAssertEqual(editor.broker.completions.count, 1);
}

- (void)testLookupIsPendingAndUnchangedSaveDoesNotReadOrWriteAgain {
    CP73Editor *editor = [self editor];
    XCTAssertEqual(editor.broker.completions.count, 1);
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    XCTAssertGreaterThan(editor.passwordField.accessibilityHelp.length, 0);
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"synthetic-secret"]];
    editor.accountDescriptionField.stringValue = @"Changed description";
    [self enable:editor];
    XCTAssertEqual(editor.broker.completions.count, 1); XCTAssertEqual(editor.saves, 0);
    XCTAssertEqual(editor.memory.writes, 1);
    XCTAssertEqualObjects(editor.memory.accounts[0][@"Description"], @"Changed description");
}

- (void)testSelectionAndExternalAccountChangesRejectLateCredentialResults {
    CP73Editor *editor = [self editor];
    editor.table.row = 1; [editor populateFieldsForAccountAtIndex:1];
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"wrong-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    NSMutableArray *accounts = [editor.memory.accounts mutableCopy];
    NSMutableDictionary *changed = [accounts[1] mutableCopy]; changed[@"Domain"] = @"changed.invalid"; accounts[1] = changed;
    editor.memory.accounts = accounts;
    [editor.broker finish:1 result:[AKCredentialReadResult successWithPassword:@"stale-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    [self editPassword:@"explicit-secret" editor:editor]; [self enable:editor];
    XCTAssertEqual(editor.saves, 0); XCTAssertEqual(editor.memory.writes, 0); XCTAssertEqual(editor.errors, 1);
}

- (void)testExplicitPasswordEditSurvivesPendingReadAndSavesOnlyOwnerInput {
    CP73Editor *editor = [self editor];
    [self editPassword:@"replacement" editor:editor];
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"old-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"replacement");
    [self enable:editor];
    XCTAssertEqual(editor.saves, 1); XCTAssertEqualObjects(editor.savedPassword, @"replacement");
    XCTAssertEqual(editor.broker.invalidations, 1); XCTAssertEqual(editor.memory.writes, 1);
}

- (void)testCancelledDeniedAndMalformedLookupCannotEnableWithAnEmptyPassword {
    for (NSNumber *status in @[@(AKCredentialReadStatusCancelled), @(AKCredentialReadStatusDenied), @(AKCredentialReadStatusInvalidData), @(AKCredentialReadStatusFailure)]) {
        CP73Editor *editor = [self editor];
        [editor.broker finish:0 result:[AKCredentialReadResult failureWithStatus:status.integerValue securityStatus:errSecAuthFailed]];
        XCTAssertEqual(editor.broker.completions.count, 1); XCTAssertEqual(editor.memory.writes, 0);
        XCTAssertGreaterThan(editor.passwordField.accessibilityHelp.length, 0);
        [self enable:editor]; // An owner action explicitly retries; no registration is committed.
        XCTAssertEqual(editor.saves, 0); XCTAssertEqual(editor.memory.writes, 0);
        XCTAssertEqual(editor.broker.invalidations, 1); XCTAssertEqual(editor.broker.completions.count, 2);
        XCTAssertEqual(editor.accountEnabledCheckBox.state, NSControlStateValueOff);
    }
}

- (void)testMissingCredentialIsDistinctFromASuccessfulEmptyPassword {
    CP73Editor *missing = [self editor];
    [missing.broker finish:0 result:[AKCredentialReadResult failureWithStatus:AKCredentialReadStatusMissing securityStatus:errSecItemNotFound]];
    [self enable:missing]; XCTAssertEqual(missing.memory.writes, 0); XCTAssertEqual(missing.saves, 0);
    CP73Editor *empty = [self editor];
    [empty.broker finish:0 result:[AKCredentialReadResult successWithPassword:@""]];
    [self enable:empty]; XCTAssertEqual(empty.memory.writes, 1); XCTAssertEqual(empty.saves, 0);
}

- (void)testChangedCredentialDestinationRequiresAnExplicitPasswordEdit {
    CP73Editor *editor = [self editor];
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"old-secret"]];
    editor.domainField.stringValue = @"new.invalid";
    [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:editor.domainField];
    [self enable:editor]; XCTAssertEqual(editor.memory.writes, 0); XCTAssertEqual(editor.saves, 0);
    [self editPassword:@"replacement" editor:editor]; [self enable:editor];
    XCTAssertEqual(editor.saves, 1); XCTAssertEqualObjects(editor.savedService, @"SIP: new.invalid");
    XCTAssertEqualObjects(editor.savedAccount, @"one");
}

- (void)testFailedPasswordWritePreservesAccountAndAllowsExplicitRetry {
    CP73Editor *editor = [self editor];
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"old-secret"]];
    NSArray *before = editor.memory.accounts;
    [self editPassword:@"replacement" editor:editor]; editor.allowsSave = NO; [self enable:editor];
    XCTAssertEqualObjects(editor.memory.accounts, before); XCTAssertEqual(editor.memory.writes, 0);
    XCTAssertTrue(editor.passwordField.enabled); XCTAssertEqualObjects(editor.passwordField.stringValue, @"replacement");
    editor.allowsSave = YES; [self enable:editor];
    XCTAssertEqual(editor.memory.writes, 1); XCTAssertEqual(editor.broker.completions.count, 1);
}

- (void)testHidingClearsSecretPreservesNonSecretDraftAndRejectsLateLookup {
    CP73Editor *editor = [self editor]; editor.accountDescriptionField.stringValue = @"Unsaved description";
    [editor viewWillDisappear];
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"late-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    [editor viewWillAppear];
    XCTAssertEqualObjects(editor.accountDescriptionField.stringValue, @"Unsaved description");
    XCTAssertEqual(editor.broker.completions.count, 2);
    [editor.broker finish:1 result:[AKCredentialReadResult successWithPassword:@"fresh-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"fresh-secret");
}

- (void)testRepeatedHideDoesNotForgetThatAnUnsavedReplacementWasCleared {
    CP73Editor *editor = [self editor];
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"old-secret"]];
    [self editPassword:@"replacement" editor:editor];
    for (NSUInteger i = 0; i < 3; i++) {
        [editor viewWillDisappear]; [editor viewWillAppear];
        [self enable:editor];
        XCTAssertEqual(editor.broker.completions.count, 1);
        XCTAssertEqual(editor.memory.writes, 0); XCTAssertEqual(editor.saves, 0);
        XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    }
    [self editPassword:@"replacement" editor:editor]; [self enable:editor];
    XCTAssertEqual(editor.memory.writes, 1); XCTAssertEqual(editor.saves, 1);
}

- (void)testSuccessfulExplicitRetryCanEnableWithoutAThirdReadOrCredentialWrite {
    CP73Editor *editor = [self editor];
    [editor.broker finish:0 result:[AKCredentialReadResult failureWithStatus:AKCredentialReadStatusCancelled securityStatus:errSecUserCanceled]];
    [self enable:editor];
    [editor.broker finish:1 result:[AKCredentialReadResult successWithPassword:@"synthetic-secret"]];
    XCTAssertEqual(editor.memory.writes, 0);
    XCTAssertTrue([editor.accountEnabledCheckBox.accessibilityHelp containsString:@"Enable this account again"]);
    XCTAssertEqualObjects(editor.accountEnabledCheckBox.toolTip, editor.accountEnabledCheckBox.accessibilityHelp);
    [self enable:editor];
    XCTAssertEqual(editor.memory.writes, 1); XCTAssertEqual(editor.saves, 0);
    XCTAssertEqual(editor.broker.completions.count, 2);
    XCTAssertNil(editor.accountEnabledCheckBox.toolTip);
}

- (void)testHidingAnUnsavedPasswordRequiresItToBeEnteredAgain {
    CP73Editor *editor = [self editor];
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"old-secret"]];
    [self editPassword:@"replacement" editor:editor]; [editor viewWillDisappear]; [editor viewWillAppear];
    [self enable:editor];
    XCTAssertEqual(editor.memory.writes, 0); XCTAssertEqual(editor.saves, 0);
    XCTAssertEqual(editor.broker.completions.count, 1);
    [self editPassword:@"replacement" editor:editor]; [self enable:editor]; XCTAssertEqual(editor.memory.writes, 1);
}

- (void)testHiddenLateEditAndEnableCannotWriteCredentialsOrCommitAccount {
    CP73Editor *editor = [self editor];
    [editor viewWillDisappear];
    [self editPassword:@"late-replacement" editor:editor];
    [self enable:editor];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    XCTAssertEqual(editor.saves, 0); XCTAssertEqual(editor.memory.writes, 0);
    XCTAssertEqual(editor.broker.invalidations, 0); XCTAssertEqual(editor.broker.completions.count, 1);
    XCTAssertEqual(editor.accountEnabledCheckBox.state, NSControlStateValueOff);
}

- (void)testActualWindowCloseClearsSecretAndReopenSignalAdmitsOneLookup {
    // Unlike the offscreen form fixtures above, let the native host window
    // deliver the first appearance so its callback owns the admitted read.
    CP73Editor *editor = [self editorWithPresentation:NO];
    XCTAssertEqual(editor.broker.completions.count, 0);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 548, 304)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentViewController = editor;
    [window orderFront:nil];
    XCTAssertEqual([editor valueForKey:@"credentialObservedWindow"], window);
    XCTAssertEqual(editor.broker.completions.count, 1);
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"synthetic-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"synthetic-secret");
    [window close];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    [editor.broker finish:0 result:[AKCredentialReadResult successWithPassword:@"late-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"");
    [window orderFront:nil];
    // Key focus is controlled by WindowServer and the test runner. Exercise the
    // registered reopen signal without depending on another app's active window.
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:window];
    XCTAssertEqual(editor.broker.completions.count, 2);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:window];
    XCTAssertEqual(editor.broker.completions.count, 2);
    [editor.broker finish:1 result:[AKCredentialReadResult successWithPassword:@"fresh-secret"]];
    XCTAssertEqualObjects(editor.passwordField.stringValue, @"fresh-secret");
    [window close];
}
@end
