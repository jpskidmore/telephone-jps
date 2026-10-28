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
@property(nonatomic) NSUInteger retryGeneration;
@property(nonatomic, copy) NSString *preparedUsername;
@property(nonatomic, copy) NSString *preparedPassword;
@property(nonatomic, weak) AKSIPAccount *presentedAccount;
@property(nonatomic) NSUInteger presentedCredentialGeneration;
@property(nonatomic) BOOL credentialSessionActive;
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
        _presentedAccount = accountController.account;
        _presentedCredentialGeneration = accountController.credentialAccessGeneration;
        _credentialSessionActive = accountController != nil && accountController.account != nil;
    }
    return self;
}

- (void)awakeFromNib {
    [[self  informativeText] setStringValue:
     [NSString stringWithFormat:
      NSLocalizedString(@"Telephone was unable to login to %@. Change user name or password and try again.",
                        @"Registrar authentication failed."), self.accountController.account.registrar]];
    
    self.usernameField.stringValue = self.preparedUsername ?: self.accountController.account.username ?: @"";
    self.passwordField.stringValue = self.preparedPassword ?: @"";
    self.preparedPassword = nil;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.usernameField.cell.accessibilityLabel = NSLocalizedString(@"Username", @"Accessible account field purpose.");
    self.passwordField.cell.accessibilityLabel = NSLocalizedString(@"Password", @"Accessible account field purpose.");
}

- (void)prepareWithUsername:(NSString *)username password:(NSString *)password {
    self.retryGeneration++;
    self.retryPending = NO;
    self.presentedAccount = self.accountController.account;
    self.presentedCredentialGeneration = self.accountController.credentialAccessGeneration;
    self.credentialSessionActive = self.presentedAccount != nil;
    self.preparedUsername = username;
    self.preparedPassword = password;
    (void)self.window;
    self.usernameField.stringValue = username;
    self.passwordField.stringValue = password ?: @"";
    self.preparedPassword = nil;
    self.informativeText.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Telephone was unable to login to %@. Change user name or password and try again.", @"Registrar authentication failed."), self.accountController.account.registrar];
}

- (void)clearCredentialPresentation {
    self.credentialSessionActive = NO;
    self.preparedPassword = nil;
    self.passwordField.stringValue = @"";
}

- (IBAction)closeSheet:(id)sender {
    self.retryGeneration++;
    self.retryPending = NO;
    [self clearCredentialPresentation];
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
    AccountController *owner = self.accountController;
    if (!self.credentialSessionActive || !owner.isEnabled || owner.credentialAccessSuspended ||
        owner.account != self.presentedAccount || owner.credentialAccessGeneration != self.presentedCredentialGeneration) {
        [self presentCredentialError:NSLocalizedString(@"This account changed or is no longer available. Choose Online and try again from the current account.", @"Obsolete authentication form.") field:self.usernameField];
        return;
    }
    
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
    NSUInteger retryGeneration = ++self.retryGeneration;
    // Removal advances the account credential generation exactly once before its completion.
    NSUInteger credentialGeneration = controller.credentialAccessGeneration + 1;
    [controller removeAccountFromUserAgentWithCompletion:^(BOOL removed) {
        if (self.retryGeneration != retryGeneration) return;
        if (controller.credentialAccessGeneration != credentialGeneration || controller.credentialAccessSuspended || !controller.isEnabled || controller.account != account || !account.desiredRegistered) {
            self.retryPending = NO;
            return;
        }
        if (!removed) {
            self.retryPending = NO;
            self.credentialSessionActive = YES;
            self.presentedCredentialGeneration = credentialGeneration;
            self.passwordField.stringValue = password;
            [self presentCredentialError:NSLocalizedString(@"Could not reset this account. Try again.", @"Authentication account removal failure.") field:self.usernameField];
            return;
        }
        [account updateUsername:username];
        [controller showConnectingState];
        [self.userAgent addAccount:account withPassword:password completion:^(BOOL added) {
            BOOL obsoletePresentation = self.retryGeneration != retryGeneration;
            BOOL obsoleteOwner = controller.credentialAccessGeneration != credentialGeneration || controller.credentialAccessSuspended || !controller.isEnabled || controller.account != account || !account.desiredRegistered;
            if (obsoletePresentation || obsoleteOwner) {
                // A newer retry of this same account owns its removal/admission.
                // A delayed BOOL callback cannot identify a newer native account.
                BOOL newerOwner = controller.account == account && controller.isEnabled && !controller.credentialAccessSuspended &&
                    account.desiredRegistered && (controller.credentialAccessGeneration != credentialGeneration || self.retryPending);
                if (added && !newerOwner) [self.userAgent removeAccount:account completion:^(BOOL removedAgain) {}];
                if (!obsoletePresentation) self.retryPending = NO;
                return;
            }
            self.retryPending = NO;
            if (!added) {
                [controller showUnavailableState];
                self.credentialSessionActive = YES;
                self.presentedCredentialGeneration = credentialGeneration;
                self.passwordField.stringValue = password;
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
