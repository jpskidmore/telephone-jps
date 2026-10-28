#import <XCTest/XCTest.h>
#import "ActiveAccountViewController.h"
#import "ActiveAccountTransferViewController.h"
#import "AKSIPURI.h"
#import "AKTelephoneNumberFormatter.h"
#import "Telephone-Swift.h"

@interface ActiveAccountViewController (DiallerCompletionDelegateTests) <NSTokenFieldDelegate>
- (IBAction)dialFromButton:(NSButton *)sender;
@end

// Implemented with typed, immutable Contact values in ContactsRecoveryTests.swift.
// No CNContactStore, AddressBook constructor, permission request or real account
// is part of this boundary.
@interface JPSDiallerCompletionFixture : NSObject
+ (JPSDiallerContacts *)providerWithScenario:(NSInteger)scenario;
@end

@interface JPSCompletionAccountFixture : NSObject
@property(nonatomic, strong) JPSDiallerContacts *contactCompletions;
@end
@implementation JPSCompletionAccountFixture @end

@interface DiallerCompletionTests : XCTestCase
@end

@implementation DiallerCompletionTests

- (ActiveAccountViewController *)controllerWithScenario:(NSInteger)scenario {
    ActiveAccountViewController *controller = [[ActiveAccountViewController alloc] initWithNibName:@"ActiveAccountView" bundle:nil];
    [self attachProgrammaticFieldToController:controller];
    controller.contactCompletions = [JPSDiallerCompletionFixture providerWithScenario:scenario];
    return controller;
}

- (void)attachProgrammaticFieldToController:(ActiveAccountViewController *)controller {
    // Exercise the production controller and real AppKit field without loading
    // application startup, a profile, or any production account initializer.
    controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 368, 56)];
    Class fieldClass = NSClassFromString(@"AKFixedSizeTokenField") ?: NSTokenField.class;
    NSTokenField *field = [[fieldClass alloc] initWithFrame:NSMakeRect(8, 16, 352, 24)];
    field.delegate = (id<NSTokenFieldDelegate>)controller;
    field.target = controller;
    field.action = @selector(makeCall:);
    [controller.view addSubview:field];
    controller.callDestinationField = field;
    [controller awakeFromNib];
}

- (NSArray<NSString *> *)completions:(NSString *)query controller:(ActiveAccountViewController *)controller {
    NSInteger selected = 0;
    return [controller tokenField:controller.callDestinationField completionsForSubstring:query indexOfToken:0 indexOfSelectedItem:&selected];
}

- (NSArray *)token:(NSString *)text controller:(ActiveAccountViewController *)controller {
    return [controller tokenField:controller.callDestinationField representedObjectForEditingString:text];
}

- (NSArray<NSString *> *)addresses:(NSArray *)token {
    NSMutableArray *addresses = [NSMutableArray array];
    for (NSDictionary *destination in token) {
        AKSIPURI *uri = destination[kURI];
        [addresses addObject:uri.host.length ? uri.SIPAddress : uri.user];
    }
    return addresses;
}

- (void)testMissingProviderIsEmptyAndRawInputStillParsesWithoutAnyDirectory {
    ActiveAccountViewController *controller = [[ActiveAccountViewController alloc] initWithNibName:@"ActiveAccountView" bundle:nil];
    [self attachProgrammaticFieldToController:controller];
    XCTAssertEqualObjects([self completions:@"Ada" controller:controller], @[]);
    XCTAssertEqual(controller.callDestinationField.tokenStyle, NSTokenStyleNone);
    NSArray *token = [self token:@"  999  " controller:controller];
    XCTAssertEqualObjects([self addresses:token], (@[@"999"]));
    XCTAssertEqualObjects(token[0][kPhoneLabel], @"");
}

- (void)testNameCompletionsPreserveQueryOrderCapitalisationAndAllDestinations {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    XCTAssertEqualObjects([self completions:@"aDa L" controller:controller],
        (@[@"aDa Lovelace <100>", @"Ada Lovelace <200>", @"Ada Lovelace <Ada@pbx.invalid>", @"Ada Lovelace <team@pbx.invalid>"]));
    XCTAssertEqualObjects([self completions:@"Lo" controller:controller],
        (@[@"Lovelace Ada <100>", @"Lovelace Ada <200>", @"Lovelace Ada <Ada@pbx.invalid>", @"Lovelace Ada <team@pbx.invalid>"]));
    XCTAssertEqual(controller.callDestinationField.tokenStyle, NSTokenStyleRounded);
}

