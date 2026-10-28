//
//  AccountPreferencesViewController.m
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

#import "AccountPreferencesViewController.h"

@import UseCases;

#import "AKKeychain.h"

#import "AccountSetupController.h"
#import "PreferencesController.h"

#import "Telephone-Swift.h"


// Pasteboard type.
static NSString * const kAKSIPAccountPboardType = @"AKSIPAccountPboardType";

// Maximum number of accounts.
static const NSUInteger kAccountsMax = 32;

@interface AccountPreferencesViewController ()
@property(nonatomic) NSUInteger credentialGeneration;
@property(nonatomic, copy) NSDictionary *credentialAccountSnapshot;
@property(nonatomic, copy) NSString *credentialService;
@property(nonatomic, copy) NSString *credentialUsername;
@property(nonatomic, copy) NSString *loadedCredentialPassword;
@property(nonatomic) AKCredentialReadStatus credentialReadStatus;
@property(nonatomic) BOOL credentialReadPending;
@property(nonatomic) BOOL credentialPasswordWasEdited;
@property(nonatomic) BOOL credentialRequiresReplacement;
@property(nonatomic) BOOL credentialPresentationActive;
@property(nonatomic) BOOL credentialRetryAwaitingEnable;
@property(nonatomic, weak) NSWindow *credentialObservedWindow;
@end

@implementation AccountPreferencesViewController

- (NSUserDefaults *)accountDefaults { return NSUserDefaults.standardUserDefaults; }

- (AKCredentialBroker *)credentialBroker { return AKCredentialBroker.sharedBroker; }

- (void)readPasswordForService:(NSString *)service account:(NSString *)account completion:(AKCredentialReadCompletion)completion {
    [[self credentialBroker] readPasswordForService:service account:account completion:completion];
}

- (BOOL)savePassword:(NSString *)password service:(NSString *)service account:(NSString *)account error:(NSError **)error {
    return [AKKeychain addItemWithService:service account:account password:password error:error];
}

- (NSString *)credentialServiceForAccount:(NSDictionary *)account {
    NSString *registrar = account[AKSIPAccountKeys.registrar];
    return [NSString stringWithFormat:@"SIP: %@", registrar.length ? registrar : (account[AKSIPAccountKeys.domain] ?: @"")];
}

- (void)resetCredentialSnapshot {
    self.credentialGeneration++;
    self.credentialAccountSnapshot = nil;
    self.credentialService = nil;
    self.credentialUsername = nil;
    self.loadedCredentialPassword = nil;
    self.credentialReadStatus = AKCredentialReadStatusSuperseded;
    self.credentialReadPending = NO;
    self.credentialPasswordWasEdited = NO;
    self.credentialRequiresReplacement = NO;
    self.credentialRetryAwaitingEnable = NO;
    self.passwordField.stringValue = @"";
    self.passwordField.placeholderString = nil;
    self.passwordField.accessibilityHelp = nil;
    self.passwordField.toolTip = nil;
    self.accountEnabledCheckBox.accessibilityHelp = nil;
    self.accountEnabledCheckBox.toolTip = nil;
}

- (BOOL)selectedAccountMatchesCredentialSnapshot {
    NSArray *accounts = [[self accountDefaults] arrayForKey:UserDefaultsKeys.accounts];
    NSInteger row = self.accountsTable.selectedRow;
    return self.credentialAccountSnapshot && row >= 0 && (NSUInteger)row < accounts.count &&
        [accounts[(NSUInteger)row] isEqualToDictionary:self.credentialAccountSnapshot];
}

- (NSString *)currentCredentialService {
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *registrar = [self.registrarField.stringValue stringByTrimmingCharactersInSet:spaces];
    NSString *domain = [self.domainField.stringValue stringByTrimmingCharactersInSet:spaces];
    return [NSString stringWithFormat:@"SIP: %@", registrar.length ? registrar : domain];
}

