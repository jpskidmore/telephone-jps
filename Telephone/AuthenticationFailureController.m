//
//  AuthenticationFailureController.m
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

#import "AuthenticationFailureController.h"

#import "AKSIPUserAgent.h"
#import "AKKeychain.h"

#import "AccountController.h"
#import "AppController.h"
#import "SIPResponseLocalization.h"


NSString * const AKAuthenticationFailureControllerDidChangeUsernameAndPasswordNotification
    = @"AKAuthenticationFailureControllerDidChangeUsernameAndPassword";

@interface AuthenticationFailureController ()
@property(nonatomic) BOOL retryPending;
@end

@implementation AuthenticationFailureController

- (BOOL)savePassword:(NSString *)password service:(NSString *)service account:(NSString *)account error:(NSError **)error {
    return [AKKeychain addItemWithService:service account:account password:password error:error];
}


- (instancetype)initWithAccountController:(AccountController *)accountController userAgent:(AKSIPUserAgent *)userAgent {
    self = [super initWithWindowNibName:@"AuthenticationFailure"];
    if (self != nil) {
        _accountController = accountController;
        _userAgent = userAgent;
    }
    return self;
}

- (void)awakeFromNib {
    [[self  informativeText] setStringValue:
     [NSString stringWithFormat:
      NSLocalizedString(@"Telephone was unable to login to %@. Change user name or password and try again.",
                        @"Registrar authentication failed."), self.accountController.account.registrar]];
    
    NSString *username = [[[self accountController] account] username];
    NSString *service = [NSString stringWithFormat:@"SIP: %@", [[[self accountController] account] registrar]];
    NSString *password = [AKKeychain passwordForService:service account:username];
    
    [[self usernameField] setStringValue:username];
    [[self passwordField] setStringValue:password];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.usernameField.cell.accessibilityLabel = NSLocalizedString(@"Username", @"Accessible account field purpose.");
    self.passwordField.cell.accessibilityLabel = NSLocalizedString(@"Password", @"Accessible account field purpose.");
}

- (IBAction)closeSheet:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

- (void)presentCredentialError:(NSString *)message field:(NSTextField *)field {
    self.informativeText.stringValue = message;
    field.accessibilityHelp = message;
    [self.window makeFirstResponder:field];
    NSAccessibilityPostNotification(field, NSAccessibilityValueChangedNotification);
}

- (IBAction)changeUsernameAndPassword:(id)sender {
    if (self.retryPending) return;
    
    NSCharacterSet *spacesSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *username = [[[self usernameField] stringValue] stringByTrimmingCharactersInSet:spacesSet];
    
    if (username.length == 0) {
        [self presentCredentialError:NSLocalizedString(@"Enter your username before trying again.", @"Authentication username required.")
                              field:self.usernameField];
        return;
    }

    if (self.mustSaveCheckBox.state == NSControlStateValueOn) {
        NSError *saveError;
        NSString *service = [NSString stringWithFormat:@"SIP: %@", self.accountController.account.registrar];
        if (![self savePassword:self.passwordField.stringValue service:service account:username error:&saveError]) {
            [self presentCredentialError:[NSString stringWithFormat:NSLocalizedString(@"Password could not be saved. %@", @"Credential save failure."), saveError.localizedDescription]
                                  field:self.passwordField];
            return;
        }
    }
    AccountController *controller = self.accountController;
    AKSIPAccount *account = controller.account;
    NSString *password = self.passwordField.stringValue;
    self.retryPending = YES;
    [controller removeAccountFromUserAgentWithCompletion:^(BOOL removed) {
        if (!controller.isEnabled || controller.account != account || !account.desiredRegistered) {
            self.retryPending = NO;
            return;
        }
        if (!removed) {
            self.retryPending = NO;
            [self presentCredentialError:NSLocalizedString(@"Could not reset this account. Try again.", @"Authentication account removal failure.") field:self.usernameField];
            return;
        }
        [account updateUsername:username];
        [controller showConnectingState];
        [self.userAgent addAccount:account withPassword:password completion:^(BOOL added) {
            self.retryPending = NO;
            if (!controller.isEnabled || controller.account != account || !account.desiredRegistered) {
                if (added) [self.userAgent removeAccount:account completion:^(BOOL removedAgain) {}];
                return;
            }
            if (!added) {
                [controller showUnavailableState];
                [self presentCredentialError:NSLocalizedString(@"Could not reconnect this account. Try again.", @"Authentication account add failure.") field:self.usernameField];
                return;
            }
            // Registration success/failure arrives through the account delegate;
            // a cached pre-REGISTER snapshot cannot decide the retry result.
            [self closeSheet:sender];
            self.passwordField.stringValue = @"";
            [[NSNotificationCenter defaultCenter] postNotificationName:AKAuthenticationFailureControllerDidChangeUsernameAndPasswordNotification object:self];
        }];
    }];
}

@end