- (void)testPhoneAndSIPPrefixesHaveDestinationFirstFormAndOrdinaryEmailsAreExcluded {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    XCTAssertEqualObjects([self completions:@"20" controller:controller], (@[@"200 (Ada Lovelace)"]));
    XCTAssertEqualObjects([self completions:@"aDA@" controller:controller], (@[@"aDA@pbx.invalid (Ada Lovelace)"]));
    XCTAssertEqualObjects([self completions:@"team@" controller:controller], (@[@"team@pbx.invalid (Ada Lovelace)"]));
    XCTAssertEqualObjects([self completions:@"private@" controller:controller], @[]);
    XCTAssertEqualObjects([self completions:@"near@" controller:controller], @[]);
    XCTAssertEqual(controller.callDestinationField.tokenStyle, NSTokenStyleNone);
}

- (void)testMultiwordAndCompanyNamesKeepTheirDistinctSearchRules {
    ActiveAccountViewController *controller = [self controllerWithScenario:1];
    XCTAssertEqualObjects([self completions:@"Mary Jane Va" controller:controller], (@[@"Mary Jane Van Dyke <300>"]));
    XCTAssertEqualObjects([self completions:@"Van Dyke Ma" controller:controller], (@[@"Van Dyke Mary Jane <300>"]));
    XCTAssertEqualObjects([self completions:@"Mary Jane " controller:controller], (@[@"Mary Jane Van Dyke <300>"]));
    XCTAssertEqualObjects([self completions:@"Mary  Jane" controller:controller], @[], @"Repeated spaces are literal, not a normalized name query");
    XCTAssertEqualObjects([self completions:@" Mary" controller:controller], @[]);
    XCTAssertEqualObjects([self completions:@"First Resp" controller:controller], (@[@"First Responders <400>"]));
    XCTAssertEqualObjects([self completions:@"Company Given" controller:controller], @[]);
    XCTAssertEqualObjects([self completions:@"Person Organisation" controller:controller], @[]);
}

- (void)testSingleNamesPunctuationAccentsAndUnnamedPhoneFallback {
    ActiveAccountViewController *controller = [self controllerWithScenario:1];
    XCTAssertEqualObjects([self completions:@"Prin" controller:controller], (@[@"Prince <500>"]));
    XCTAssertEqualObjects([self completions:@"Solo" controller:controller], (@[@"Solo <600>"]));
    XCTAssertEqualObjects([self completions:@"Zoë O'" controller:controller], (@[@"Zoë O'Neill <700>"]));
    XCTAssertEqualObjects([self completions:@"800" controller:controller], (@[@"800"]));
    XCTAssertEqualObjects([self completions:@"unmatched" controller:controller], @[]);
}

- (void)testNamedPhoneTokenExpandsAllDestinationsAndSelectsTheEnteredPhone {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    NSArray *token = [self token:@"Ada Lovelace <200>" controller:controller];
    XCTAssertEqualObjects([self addresses:token], (@[@"100", @"200", @"Ada@pbx.invalid", @"team@pbx.invalid"]));
    XCTAssertEqualObjects([token valueForKey:kPhoneLabel], (@[@"home", @"mobile", @"sip", @"sip"]));
    controller.callDestinationField.objectValue = @[token];
    XCTAssertEqual(controller.callDestinationURIIndex, 1u);
    XCTAssertEqualObjects(controller.callDestinationURI.user, @"200");
    XCTAssertEqualObjects([controller tokenField:controller.callDestinationField editingStringForRepresentedObject:token], @"Ada Lovelace <200>");
}