- (BOOL)formUsesLoadedCredentialIdentity {
    return [[self currentCredentialService] isEqualToString:self.credentialService] &&
        [[self.usernameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
            isEqualToString:self.credentialUsername];
}

- (NSString *)credentialReadHelpForStatus:(AKCredentialReadStatus)status {
    switch (status) {
        case AKCredentialReadStatusMissing:
            return NSLocalizedString(@"No password is saved. Enter a password before enabling this account.", @"Missing account credential.");
        case AKCredentialReadStatusCancelled:
            return NSLocalizedString(@"Keychain access was cancelled. Enter a replacement password, or enable the account to request access again.", @"Cancelled account credential lookup.");
        case AKCredentialReadStatusDenied:
            return NSLocalizedString(@"Keychain access was denied. Enter a replacement password, or enable the account to request access again.", @"Denied account credential lookup.");
        case AKCredentialReadStatusInvalidData:
            return NSLocalizedString(@"The saved password could not be read. Enter a replacement password, or enable the account to try again.", @"Invalid account credential data.");
        default:
            return NSLocalizedString(@"The password is unavailable. Enter a replacement password, or enable the account to try again.", @"Unavailable account credential lookup.");
    }
}

- (void)loadCredentialForAccount:(NSDictionary *)account {
    self.credentialGeneration++;
    NSUInteger generation = self.credentialGeneration;
    self.credentialAccountSnapshot = [account copy];
    self.credentialService = [self credentialServiceForAccount:account];
    self.credentialUsername = account[AKSIPAccountKeys.username] ?: @"";
    self.loadedCredentialPassword = nil;
    self.credentialReadPending = NO;
    self.credentialReadStatus = AKCredentialReadStatusSuperseded;
    if (!self.credentialPresentationActive) return;
    self.credentialReadPending = YES;
    self.passwordField.placeholderString = NSLocalizedString(@"Loading password…", @"Pending account credential lookup.");
    self.passwordField.accessibilityHelp = NSLocalizedString(@"The saved password is being requested. You may enter a replacement password while waiting.", @"Pending account credential help.");
    self.passwordField.toolTip = self.passwordField.accessibilityHelp;
    __weak typeof(self) weakSelf = self;
    [self readPasswordForService:self.credentialService account:self.credentialUsername completion:^(AKCredentialReadResult *result) {
        AccountPreferencesViewController *controller = weakSelf;
        if (!controller || !controller.credentialPresentationActive || controller.credentialGeneration != generation ||
            ![controller selectedAccountMatchesCredentialSnapshot] || ![controller formUsesLoadedCredentialIdentity]) return;
        controller.credentialReadPending = NO;
        controller.credentialReadStatus = result.status;
        if (result.status == AKCredentialReadStatusSuccess) {
            controller.loadedCredentialPassword = result.password;
            if (!controller.credentialPasswordWasEdited) controller.passwordField.stringValue = result.password;
            controller.passwordField.placeholderString = nil;
            controller.passwordField.accessibilityHelp = nil;
            controller.passwordField.toolTip = nil;
            NSString *readyHelp = controller.credentialRetryAwaitingEnable
                ? NSLocalizedString(@"Password loaded. Enable this account again to continue.", @"Explicit credential retry completed.") : nil;
            controller.accountEnabledCheckBox.accessibilityHelp = readyHelp;
            controller.accountEnabledCheckBox.toolTip = readyHelp;
        } else {
            NSString *help = [controller credentialReadHelpForStatus:result.status];
            controller.passwordField.placeholderString = NSLocalizedString(@"Password unavailable", @"Failed account credential lookup.");
            controller.passwordField.accessibilityHelp = help;
            controller.passwordField.toolTip = help;
            controller.accountEnabledCheckBox.accessibilityHelp = help;
            controller.accountEnabledCheckBox.toolTip = help;
        }
        NSAccessibilityPostNotification(controller.passwordField, NSAccessibilityValueChangedNotification);
    }];
}

- (void)credentialFieldDidChange:(NSNotification *)notification {
    if (!self.credentialPresentationActive) {
        if (notification.object == self.passwordField) self.passwordField.stringValue = @"";
        return;
    }
    if (notification.object == self.passwordField) {
        self.credentialPasswordWasEdited = YES;
        self.credentialRetryAwaitingEnable = NO;
        self.accountEnabledCheckBox.accessibilityHelp = nil;
        self.accountEnabledCheckBox.toolTip = nil;
        return;
    }
    // Identity edits make the in-flight result belong to the old form. Keep
    // deliberately entered text, but never copy the old saved secret to a new key.
    if (![self formUsesLoadedCredentialIdentity]) {
        self.credentialGeneration++;
        self.credentialReadPending = NO;
        self.credentialReadStatus = AKCredentialReadStatusSuperseded;
        self.credentialRetryAwaitingEnable = NO;
        self.loadedCredentialPassword = nil;
        if (!self.credentialPasswordWasEdited) self.passwordField.stringValue = @"";
        NSString *help = NSLocalizedString(@"The credential destination changed. Enter a password before enabling this account.", @"Changed account credential identity.");
        self.passwordField.placeholderString = NSLocalizedString(@"Enter password", @"Replacement account credential.");
        self.passwordField.accessibilityHelp = help;
        self.passwordField.toolTip = help;
    }
}

- (void)resumeCredentialPresentation {
    if (self.credentialPresentationActive) return;
    self.credentialPresentationActive = YES;
    if ([self selectedAccountMatchesCredentialSnapshot]) {
        if (self.credentialRequiresReplacement || ![self formUsesLoadedCredentialIdentity]) {
            self.passwordField.placeholderString = NSLocalizedString(@"Enter password", @"Replacement account credential.");
            self.passwordField.accessibilityHelp = NSLocalizedString(@"Enter the replacement password again before enabling this account.", @"Discarded unsaved credential help.");
        } else if (!self.credentialReadPending) {
            [self loadCredentialForAccount:self.credentialAccountSnapshot];
        }
    } else {
        [self populateFieldsForAccountAtIndex:self.accountsTable.selectedRow];
    }
}

- (void)suspendCredentialPresentation {
    self.credentialPresentationActive = NO;
    self.credentialRequiresReplacement = self.credentialRequiresReplacement || self.credentialPasswordWasEdited ||
        (self.loadedCredentialPassword && ![self.passwordField.stringValue isEqualToString:self.loadedCredentialPassword]);
    self.credentialGeneration++;
    self.credentialReadPending = NO;
    self.credentialReadStatus = AKCredentialReadStatusSuperseded;
    self.credentialPasswordWasEdited = NO;
    self.credentialRetryAwaitingEnable = NO;
    self.loadedCredentialPassword = nil;
    self.passwordField.stringValue = @"";
    self.passwordField.placeholderString = nil;
    self.passwordField.accessibilityHelp = nil;
    self.passwordField.toolTip = nil;
    self.accountEnabledCheckBox.accessibilityHelp = nil;
    self.accountEnabledCheckBox.toolTip = nil;
}


- (void)viewWillAppear {
    [super viewWillAppear];
    [self resumeCredentialPresentation];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    NSWindow *window = self.view.window;
    if (self.credentialObservedWindow == window) return;
    NSNotificationCenter *centre = NSNotificationCenter.defaultCenter;
    if (self.credentialObservedWindow) {
        [centre removeObserver:self name:NSWindowWillCloseNotification object:self.credentialObservedWindow];
        [centre removeObserver:self name:NSWindowDidBecomeKeyNotification object:self.credentialObservedWindow];
    }
    self.credentialObservedWindow = window;
    if (window) {
        [centre addObserver:self selector:@selector(credentialWindowWillClose:) name:NSWindowWillCloseNotification object:window];
        [centre addObserver:self selector:@selector(credentialWindowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:window];
    }
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    [self suspendCredentialPresentation];
}

- (void)credentialWindowWillClose:(NSNotification *)notification {
    if (self.view.window == notification.object) [self suspendCredentialPresentation];
}

- (void)credentialWindowDidBecomeKey:(NSNotification *)notification {
    if (self.view.window == notification.object) [self resumeCredentialPresentation];
}

@synthesize accountSetupController = _accountSetupController;

- (AccountSetupController *)accountSetupController {
    if (_accountSetupController == nil) {
        _accountSetupController = [[AccountSetupController alloc] init];
    }
    return _accountSetupController;
}

- (instancetype)init {
    self = [super initWithNibName:@"AccountPreferencesView" bundle:nil];
    if (self != nil) {
        [self setTitle:NSLocalizedString(@"Accounts", @"Accounts preferences window title.")];
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Native accessibility exposes the cell; Interface Builder descriptions on
    // its control view do not propagate into that unignored element.
    self.accountDescriptionField.cell.accessibilityLabel = NSLocalizedString(@"Account description", @"Accessible control purpose.");
    self.fullNameField.cell.accessibilityLabel = NSLocalizedString(@"Full name", @"Accessible control purpose.");
    self.domainField.cell.accessibilityLabel = NSLocalizedString(@"Account domain", @"Accessible control purpose.");
    self.usernameField.cell.accessibilityLabel = NSLocalizedString(@"Account username", @"Accessible control purpose.");
    self.passwordField.cell.accessibilityLabel = NSLocalizedString(@"Account password", @"Accessible control purpose.");
    self.reregistrationTimeField.cell.accessibilityLabel = NSLocalizedString(@"Registration interval", @"Accessible control purpose.");
    self.plusCharacterSubstitutionField.cell.accessibilityLabel = NSLocalizedString(@"Plus character replacement", @"Accessible control purpose.");
    self.proxyHostField.cell.accessibilityLabel = NSLocalizedString(@"Account proxy host", @"Accessible control purpose.");
    self.proxyPortField.cell.accessibilityLabel = NSLocalizedString(@"Account proxy port", @"Accessible control purpose.");
    self.SIPAddressField.cell.accessibilityLabel = NSLocalizedString(@"SIP address", @"Accessible control purpose.");
    self.registrarField.cell.accessibilityLabel = NSLocalizedString(@"Registrar", @"Accessible control purpose.");
    for (NSTextField *field in @[self.passwordField, self.usernameField, self.domainField, self.registrarField]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(credentialFieldDidChange:)
                                                   name:NSControlTextDidChangeNotification object:field];
    }

    NSString *connectionScope = NSLocalizedString(@"Connection settings for the selected account.", @"Account Connection tab scope.");
    NSView *connectionView = self.proxyHostField.superview;
    connectionView.accessibilityElement = YES;
    connectionView.accessibilityRole = NSAccessibilityGroupRole;
    connectionView.accessibilityLabel = connectionScope;
    for (NSView *view in self.view.subviews) {
        if ([view isKindOfClass:NSTabView.class]) {
            for (NSTabViewItem *item in ((NSTabView *)view).tabViewItems) {
                if (item.view == connectionView) {
                    item.toolTip = connectionScope;
                }
            }
        }
    }
}

- (void)awakeFromNib {
    // Register a pasteboard type to rearrange accounts with drag and drop.
    [[self accountsTable] registerForDraggedTypes:@[kAKSIPAccountPboardType]];
    
    NSInteger row = [[self accountsTable] selectedRow];
    if (row != -1) {
        [self populateFieldsForAccountAtIndex:row];
    }
    
    NSUserDefaults *defaults = [self accountDefaults];
    NSUInteger accountsCount = [[defaults arrayForKey:UserDefaultsKeys.accounts] count];
    if (accountsCount >= kAccountsMax) {
        [[self addAccountButton] setEnabled:NO];
    }
    
    // Subscribe to the account setup notifications.
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(accountSetupControllerDidAddAccount:)
               name:AKAccountSetupControllerDidAddAccountNotification
             object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (IBAction)showAddAccountSheet:(id)sender {
    [[[self accountSetupController] fullNameField] setStringValue:@""];
    [[[self accountSetupController] domainField] setStringValue:@""];
    [[[self accountSetupController] usernameField] setStringValue:@""];
    [[[self accountSetupController] passwordField] setStringValue:@""];
    
    [[[self accountSetupController] fullNameInvalidDataView] setHidden:YES];
    [[[self accountSetupController] domainInvalidDataView] setHidden:YES];
    [[[self accountSetupController] usernameInvalidDataView] setHidden:YES];
    [[[self accountSetupController] passwordInvalidDataView] setHidden:YES];
    
    [[[self accountSetupController] window] makeFirstResponder:
     [[self accountSetupController] fullNameField]];

    [[[self view] window] beginSheet:[[self accountSetupController] window] completionHandler:nil];
}

- (IBAction)showRemoveAccountSheet:(id)sender {
    NSInteger index = [[self accountsTable] selectedRow];
    if (index == -1) {
        NSBeep();
        return;
    }
    
    NSTableColumn *theColumn = [[NSTableColumn alloc] initWithIdentifier:@"SIPAddress"];
    NSString *selectedAccount = [[[self accountsTable] dataSource] tableView:[self accountsTable]
                                                   objectValueForTableColumn:theColumn
                                                                         row:index];
    
    NSAlert *alert = [[NSAlert alloc] init];
    NSButton *delete = [alert addButtonWithTitle:NSLocalizedString(@"Delete", @"Delete button.")];
    delete.hasDestructiveAction = YES;
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button.")].keyEquivalent = @"\033";
    [alert setMessageText:[NSString stringWithFormat:
                           NSLocalizedString(@"Delete “%@”?", @"Account removal confirmation."),
                           selectedAccount]];
    [alert setInformativeText:
     [NSString stringWithFormat:
      NSLocalizedString(@"This will delete your currently set up account “%@”.",
                        @"Account removal confirmation informative text."),
      selectedAccount]];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert beginSheetModalForWindow:[[self accountsTable] window] completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self removeAccountAtIndex:[[self accountsTable] selectedRow]];
        }
    }];
}

