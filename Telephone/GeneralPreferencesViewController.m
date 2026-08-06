//
//  GeneralPreferencesViewController.m
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

#import "GeneralPreferencesViewController.h"

#import "Telephone-Swift.h"


@interface GeneralPreferencesViewController ()

@property(nonatomic, weak) IBOutlet NSTextField *recordingFolderPathField;
@property(nonatomic, weak) IBOutlet NSPopUpButton *recordingFormatPopUpButton;

- (IBAction)chooseRecordingFolder:(id)sender;
- (IBAction)recordingFormatChanged:(id)sender;

@end


@implementation GeneralPreferencesViewController

- (instancetype)init {
    self = [super initWithNibName:@"GeneralPreferencesView" bundle:nil];
    if (self != nil) {
        [self setTitle:NSLocalizedString(@"General", @"General preferences window title.")];
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.recordingFormatPopUpButton removeAllItems];
    [self.recordingFormatPopUpButton addItemsWithTitles:@[
        NSLocalizedString(@"OGG — smallest files", @"Smallest call recording format option."),
        NSLocalizedString(@"MP3 — good quality", @"Compatible call recording format option."),
        NSLocalizedString(@"Source — no added loss", @"Lossless call recording format option.")
    ]];

    NSString *format = [NSUserDefaults.standardUserDefaults stringForKey:UserDefaultsKeys.recordingFormat];
    NSInteger selectedIndex = [format isEqualToString:@"mp3"] ? 1 : ([format isEqualToString:@"source"] ? 2 : 0);
    [self.recordingFormatPopUpButton selectItemAtIndex:selectedIndex];
    [self updateRecordingFolderDisplay];
}

- (IBAction)chooseRecordingFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = NSLocalizedString(@"Choose Call Recordings Folder", @"Call recording folder picker title.");
    panel.prompt = NSLocalizedString(@"Choose", @"Call recording folder picker confirmation button.");
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.directoryURL = [self recordingFolderURL];

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        NSError *error = nil;
        NSData *bookmark = [panel.URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                               includingResourceValuesForKeys:nil
                                                relativeToURL:nil
                                                        error:&error];
        if (bookmark == nil) {
            NSLog(@"Could not remember the call recordings folder: %@", error);
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = NSLocalizedString(@"The recordings folder could not be saved.", @"Recording folder error title.");
            alert.informativeText = error.localizedDescription ?: @"";
            [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
            return;
        }

        [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:UserDefaultsKeys.recordingFolderBookmark];
        [self updateRecordingFolderDisplay];
    }];
}

- (IBAction)recordingFormatChanged:(id)sender {
    NSInteger index = self.recordingFormatPopUpButton.indexOfSelectedItem;
    NSString *format = index == 1 ? @"mp3" : (index == 2 ? @"source" : @"ogg");
    [NSUserDefaults.standardUserDefaults setObject:format forKey:UserDefaultsKeys.recordingFormat];
}

- (NSURL *)recordingFolderURL {
    NSData *bookmark = [NSUserDefaults.standardUserDefaults dataForKey:UserDefaultsKeys.recordingFolderBookmark];
    if (bookmark != nil) {
        BOOL stale = NO;
        NSError *error = nil;
        NSURL *URL = [NSURL URLByResolvingBookmarkData:bookmark
                                               options:NSURLBookmarkResolutionWithSecurityScope
                                         relativeToURL:nil
                                   bookmarkDataIsStale:&stale
                                                 error:&error];
        if (URL != nil) {
            return URL;
        }
        NSLog(@"Could not resolve the call recordings folder: %@", error);
    }

    NSURL *downloadsURL = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory
                                                               inDomains:NSUserDomainMask].firstObject;
    return [downloadsURL URLByAppendingPathComponent:@"jps Telephone Recordings" isDirectory:YES];
}

- (void)updateRecordingFolderDisplay {
    NSString *path = [self recordingFolderURL].path ?: @"";
    self.recordingFolderPathField.stringValue = path;
    self.recordingFolderPathField.toolTip = path;
}

@end