- (void)testRawSIPAddressRemainsSingletonButNamedSIPAddressExpandsCaseInsensitively {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    NSArray *raw = [self token:@"Ada@pbx.invalid" controller:controller];
    XCTAssertEqualObjects([self addresses:raw], (@[@"Ada@pbx.invalid"]));
    XCTAssertEqualObjects(((AKSIPURI *)raw[0][kURI]).displayName, @"");
    NSArray *named = [self token:@"Lovelace Ada <TEAM@PBX.INVALID>" controller:controller];
    XCTAssertEqual(named.count, 4u);
    controller.callDestinationField.objectValue = @[named];
    XCTAssertEqual(controller.callDestinationURIIndex, 3u);
    XCTAssertEqualObjects(controller.callDestinationURI.SIPAddress, @"team@pbx.invalid");
    XCTAssertEqualObjects(controller.callDestinationURI.displayName, @"Ada Lovelace");
}

- (void)testNamedOrdinaryEmailKeepsExistingFirstDestinationFallback {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    NSArray *token = [self token:@"Ada Lovelace <private@pbx.invalid>" controller:controller];
    XCTAssertEqual(token.count, 4u);
    controller.callDestinationField.objectValue = @[token];
    XCTAssertEqual(controller.callDestinationURIIndex, 0u);
    XCTAssertEqualObjects(controller.callDestinationURI.user, @"100");
}

- (void)testDuplicateContactsStayOrderedAndFirstContactSelectsLastEqualDestination {
    ActiveAccountViewController *controller = [self controllerWithScenario:2];
    XCTAssertEqualObjects([self completions:@"Ada" controller:controller],
        (@[@"Ada Lovelace <100>", @"Ada Lovelace <100>", @"Ada Lovelace <200>", @"Ada Lovelace <100>", @"Ada Lovelace <900>"]));
    NSArray *token = [self token:@"Ada Lovelace <100>" controller:controller];
    XCTAssertEqualObjects([self addresses:token], (@[@"100", @"100", @"200"]));
    controller.callDestinationField.objectValue = @[token];
    XCTAssertEqual(controller.callDestinationURIIndex, 1u);
    XCTAssertEqualObjects(token[1][kPhoneLabel], @"mobile");
}

- (void)testFormattedDuplicatePhonesSelectLastNormalisedMatch {
    ActiveAccountViewController *controller = [self controllerWithScenario:4];
    NSArray *token = [self token:@"Ada Lovelace <123 456 7890>" controller:controller];
    XCTAssertEqual(token.count, 2u);
    controller.callDestinationField.objectValue = @[token];
    XCTAssertEqual(controller.callDestinationURIIndex, 1u);
    AKTelephoneNumberFormatter *formatter = [AKTelephoneNumberFormatter new];
    XCTAssertEqualObjects([formatter telephoneNumberFromString:controller.callDestinationURI.user], @"1234567890");
    XCTAssertEqualObjects(token[1][kPhoneLabel], @"mobile");
}

- (void)testConfiguredDisplayNameOrderIsDistinctFromTheNamePrefixQueryOrder {
    ActiveAccountViewController *controller = [self controllerWithScenario:5];
    XCTAssertEqualObjects([self completions:@"20" controller:controller], (@[@"200 (Lovelace Ada)"]));
    XCTAssertEqualObjects([self completions:@"Ada" controller:controller], (@[@"Ada Lovelace <100>", @"Ada Lovelace <200>"]));
    NSArray *token = [self token:@"Ada Lovelace <200>" controller:controller];
    controller.callDestinationField.objectValue = @[token];
    XCTAssertEqualObjects(controller.callDestinationURI.displayName, @"Lovelace Ada");
    XCTAssertEqual(controller.callDestinationURIIndex, 1u);
}

- (void)testRepeatedSIPLabelsAndAddressesSelectTheLastCaseInsensitiveDestination {
    ActiveAccountViewController *controller = [self controllerWithScenario:6];
    XCTAssertEqualObjects([self completions:@"Ada" controller:controller],
        (@[@"Ada@pbx.invalid (Ada Lovelace)", @"ADA@PBX.INVALID (Ada Lovelace)",
           @"Ada Lovelace <100>", @"Ada Lovelace <Ada@pbx.invalid>", @"Ada Lovelace <ADA@PBX.INVALID>"]));
    NSArray *token = [self token:@"Ada Lovelace <ada@pbx.invalid>" controller:controller];
    controller.callDestinationField.objectValue = @[token];
    XCTAssertEqual(controller.callDestinationURIIndex, 2u);
    XCTAssertEqualObjects(controller.callDestinationURI.SIPAddress, @"ADA@PBX.INVALID");
}