- (void)removeAccountAtIndex:(NSInteger)index {
    NSUserDefaults *defaults = [self accountDefaults];
    NSMutableArray *savedAccounts = [NSMutableArray arrayWithArray:[defaults arrayForKey:UserDefaultsKeys.accounts]];
    if (index < 0 || (NSUInteger)index >= savedAccounts.count) return;
    NSDictionary *removedAccount = savedAccounts[(NSUInteger)index];
    NSString *uuid = removedAccount[AKSIPAccountKeys.uuid];
    [[self credentialBroker] invalidateService:[self credentialServiceForAccount:removedAccount]
                                     account:removedAccount[AKSIPAccountKeys.username] ?: @""];
    [self resetCredentialSnapshot];
    [savedAccounts removeObjectAtIndex:index];
    [defaults setObject:savedAccounts forKey:UserDefaultsKeys.accounts];
    
    if ([savedAccounts count] < kAccountsMax) {
        [[self addAccountButton] setEnabled:YES];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:AKPreferencesControllerDidRemoveAccountNotification
                                                        object:[self preferencesController]
                                                      userInfo:@{kAccountIndex: @(index), AKSIPAccountKeys.uuid: uuid}];
    [[self accountsTable] reloadData];
    
    // Select none, last or previous account.
    if ([savedAccounts count] == 0) {
        [self populateFieldsForAccountAtIndex:-1];
        return;
        
    } else if (index >= ([savedAccounts count] - 1)) {
        [[self accountsTable] selectRowIndexes:[NSIndexSet indexSetWithIndex:([savedAccounts count] - 1)]
                          byExtendingSelection:NO];
        
        [self populateFieldsForAccountAtIndex:([savedAccounts count] - 1)];
        
    } else {
        [[self accountsTable] selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        
        [self populateFieldsForAccountAtIndex:index];
    }
}

- (void)populateFieldsForAccountAtIndex:(NSInteger)index {
    NSUserDefaults *defaults = [self accountDefaults];
    NSArray *savedAccounts = [defaults arrayForKey:UserDefaultsKeys.accounts];
    [self resetCredentialSnapshot];
    
    if (index >= 0 && (NSUInteger)index < savedAccounts.count) {
        NSDictionary *accountDict = savedAccounts[index];
        
        [[self accountEnabledCheckBox] setEnabled:YES];
        
        // Conditionally enable fields and set checkboxes state.
        if ([accountDict[UserDefaultsKeys.accountEnabled] boolValue]) {
            [[self accountEnabledCheckBox] setState:NSControlStateValueOn];
            [[self accountDescriptionField] setEnabled:NO];
            [[self fullNameField] setEnabled:NO];
            [[self domainField] setEnabled:NO];
            [[self usernameField] setEnabled:NO];
            [[self passwordField] setEnabled:NO];
            [[self reregistrationTimeField] setEnabled:NO];
            [[self substitutePlusCharacterCheckBox] setEnabled:NO];
            [[self substitutePlusCharacterCheckBox] setState:[accountDict[UserDefaultsKeys.substitutePlusCharacter] integerValue]];
            [[self plusCharacterSubstitutionField] setEnabled:NO];
            [[self useProxyCheckBox] setState:[accountDict[AKSIPAccountKeys.useProxy] integerValue]];
            [[self useProxyCheckBox] setEnabled:NO];
            [[self proxyHostField] setEnabled:NO];
            [[self proxyPortField] setEnabled:NO];
            [[self SIPAddressField] setEnabled:NO];
            [[self registrarField] setEnabled:NO];
            [[self cantEditAccountLabel] setHidden:NO];
            [[self UDPButton] setEnabled:NO];
            [[self TCPButton] setEnabled:NO];
            [[self TLSButton] setEnabled:NO];
            [[self IPv4Button] setEnabled:NO];
            [[self IPv6Button] setEnabled:NO];
            [[self updateIPAddressCheckBox] setEnabled:NO];

        } else {
            [[self accountEnabledCheckBox] setState:NSControlStateValueOff];
            [[self accountDescriptionField] setEnabled:YES];
            [[self fullNameField] setEnabled:YES];
            [[self domainField] setEnabled:YES];
            [[self usernameField] setEnabled:YES];
            [[self passwordField] setEnabled:YES];
            
            [[self reregistrationTimeField] setEnabled:YES];
            [[self substitutePlusCharacterCheckBox] setEnabled:YES];
            [[self substitutePlusCharacterCheckBox] setState:[accountDict[UserDefaultsKeys.substitutePlusCharacter] integerValue]];
            if ([[self substitutePlusCharacterCheckBox] state] == NSControlStateValueOn) {
                [[self plusCharacterSubstitutionField] setEnabled:YES];
            } else {
                [[self plusCharacterSubstitutionField] setEnabled:NO];
            }

            [[self useProxyCheckBox] setEnabled:YES];
            [[self useProxyCheckBox] setState:[accountDict[AKSIPAccountKeys.useProxy] integerValue]];
            if ([[self useProxyCheckBox] state] == NSControlStateValueOn) {
                [[self proxyHostField] setEnabled:YES];
                [[self proxyPortField] setEnabled:YES];
            } else {
                [[self proxyHostField] setEnabled:NO];
                [[self proxyPortField] setEnabled:NO];
            }
            
            [[self SIPAddressField] setEnabled:YES];
            [[self registrarField] setEnabled:YES];
            [[self cantEditAccountLabel] setHidden:YES];
            [[self UDPButton] setEnabled:YES];
            [[self TCPButton] setEnabled:YES];
            [[self TLSButton] setEnabled:YES];
            [[self IPv4Button] setEnabled:YES];
            [[self IPv6Button] setEnabled:YES];
            [[self updateIPAddressCheckBox] setEnabled:YES];
        }
        
        // Populate fields.
        
        // Description.
        if ([accountDict[AKSIPAccountKeys.desc] length] > 0) {
            [[self accountDescriptionField] setStringValue:accountDict[AKSIPAccountKeys.desc]];
        } else {
            [[self accountDescriptionField] setStringValue:@""];
        }
        
        // Description's placeholder string.
        if ([accountDict[AKSIPAccountKeys.sipAddress] length] > 0) {
            [[self accountDescriptionField] setPlaceholderString:accountDict[AKSIPAccountKeys.sipAddress]];
        } else {
            [[self accountDescriptionField] setPlaceholderString:
             [[SIPAddress alloc] initWithUser:accountDict[AKSIPAccountKeys.username]
                                         host:accountDict[AKSIPAccountKeys.domain]].stringValue];
        }
        
        // Full Name.
        [[self fullNameField] setStringValue:accountDict[AKSIPAccountKeys.fullName]];
        
        // Domain.
        if ([accountDict[AKSIPAccountKeys.domain] length] > 0) {
            [[self domainField] setStringValue:accountDict[AKSIPAccountKeys.domain]];
        } else {
            [[self domainField] setStringValue:@""];
        }
        
        // User Name.
        [[self usernameField] setStringValue:accountDict[AKSIPAccountKeys.username]];
        
        // The shared broker supplies the password after all identity fields are populated.
        self.passwordField.stringValue = @"";

        // Reregister every...
        if ([accountDict[AKSIPAccountKeys.reregistrationTime] integerValue] > 0) {
            [[self reregistrationTimeField] setStringValue:[accountDict[AKSIPAccountKeys.reregistrationTime] stringValue]];
        } else {
            [[self reregistrationTimeField] setStringValue:@""];
        }
        
        // Substitute ... for "+".
        if (accountDict[UserDefaultsKeys.plusCharacterSubstitutionString] != nil) {
            [[self plusCharacterSubstitutionField] setStringValue:
             accountDict[UserDefaultsKeys.plusCharacterSubstitutionString]];
        } else {
            [[self plusCharacterSubstitutionField] setStringValue:@"00"];
        }
        
        // Proxy Server.
        if ([accountDict[AKSIPAccountKeys.proxyHost] length] > 0) {
            [[self proxyHostField] setStringValue:accountDict[AKSIPAccountKeys.proxyHost]];
        } else {
            [[self proxyHostField] setStringValue:@""];
        }
        
        // Proxy Port.
        if ([accountDict[AKSIPAccountKeys.proxyPort] integerValue] > 0) {
            [[self proxyPortField] setStringValue:[accountDict[AKSIPAccountKeys.proxyPort] stringValue]];
        } else {
            [[self proxyPortField] setStringValue:@""];
        }
        
        // SIP Address.
        if ([accountDict[AKSIPAccountKeys.sipAddress] length] > 0) {
            [[self SIPAddressField] setStringValue:accountDict[AKSIPAccountKeys.sipAddress]];
        } else {
            [[self SIPAddressField] setStringValue:@""];
        }
        
        // Registry Server.
        if ([accountDict[AKSIPAccountKeys.registrar] length] > 0) {
            [[self registrarField] setStringValue:accountDict[AKSIPAccountKeys.registrar]];
        } else {
            [[self registrarField] setStringValue:@""];
        }
        
        // SIP Address and Registry Server placeholder strings.
        if ([accountDict[AKSIPAccountKeys.domain] length] > 0) {
            [[self SIPAddressField] setPlaceholderString:
             [[SIPAddress alloc] initWithUser:accountDict[AKSIPAccountKeys.username]
                                         host:accountDict[AKSIPAccountKeys.domain]].stringValue];
            [[self registrarField] setPlaceholderString:accountDict[AKSIPAccountKeys.domain]];
        } else {
            [[self SIPAddressField] setPlaceholderString:nil];
            [[self registrarField] setPlaceholderString:nil];
        }

        // Update SIP Transport.
        if ([accountDict[AKSIPAccountKeys.transport] isEqualToString:AKSIPAccountKeys.transportTCP]) {
            [[self TCPButton] setState:NSControlStateValueOn];
        } else if ([accountDict[AKSIPAccountKeys.transport] isEqualToString:AKSIPAccountKeys.transportTLS]) {
            [[self TLSButton] setState:NSControlStateValueOn];
        } else {
            [[self UDPButton] setState:NSControlStateValueOn];
        }
        [self updateProxyPortFieldPlaceholder];

        // Update IP Version.
        if ([accountDict[AKSIPAccountKeys.ipVersion] isEqualToString:AKSIPAccountKeys.ipVersion6]) {
            [[self IPv6Button] setState:NSControlStateValueOn];
        } else {
            [[self IPv4Button] setState:NSControlStateValueOn];
        }
        
        // Update headers checkbox.
        if ([accountDict[AKSIPAccountKeys.updateContactHeader] boolValue] &&
            [accountDict[AKSIPAccountKeys.updateViaHeader] boolValue] &&
            [accountDict[AKSIPAccountKeys.updateSDP] boolValue]) {
            [[self updateIPAddressCheckBox] setAllowsMixedState:NO];
            [[self updateIPAddressCheckBox] setState:NSControlStateValueOn];
        } else if ([accountDict[AKSIPAccountKeys.updateContactHeader] boolValue] ||
                   [accountDict[AKSIPAccountKeys.updateViaHeader] boolValue] ||
                   [accountDict[AKSIPAccountKeys.updateSDP] boolValue]) {
            [[self updateIPAddressCheckBox] setAllowsMixedState:YES];
            [[self updateIPAddressCheckBox] setState:NSControlStateValueMixed];
        } else {
            [[self updateIPAddressCheckBox] setAllowsMixedState:NO];
            [[self updateIPAddressCheckBox] setState:NSControlStateValueOff];
        }
        // The Accounts nib is also loaded merely to measure the Settings
        // layout. The admission helper stages metadata until this pane appears.
        [self loadCredentialForAccount:accountDict];

    } else {  // if (index >= 0)
        [[self accountEnabledCheckBox] setState:NSControlStateValueOff];
        [[self accountDescriptionField] setStringValue:@""];
        [[self accountDescriptionField] setPlaceholderString:nil];
        [[self fullNameField] setStringValue:@""];
        [[self domainField] setStringValue:@""];
        [[self usernameField] setStringValue:@""];
        [[self passwordField] setStringValue:@""];
        [[self reregistrationTimeField] setStringValue:@""];
        [[self substitutePlusCharacterCheckBox] setState:NSControlStateValueOff];
        [[self plusCharacterSubstitutionField] setStringValue:@"00"];
        [[self useProxyCheckBox] setState:NSControlStateValueOff];
        [[self proxyHostField] setStringValue:@""];
        [[self proxyPortField] setStringValue:@""];
        [[self SIPAddressField] setStringValue:@""];
        [[self registrarField] setStringValue:@""];
        [[self UDPButton] setState:NSControlStateValueOff];
        [[self TCPButton] setState:NSControlStateValueOff];
        [[self TLSButton] setState:NSControlStateValueOff];
        [[self IPv4Button] setState:NSControlStateValueOff];
        [[self IPv6Button] setState:NSControlStateValueOff];
        [[self updateIPAddressCheckBox] setState:NSControlStateValueOff];

        [[self accountEnabledCheckBox] setEnabled:NO];
        [[self accountDescriptionField] setEnabled:NO];
        [[self fullNameField] setEnabled:NO];
        [[self domainField] setEnabled:NO];
        [[self usernameField] setEnabled:NO];
        [[self passwordField] setEnabled:NO];
        [[self reregistrationTimeField] setEnabled:NO];
        [[self substitutePlusCharacterCheckBox] setEnabled:NO];
        [[self plusCharacterSubstitutionField] setEnabled:NO];
        [[self useProxyCheckBox] setEnabled:NO];
        [[self proxyHostField] setEnabled:NO];
        [[self proxyPortField] setEnabled:NO];
        [[self SIPAddressField] setEnabled:NO];
        [[self SIPAddressField] setPlaceholderString:nil];
        [[self registrarField] setEnabled:NO];
        [[self registrarField] setPlaceholderString:nil];
        [[self cantEditAccountLabel] setHidden:YES];
        [[self UDPButton] setEnabled:NO];
        [[self TCPButton] setEnabled:NO];
        [[self TLSButton] setEnabled:NO];
        [[self IPv4Button] setEnabled:NO];
        [[self IPv6Button] setEnabled:NO];
        [[self updateIPAddressCheckBox] setEnabled:NO];
    }
}

- (void)presentAccountEditError:(NSString *)message field:(NSTextField *)field {
    self.accountEnabledCheckBox.state = NSControlStateValueOff;
    field.accessibilityHelp = message;
    [self.view.window makeFirstResponder:field];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Account could not be enabled", @"Account edit validation error.");
    alert.informativeText = message;
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"Dismiss error.")];
    [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
}

