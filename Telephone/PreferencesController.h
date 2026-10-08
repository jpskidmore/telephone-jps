//
//  PreferencesController.h
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

#import <Cocoa/Cocoa.h>

#import "PreferencesControllerDelegate.h"
#import "PreferencesControllerNotifications.h"
#import "SoundIOPreferences.h"

@class SoundPreferencesViewEventTarget;

NS_ASSUME_NONNULL_BEGIN

@class AKSIPUserAgent;
@class GeneralPreferencesViewController, AccountPreferencesViewController;
@class SoundPreferencesViewController, NetworkPreferencesViewController;
@class DialPlanStore, DialPlanAccount, DialPlanPreferencesViewController;

// A preferences controller.
@interface PreferencesController : NSWindowController <SoundIOPreferences>

@property(nonatomic, readonly, weak) id<PreferencesControllerDelegate> delegate;
@property(nonatomic, readonly) AKSIPUserAgent *userAgent;
@property(nonatomic, readonly) SoundPreferencesViewEventTarget *soundPreferencesViewEventTarget;

// General preferences view controller.
@property(nonatomic, readonly) GeneralPreferencesViewController *generalPreferencesViewController;

// Account preferences view controller.
@property(nonatomic, readonly) AccountPreferencesViewController *accountPreferencesViewController;

// Sound preferences view controller.
@property(nonatomic, readonly) SoundPreferencesViewController *soundPreferencesViewController;

// Network preferences view controller.
@property(nonatomic, readonly) NetworkPreferencesViewController *networkPreferencesViewController;

// Shared routing settings and live account status, injected by the app coordinator.
@property(nonatomic, strong, nullable) DialPlanStore *dialPlanStore;
@property(nonatomic, copy, nullable) NSArray<DialPlanAccount *> * (^dialPlanAccountProvider)(void);
@property(nonatomic, readonly) DialPlanPreferencesViewController *dialPlanPreferencesViewController;
@property(nonatomic, readonly) NSToolbarItem *dialPlanToolbarItem;

// Outlets.
//
@property(nonatomic, weak) IBOutlet NSToolbar *toolbar;
@property(nonatomic, weak) IBOutlet NSToolbarItem *generalToolbarItem;
@property(nonatomic, weak) IBOutlet NSToolbarItem *accountsToolbarItem;
@property(nonatomic, weak) IBOutlet NSToolbarItem *soundToolbarItem;
@property(nonatomic, weak) IBOutlet NSToolbarItem *networkToolbarItem;

- (instancetype)initWithDelegate:(id<PreferencesControllerDelegate>)delegate
                       userAgent:(AKSIPUserAgent *)userAgent
 soundPreferencesViewEventTarget:(SoundPreferencesViewEventTarget *)soundPreferencesViewEventTarget;

// Changes window's content view.
- (IBAction)changeView:(id)sender;

- (void)showWindowCentered;
- (void)showAccounts;
- (void)showSound;
- (void)showDialPlan;

@end

NS_ASSUME_NONNULL_END