- (void)testMenuSelectionBelongsToItsRepresentedTokenAndRejectsExtraInput {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    NSArray *contact = [self token:@"Ada Lovelace <200>" controller:controller];
    NSArray *other = [self token:@"999" controller:controller];
    controller.callDestinationField.objectValue = @[contact, other];
    NSMenu *menu = [controller tokenField:controller.callDestinationField menuForRepresentedObject:contact];
    XCTAssertEqual(menu.numberOfItems, 4);
    XCTAssertEqual([menu itemWithTag:1].state, NSControlStateValueOn);
    XCTAssertEqual([menu itemWithTag:3].target, controller);
    [controller changeCallDestinationURIIndex:[menu itemWithTag:3]];
    XCTAssertEqualObjects(controller.callDestinationURI.SIPAddress, @"team@pbx.invalid");
    controller.callDestinationField.objectValue = @[other, contact];
    [controller changeCallDestinationURIIndex:[menu itemWithTag:0]];
    XCTAssertEqualObjects(controller.callDestinationURI.user, @"999");
    controller.callDestinationField.tokenStyle = NSTokenStyleRounded;
    XCTAssertEqualObjects([controller tokenField:controller.callDestinationField shouldAddObjects:@[contact] atIndex:1], @[]);
}

- (void)testDeniedAndInvalidatedSnapshotsCannotCompleteOrEnrichTokens {
    for (NSNumber *scenario in @[@0, @3]) {
        ActiveAccountViewController *controller = [self controllerWithScenario:scenario.integerValue];
        if (scenario.integerValue == 0) [controller.contactCompletions invalidate];
        XCTAssertEqualObjects([self completions:@"Ada" controller:controller], @[]);
        NSArray *token = [self token:@"Ada Lovelace <200>" controller:controller];
        XCTAssertEqualObjects([self addresses:token], (@[@"200"]));
        XCTAssertEqualObjects(token[0][kPhoneLabel], @"");
    }
}

- (void)testInvalidationRejectsPreviouslyReturnedMatchImmediately {
    JPSDiallerContacts *provider = [JPSDiallerCompletionFixture providerWithScenario:0];
    JPSDiallerContactMatch *match = [provider firstContactMatchingUser:@"200" SIPAddress:@"200" displayName:@"Ada Lovelace"];
    XCTAssertNotNil(match);
    XCTAssertTrue([provider isCurrentMatch:match]);
    [provider invalidate];
    XCTAssertFalse([provider isCurrentMatch:match]);
}

- (void)testTransferControllerInheritsTheSameInjectedCompletionAndTokenRules {
    // The inert object is never sent an account operation: only inherited
    // completion/representation delegates are exercised.
    JPSCompletionAccountFixture *account = [JPSCompletionAccountFixture new];
    account.contactCompletions = [JPSDiallerCompletionFixture providerWithScenario:0];
    ActiveAccountTransferViewController *controller = [[ActiveAccountTransferViewController alloc] initWithAccountController:(id)account];
    [self attachProgrammaticFieldToController:controller];
    XCTAssertEqual(controller.contactCompletions, account.contactCompletions);
    XCTAssertEqualObjects([self completions:@"Lo" controller:controller][1], @"Lovelace Ada <200>");
    NSArray *token = [self token:@"Ada Lovelace <team@pbx.invalid>" controller:controller];
    controller.callDestinationField.objectValue = @[token];
    XCTAssertEqual(controller.callDestinationURIIndex, 3u);
    XCTAssertEqualObjects(controller.callDestinationURI.SIPAddress, @"team@pbx.invalid");
}

- (NSWindow *)windowForController:(ActiveAccountViewController *)controller {
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 368, 56)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView = controller.view;
    return window;
}