- (IBAction)changeAccountEnabled:(id)sender {
    NSInteger index = [[self accountsTable] selectedRow];
    if (index < 0) return;

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    
    userInfo[kAccountIndex] = @(index);
    
    NSUserDefaults *defaults = [self accountDefaults];
    
    NSMutableArray *savedAccounts = [NSMutableArray arrayWithArray:[defaults arrayForKey:UserDefaultsKeys.accounts]];
    
    if ((NSUInteger)index >= savedAccounts.count) return;
    NSMutableDictionary *accountDict = [NSMutableDictionary dictionaryWithDictionary:savedAccounts[index]];
    if (!self.credentialPresentationActive) {
        self.accountEnabledCheckBox.state = [accountDict[UserDefaultsKeys.accountEnabled] boolValue]
            ? NSControlStateValueOn : NSControlStateValueOff;
        return;
    }
    
    BOOL isChecked = [[self accountEnabledCheckBox] state] == NSControlStateValueOn;
    accountDict[UserDefaultsKeys.accountEnabled] = @(isChecked);
    
    if (isChecked) {
        // User enabled the account.
        // Account fields could be edited, save them.
        
        NSCharacterSet *spacesSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSString *accountDescription = [[[self accountDescriptionField] stringValue]
                                        stringByTrimmingCharactersInSet:spacesSet];
        NSString *fullName = [[[self fullNameField] stringValue] stringByTrimmingCharactersInSet:spacesSet];
        NSString *domain = [[[self domainField] stringValue] stringByTrimmingCharactersInSet:spacesSet];
        NSString *username = [[[self usernameField] stringValue] stringByTrimmingCharactersInSet:spacesSet];
        NSString *registrar = [[[self registrarField] stringValue] stringByTrimmingCharactersInSet:spacesSet];
        
        NSString *sipAddress = [self.SIPAddressField.stringValue stringByTrimmingCharactersInSet:spacesSet];
        // An explicit address and registrar support accounts with no default domain.
        if (username.length == 0 || (domain.length == 0 && (sipAddress.length == 0 || registrar.length == 0))) {
            NSTextField *field = username.length == 0 ? self.usernameField : self.domainField;
            [self presentAccountEditError:username.length == 0
                ? NSLocalizedString(@"Enter a username before enabling this account.", @"Account username required.")
                : NSLocalizedString(@"Enter a domain, or provide both a SIP address and registrar.", @"Account domain or overrides required.") field:field];
            return;
        }

        accountDict[AKSIPAccountKeys.desc] = accountDescription;
        accountDict[AKSIPAccountKeys.fullName] = fullName;
        accountDict[AKSIPAccountKeys.domain] = domain;
        accountDict[AKSIPAccountKeys.username] = username;
        
        NSString *keychainService;
        if ([registrar length] > 0) {
            keychainService = [NSString stringWithFormat:@"SIP: %@", registrar];
        } else {
            keychainService = [NSString stringWithFormat:@"SIP: %@", domain];
        }
        
        NSString *keychainAccount = username;
        NSString *currentPassword = self.passwordField.stringValue;
        BOOL passwordEdited = self.credentialPasswordWasEdited ||
            (self.loadedCredentialPassword != nil && ![currentPassword isEqualToString:self.loadedCredentialPassword]);
        if (![self selectedAccountMatchesCredentialSnapshot]) {
            [self presentAccountEditError:NSLocalizedString(@"This account changed while it was being edited. Select it again before enabling it.", @"Stale account settings.") field:self.usernameField];
            return;
        }
        BOOL sameCredential = [keychainService isEqualToString:self.credentialService] &&
            [keychainAccount isEqualToString:self.credentialUsername];
        if (self.credentialRequiresReplacement && !passwordEdited) {
            [self presentAccountEditError:NSLocalizedString(@"Enter the replacement password again before enabling this account.", @"Discarded unsaved credential help.") field:self.passwordField];
            return;
        }
        if (!sameCredential && !passwordEdited) {
            [self presentAccountEditError:NSLocalizedString(@"The credential destination changed. Enter a password before enabling this account.", @"Changed account credential identity.") field:self.passwordField];
            return;
        }
        if (!passwordEdited && (self.credentialReadPending || self.credentialReadStatus != AKCredentialReadStatusSuccess)) {
            if (self.credentialReadPending || self.credentialReadStatus == AKCredentialReadStatusMissing) {
                NSString *help = self.credentialReadPending
                    ? NSLocalizedString(@"Wait for the password lookup to finish before enabling this account.", @"Pending credential enablement.")
                    : [self credentialReadHelpForStatus:self.credentialReadStatus];
                [self presentAccountEditError:help field:self.passwordField];
            } else {
                // Enabling is a deliberate retry. It requests access again but
                // never treats cancellation/denial as an empty password.
                self.accountEnabledCheckBox.state = NSControlStateValueOff;
                [[self credentialBroker] invalidateService:keychainService account:keychainAccount];
                self.credentialRetryAwaitingEnable = YES;
                [self loadCredentialForAccount:savedAccounts[(NSUInteger)index]];
                self.accountEnabledCheckBox.accessibilityHelp = NSLocalizedString(@"Password access is being requested. Enable the account again after it finishes, or enter a replacement password.", @"Explicit credential retry help.");
                self.accountEnabledCheckBox.toolTip = self.accountEnabledCheckBox.accessibilityHelp;
            }
            return;
        }
        // The admitted snapshot is sufficient for an unchanged save. No second
        // Keychain read is made merely to compare the form with stored data.
        if (passwordEdited) {
            NSError *saveError;
            if (![self savePassword:currentPassword service:keychainService account:keychainAccount error:&saveError]) {
                [self presentAccountEditError:[NSString stringWithFormat:NSLocalizedString(@"Password could not be saved. %@", @"Credential save failure."), saveError.localizedDescription]
                                        field:self.passwordField];
                return;
            }
            [[self credentialBroker] invalidateService:keychainService account:keychainAccount];
        }
        
        accountDict[AKSIPAccountKeys.reregistrationTime] = @([[self reregistrationTimeField] integerValue]);
        
        accountDict[UserDefaultsKeys.substitutePlusCharacter] = @([[self substitutePlusCharacterCheckBox] state] == NSControlStateValueOn);
        accountDict[UserDefaultsKeys.plusCharacterSubstitutionString] = [[self plusCharacterSubstitutionField] stringValue];
        
        accountDict[AKSIPAccountKeys.useProxy] = @([[self useProxyCheckBox] state] == NSControlStateValueOn);
        NSString *proxyHost = [[[self proxyHostField] stringValue] stringByTrimmingCharactersInSet:spacesSet];
        accountDict[AKSIPAccountKeys.proxyHost] = proxyHost;
        accountDict[AKSIPAccountKeys.proxyPort] = @([[self proxyPortField] integerValue]);
        
        accountDict[AKSIPAccountKeys.sipAddress] = sipAddress;
        
        accountDict[AKSIPAccountKeys.registrar] = registrar;

        if (self.TCPButton.state == NSControlStateValueOn) {
            accountDict[AKSIPAccountKeys.transport] = AKSIPAccountKeys.transportTCP;
        } else if (self.TLSButton.state == NSControlStateValueOn) {
            accountDict[AKSIPAccountKeys.transport] = AKSIPAccountKeys.transportTLS;
        } else {
            accountDict[AKSIPAccountKeys.transport] = AKSIPAccountKeys.transportUDP;
        }

        accountDict[AKSIPAccountKeys.ipVersion] = self.IPv6Button.state == NSControlStateValueOn ? AKSIPAccountKeys.ipVersion6 : AKSIPAccountKeys.ipVersion4;

        if (self.updateIPAddressCheckBox.state == NSControlStateValueOn) {
            accountDict[AKSIPAccountKeys.updateContactHeader] = @YES;
            accountDict[AKSIPAccountKeys.updateViaHeader] = @YES;
            accountDict[AKSIPAccountKeys.updateSDP] = @YES;
        } else if (self.updateIPAddressCheckBox.state == NSControlStateValueMixed) {
            accountDict[AKSIPAccountKeys.updateContactHeader] = @YES;
            accountDict[AKSIPAccountKeys.updateViaHeader] = @YES;
            accountDict[AKSIPAccountKeys.updateSDP] = @NO;
        } else {
            accountDict[AKSIPAccountKeys.updateContactHeader] = @NO;
            accountDict[AKSIPAccountKeys.updateViaHeader] = @NO;
            accountDict[AKSIPAccountKeys.updateSDP] = @NO;
        }

        // Set placeholders.
        
        if ([sipAddress length] > 0) {
            [[self accountDescriptionField] setPlaceholderString:sipAddress];
        } else {
            [[self accountDescriptionField] setPlaceholderString:
             [[SIPAddress alloc] initWithUser:username host:domain].stringValue];
        }
        
        if ([domain length] > 0) {
            [[self SIPAddressField] setPlaceholderString:[[SIPAddress alloc] initWithUser:username host:domain].stringValue];

            [[self registrarField] setPlaceholderString:domain];
            
        } else {
            [[self SIPAddressField] setPlaceholderString:nil];
            [[self registrarField] setPlaceholderString:nil];
        }
        
        // Disable account fields.
        [[self accountDescriptionField] setEnabled:NO];
        [[self fullNameField] setEnabled:NO];
        [[self domainField] setEnabled:NO];
        [[self usernameField] setEnabled:NO];
        [[self passwordField] setEnabled:NO];
        
        [[self reregistrationTimeField] setEnabled:NO];
        [[self substitutePlusCharacterCheckBox] setEnabled:NO];
        [[self plusCharacterSubstitutionField] setEnabled:NO];
        [[self useProxyCheckBox] setEnabled:NO];
        [[self proxyHostField] setEnabled:NO];
        [[self proxyPortField] setEnabled:NO];
        [[self SIPAddressField] setEnabled:NO];
        [[self registrarField] setEnabled:NO];
        [[self cantEditAccountLabel] setHidden:NO];
        [[self UDPButton] setEnabled:NO];
        [[self TCPButton] setEnabled:NO];
        [[self TLSButton] setEnabled:NO];
        [[self IPv4Button] setEnabled:NO];
        [[self IPv6Button] setEnabled:NO];
        [[self updateIPAddressCheckBox] setEnabled:NO];

        // Mark accounts table as needing redisplay.
        [[self accountsTable] reloadData];
        
    } else {  // if (isChecked)
        // User disabled the account - enable account fields, set checkboxes state.
        [[self accountDescriptionField] setEnabled:YES];
        [[self fullNameField] setEnabled:YES];
        [[self domainField] setEnabled:YES];
        [[self usernameField] setEnabled:YES];
        [[self passwordField] setEnabled:YES];
        
        [[self reregistrationTimeField] setEnabled:YES];
        [[self substitutePlusCharacterCheckBox] setEnabled:YES];
        [[self substitutePlusCharacterCheckBox] setState:[accountDict[UserDefaultsKeys.substitutePlusCharacter] integerValue]];
        if ([[self substitutePlusCharacterCheckBox] state] == NSControlStateValueOn) {
            [[self plusCharacterSubstitutionField] setEnabled:YES];
        }
        
        [[self useProxyCheckBox] setEnabled:YES];
        [[self useProxyCheckBox] setState:[accountDict[AKSIPAccountKeys.useProxy] integerValue]];
        if ([[self useProxyCheckBox] state] == NSControlStateValueOn) {
            [[self proxyHostField] setEnabled:YES];
            [[self proxyPortField] setEnabled:YES];
        }
        
        [[self SIPAddressField] setEnabled:YES];
        [[self registrarField] setEnabled:YES];
        [[self cantEditAccountLabel] setHidden:YES];
        [[self UDPButton] setEnabled:YES];
        [[self TCPButton] setEnabled:YES];
        [[self TLSButton] setEnabled:YES];
        [[self IPv4Button] setEnabled:YES];
        [[self IPv6Button] setEnabled:YES];
        [[self updateIPAddressCheckBox] setEnabled:YES];
    }
    
    savedAccounts[index] = accountDict;
    
    [defaults setObject:savedAccounts forKey:UserDefaultsKeys.accounts];
    self.credentialGeneration++;
    self.credentialReadPending = NO;
    self.credentialAccountSnapshot = [accountDict copy];
    self.credentialService = [self credentialServiceForAccount:accountDict];
    self.credentialUsername = accountDict[AKSIPAccountKeys.username] ?: @"";
    if (isChecked) {
        self.loadedCredentialPassword = self.passwordField.stringValue;
        self.credentialReadStatus = AKCredentialReadStatusSuccess;
        self.credentialPasswordWasEdited = NO;
        self.credentialRequiresReplacement = NO;
        self.credentialRetryAwaitingEnable = NO;
        self.passwordField.accessibilityHelp = nil;
        self.passwordField.toolTip = nil;
        self.accountEnabledCheckBox.accessibilityHelp = nil;
        self.accountEnabledCheckBox.toolTip = nil;
    }
    
    [[NSNotificationCenter defaultCenter]
     postNotificationName:AKPreferencesControllerDidChangeAccountEnabledNotification
                   object:[self preferencesController]
                 userInfo:userInfo];
}