- (NSTextView *)beginEditingController:(ActiveAccountViewController *)controller window:(NSWindow *)window {
    XCTAssertTrue([window makeFirstResponder:controller.callDestinationField]);
    [controller.callDestinationField selectText:nil];
    NSTextView *editor = (NSTextView *)controller.callDestinationField.currentEditor;
    XCTAssertTrue([editor isKindOfClass:NSTextView.class]);
    return editor;
}

- (void)sendKey:(NSString *)characters code:(unsigned short)code editor:(NSTextView *)editor window:(NSWindow *)window {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
        characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
    [editor keyDown:event];
}

- (void)recordCompletionState:(NSString *)phase editor:(NSTextView *)editor controller:(ActiveAccountViewController *)controller {
    if (![NSProcessInfo.processInfo.environment[@"JPS_CONTACTS70_KEYBOARD_DIAGNOSTICS"] boolValue]) return;
    NSMutableArray *windows = [NSMutableArray array];
    for (NSWindow *candidate in NSApp.windows) {
        NSMutableArray *tables = [NSMutableArray array];
        NSMutableArray<NSView *> *pending = [NSMutableArray array];
        if (candidate.contentView) [pending addObject:candidate.contentView];
        while (pending.count) {
            NSView *view = pending.lastObject; [pending removeLastObject];
            if ([view isKindOfClass:NSTableView.class]) {
                NSTableView *table = (NSTableView *)view;
                [tables addObject:@{@"class":NSStringFromClass(table.class), @"rows":@(table.numberOfRows),
                                   @"selectedRow":@(table.selectedRow), @"selection":table.selectedRowIndexes.description}];
            }
            [pending addObjectsFromArray:view.subviews];
        }
        [windows addObject:@{@"class":NSStringFromClass(candidate.class), @"visible":@(candidate.visible),
                             @"key":@(candidate.keyWindow), @"frame":NSStringFromRect(candidate.frame),
                             @"firstResponder":NSStringFromClass(candidate.firstResponder.class) ?: @"nil", @"tables":tables}];
    }
    NSDictionary *state = @{@"phase":phase, @"editorClass":NSStringFromClass(editor.class), @"text":editor.string ?: @"",
                            @"selection":NSStringFromRange(editor.selectedRange),
                            @"objects":[controller.callDestinationField.objectValue description] ?: @"nil", @"windows":windows};
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingSortedKeys error:nil];
    NSLog(@"CONTACTS70_KEYBOARD %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

- (NSTableView *)visibleCompletionTable {
    for (NSWindow *candidate in NSApp.windows) {
        if (!candidate.visible || ![NSStringFromClass(candidate.class) containsString:@"Completion"]) continue;
        NSMutableArray<NSView *> *pending = [NSMutableArray array];
        if (candidate.contentView) [pending addObject:candidate.contentView];
        while (pending.count) {
            NSView *view = pending.lastObject; [pending removeLastObject];
            if ([view isKindOfClass:NSTableView.class]) return (NSTableView *)view;
            [pending addObjectsFromArray:view.subviews];
        }
    }
    return nil;
}

- (void)sendCompletionKey:(NSString *)characters code:(unsigned short)code window:(NSWindow *)window {
    NSEventModifierFlags flags = code == 125 ? NSEventModifierFlagFunction | NSEventModifierFlagNumericPad : 0;
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
        characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
    // Dispatch to the native window and its responder chain. The inactive
    // isolated host has no application key-window routing of its own.
    [window sendEvent:event];
}

- (void)testNativeFieldEditorReturnAcceptsNamedTokenThenCallsExactlyOnce {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    NSWindow *window = [self windowForController:controller];
    __block NSUInteger deliveries = 0;
    __block AKSIPURI *delivered;
    __block NSString *label;
    controller.callDestinationHandler = ^(AKSIPURI *uri, NSString *phoneLabel) {
        deliveries++; delivered = [uri copy]; label = [phoneLabel copy];
    };
    @try {
        NSTextView *editor = [self beginEditingController:controller window:window];
        [editor insertText:@"Ada Lovelace <200>" replacementRange:NSMakeRange(NSNotFound, 0)];
        [self sendKey:@"\r" code:36 editor:editor window:window];
        // A token field can consume Return to accept the token before the
        // following Return invokes its action. Both phases use native events.
        XCTAssertTrue(controller.canMakeCall);
        if (deliveries == 0) [self sendKey:@"\r" code:36 editor:editor window:window];
        XCTAssertEqual(deliveries, 1u);
        XCTAssertEqualObjects(delivered.user, @"200");
        XCTAssertEqualObjects(label, @"mobile");
    } @finally {
        [controller.callDestinationField abortEditing];
        [window orderOut:nil]; [window close];
    }
}

- (void)testNativeCompletionKeyboardSelectionCommitsTheChosenDestination {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    NSWindow *window = [self windowForController:controller];
    __block NSUInteger deliveries = 0;
    __block AKSIPURI *delivered;
    controller.callDestinationHandler = ^(AKSIPURI *uri, NSString *label) { deliveries++; delivered = [uri copy]; };
    @try {
        [window setFrameOrigin:NSMakePoint(40, NSMinY(NSScreen.mainScreen.visibleFrame) + 240)];
        [window orderFront:nil];
        [window makeKeyWindow];
        NSTextView *editor = [self beginEditingController:controller window:window];
        [editor insertText:@"Ada L" replacementRange:NSMakeRange(NSNotFound, 0)];
        [self recordCompletionState:@"inserted" editor:editor controller:controller];
        [editor complete:nil];
        [self recordCompletionState:@"complete" editor:editor controller:controller];
        NSTableView *completionTable = [self visibleCompletionTable];
        XCTAssertNotNil(completionTable);
        XCTAssertEqual(completionTable.numberOfRows, 4);
        XCTAssertEqual(completionTable.selectedRow, 0);
        // The isolated host remains inactive. Address the native event to the
        // visible panel's window, whose actual first responder is its table,
        // rather than bypassing the panel through the editor's keyDown:.
        [self sendCompletionKey:[NSString stringWithFormat:@"%C", NSDownArrowFunctionKey] code:125 window:completionTable.window];
        [self recordCompletionState:@"down-one" editor:editor controller:controller];
        XCTAssertEqual(completionTable.selectedRow, 1);
        [self sendCompletionKey:@"\r" code:36 window:window];
        [self recordCompletionState:@"return-one" editor:editor controller:controller];
        // AppKit can use the first Return to accept a displayed completion;
        // the next Return then invokes the field's existing Call action.
        if (deliveries == 0) [self sendCompletionKey:@"\r" code:36 window:window];
        XCTAssertEqual(deliveries, 1u);
        XCTAssertEqualObjects(delivered.user, @"200");
        XCTAssertEqual(controller.callDestinationURIIndex, 1u);
    } @finally {
        [controller.callDestinationField abortEditing];
        [window orderOut:nil]; [window close];
    }
}

- (void)testCallButtonCommitsTheLiveFieldEditorBeforeDeliveringTheSameDestination {
    ActiveAccountViewController *controller = [self controllerWithScenario:0];
    NSPopUpButton *availability = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 44, 44)];
    [controller installCompactDialerWithAvailabilityView:availability target:nil historyAction:NULL moreAction:NULL];
    NSWindow *window = [self windowForController:controller];
    __block NSUInteger deliveries = 0;
    __block AKSIPURI *delivered;
    __block NSString *label;
    controller.callDestinationHandler = ^(AKSIPURI *uri, NSString *phoneLabel) {
        deliveries++; delivered = [uri copy]; label = [phoneLabel copy];
    };
    @try {
        NSTextView *editor = [self beginEditingController:controller window:window];
        [editor insertText:@"Ada Lovelace <team@pbx.invalid>" replacementRange:NSMakeRange(NSNotFound, 0)];
        NSButton *button = [controller valueForKey:@"dialButton"];
        XCTAssertEqual(button.target, controller);
        XCTAssertEqual(button.action, @selector(dialFromButton:));
        [button performClick:nil];
        XCTAssertEqual(deliveries, 1u);
        XCTAssertEqualObjects(delivered.SIPAddress, @"team@pbx.invalid");
        XCTAssertEqualObjects(label, @"sip");
        XCTAssertEqual(controller.callDestinationURIIndex, 3u);
    } @finally {
        [controller.callDestinationField abortEditing];
        [window orderOut:nil]; [window close];
    }
}

@end