- (IBAction)changeSubstitutePlusCharacter:(id)sender {
    [[self plusCharacterSubstitutionField] setEnabled:([[self substitutePlusCharacterCheckBox] state] == NSControlStateValueOn)];
}

- (IBAction)changeUseProxy:(id)sender {
    BOOL isChecked = [[self useProxyCheckBox] state] == NSControlStateValueOn;
    [[self proxyHostField] setEnabled:isChecked];
    [[self proxyPortField] setEnabled:isChecked];
}

- (IBAction)changeTransport:(id)sender {
    [self updateProxyPortFieldPlaceholder];
}

- (void)updateProxyPortFieldPlaceholder {
    self.proxyPortField.placeholderString = self.TLSButton.state == NSControlStateValueOn ? @"5061" : @"5060";
}

// Group radio buttons by providing them the same action.
- (IBAction)changeIPVersion:(id)sender {}


#pragma mark -
#pragma mark NSTableView data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    NSUserDefaults *defaults = [self accountDefaults];
    return [[defaults arrayForKey:UserDefaultsKeys.accounts] count];
}

- (id)tableView:(NSTableView *)aTableView
        objectValueForTableColumn:(NSTableColumn *)aTableColumn
        row:(NSInteger)rowIndex {
    
    NSUserDefaults *defaults = [self accountDefaults];
    
    NSDictionary *accountDict = [defaults arrayForKey:UserDefaultsKeys.accounts][rowIndex];
    
    NSString *returnValue;
    NSString *accountDescription = accountDict[AKSIPAccountKeys.desc];
    if ([accountDescription length] > 0) {
        returnValue = accountDescription;
        
    } else {
        NSString *sipAddress;
        if ([accountDict[AKSIPAccountKeys.sipAddress] length] > 0) {
            sipAddress = accountDict[AKSIPAccountKeys.sipAddress];
        } else {
            sipAddress = [[SIPAddress alloc] initWithUser:accountDict[AKSIPAccountKeys.username]
                                                     host:accountDict[AKSIPAccountKeys.domain]].stringValue;
        }
        
        returnValue = sipAddress;
    }
    
    return returnValue;
}

- (BOOL)tableView:(NSTableView *)aTableView
        writeRowsWithIndexes:(NSIndexSet *)rowIndexes
        toPasteboard:(NSPasteboard *)pboard {
    
    NSError *error;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes requiringSecureCoding:YES error:&error];
    if (data == nil) {
        NSLog(@"Could not archive row indexes while dragging: %@", error);
        return NO;
    }
    [pboard declareTypes:@[kAKSIPAccountPboardType] owner:self];
    [pboard setData:data forType:kAKSIPAccountPboardType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView
                validateDrop:(id <NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    
    NSData *data = [[info draggingPasteboard] dataForType:kAKSIPAccountPboardType];
    NSError *error;
    NSIndexSet *indexes = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSIndexSet class] fromData:data error:&error];
    if (indexes == nil) {
        NSLog(@"Could not unarchive row indexes while dragging: %@", error);
        return NSDragOperationNone;
    }
    NSInteger draggingRow = [indexes firstIndex];
    if (row == draggingRow || row == draggingRow + 1) {
        return NSDragOperationNone;
    }
    [[self accountsTable] setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    
    NSData *data = [[info draggingPasteboard] dataForType:kAKSIPAccountPboardType];
    NSError *error;
    NSIndexSet *indexes = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSIndexSet class] fromData:data error:&error];
    if (indexes == nil) {
        NSLog(@"Could not unarchive row indexes while dragging: %@", error);
        return NO;
    }
    NSInteger draggingRow = [indexes firstIndex];
    
    NSUserDefaults *defaults = [self accountDefaults];
    NSMutableArray *accounts = [[defaults arrayForKey:UserDefaultsKeys.accounts] mutableCopy];
    id selectedAccount = accounts[[[self accountsTable] selectedRow]];
    
    // Swap accounts.
    [accounts insertObject:accounts[draggingRow] atIndex:row];
    if (draggingRow < row) {
        [accounts removeObjectAtIndex:draggingRow];
    } else if (draggingRow > row) {
        [accounts removeObjectAtIndex:(draggingRow + 1)];
    } else {  // This should never happen because we don't validate such drop.
        return NO;
    }
    
    [defaults setObject:accounts forKey:UserDefaultsKeys.accounts];
    
    [[self accountsTable] reloadData];
    
    // Preserve account selection.
    NSUInteger selectedAccountIndex = [accounts indexOfObject:selectedAccount];
    [[self accountsTable] selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedAccountIndex] byExtendingSelection:NO];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:AKPreferencesControllerDidSwapAccountsNotification
                                                        object:[self preferencesController]
                                                      userInfo:@{kSourceIndex: @(draggingRow), kDestinationIndex: @(row)}];
    
    return YES;
}


#pragma mark -
#pragma mark NSTableView delegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    NSInteger row = [[self accountsTable] selectedRow];
    [self populateFieldsForAccountAtIndex:row];
}


#pragma mark -
#pragma mark AccountSetupController notifications

- (void)accountSetupControllerDidAddAccount:(NSNotification *)notification {
    [[self accountsTable] reloadData];
    
    // Select the newly added account.
    NSUserDefaults *defaults = [self accountDefaults];
    NSUInteger accountsCount = [[defaults arrayForKey:UserDefaultsKeys.accounts] count];
    NSUInteger index = accountsCount - 1;
    if (index != 0) {
        [[self accountsTable] selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    }
    
    if (accountsCount >= kAccountsMax) {
        [[self addAccountButton] setEnabled:NO];
    }
}

@end
