#import "RecordingRecoveryController.h"
#import "AKStereoRecording.h"

@interface AKRecoveryOperation : NSObject
@property(nonatomic, copy) NSDictionary *job;
@property(nonatomic, copy) NSString *kind;
@property(nonatomic, copy, nullable) NSURL *destination;
@property(nonatomic) BOOL finished;
@end
@implementation AKRecoveryOperation @end

static void RecoveryOnMain(dispatch_block_t action) {
    if (NSThread.isMainThread) action();
    else dispatch_async(dispatch_get_main_queue(), action);
}

@interface RecordingRecoveryController ()
@property(nonatomic, readwrite) AKRecordingRecoveryIndex *index;
@property(nonatomic, copy) NSArray<NSDictionary *> *displayJobs;
@property(nonatomic, copy, nullable) NSString *presentationSelection;
@property(nonatomic) NSMutableDictionary<NSString *, AKRecoveryOperation *> *operations;
@property(nonatomic) NSMutableDictionary<NSString *, NSString *> *actionErrors;
@property(nonatomic) NSUInteger presentationGeneration;
@property(nonatomic, nullable) NSObject *dialogToken;
@property(nonatomic, nullable) NSSavePanel *savePanel;
@property(nonatomic, nullable) NSAlert *discardAlert;
@property(nonatomic) BOOL updatingSelection;
@property(nonatomic) NSTableView *tableView;
@property(nonatomic) NSTextField *destinationLabel;
@property(nonatomic) NSTextView *errorView;
@property(nonatomic) NSTextField *statusLabel;
@property(nonatomic) NSProgressIndicator *progressIndicator;
@property(nonatomic) NSButton *refreshButton, *retryButton, *saveElsewhereButton, *revealButton, *discardButton;
@end

@implementation RecordingRecoveryController

- (NSUInteger)managedJobCount { return self.displayJobs.count; }

- (instancetype)initWithLoader:(AKRecordingRecoveryLoader)loader {
    // initWithWindow:nil marks NSWindowController as already loaded. A logical
    // nib name preserves its normal lazy lifecycle; loadWindow below supplies
    // the complete programmatic window and never asks AppKit to load a nib.
    if ((self = [super initWithWindowNibName:@"RecordingRecovery"])) {
        _index = [[AKRecordingRecoveryIndex alloc] initWithLoader:loader];
        _operations = [NSMutableDictionary new];
        _actionErrors = [NSMutableDictionary new];
        _displayJobs = @[];
        _actionsEnabled = YES;
        __weak RecordingRecoveryController *weakSelf = self;
        _index.stateDidChange = ^{
            RecordingRecoveryController *controller = weakSelf;
            [controller refreshPresentation];
            if (controller.stateDidChange) controller.stateDidChange();
        };
        _retryHandler = ^(NSDictionary *job, NSURL *destination, void (^completion)(BOOL)) {
            AKRetryRecordingRecoveryJob(job, destination, completion);
        };
        _discardHandler = ^(NSDictionary *job, void (^completion)(BOOL, NSError *)) {
            AKDiscardPendingRecordingRecoveryJobAsync(job, completion);
        };
        _revealHandler = ^(NSURL *directory) {
            [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[directory]];
        };
        _savePanelHandler = ^(NSWindow *window, NSDictionary *job, void (^completion)(NSURL *)) {
            RecordingRecoveryController *controller = weakSelf;
            NSSavePanel *panel = [NSSavePanel savePanel];
            controller.savePanel = panel;
            panel.title = NSLocalizedString(@"Save Recovered Recording", @"Recording recovery save panel title.");
            NSURL *destination = job[@"destinationURL"];
            panel.nameFieldStringValue = destination.lastPathComponent ?: @"Recovered recording.wav";
            panel.directoryURL = destination.URLByDeletingLastPathComponent;
            panel.canCreateDirectories = YES;
            [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
                if (weakSelf.savePanel == panel) weakSelf.savePanel = nil;
                completion(response == NSModalResponseOK ? panel.URL : nil);
            }];
        };
        _discardConfirmationHandler = ^(NSWindow *window, NSDictionary *job, void (^completion)(BOOL)) {
            NSAlert *alert = [NSAlert new];
            weakSelf.discardAlert = alert;
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = NSLocalizedString(@"Discard this recording?", @"Explicit recording deletion confirmation.");
            alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"“%@” and its retained original audio will be permanently deleted. This cannot be undone.", @"Chosen recording deletion warning."), job[@"title"] ?: @"Recovered recording"];
            [alert addButtonWithTitle:NSLocalizedString(@"Discard Recording", @"Confirm chosen recording deletion.")];
            [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel chosen recording deletion.")];
            alert.buttons.firstObject.keyEquivalent = @"";
            alert.buttons.lastObject.keyEquivalent = @"\r";
            [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
                if (weakSelf.discardAlert == alert) weakSelf.discardAlert = nil;
                completion(response == NSAlertFirstButtonReturn);
            }];
        };
    }
    return self;
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = frame;
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (void)loadWindow {
    NSPanel *window = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 650, 460)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title = NSLocalizedString(@"Recover Recordings", @"Recording recovery window title.");
    window.releasedWhenClosed = NO;
    window.hidesOnDeactivate = NO;
    window.delegate = self;
    NSView *content = window.contentView;
    NSTextField *heading = [self label:NSLocalizedString(@"Unfinished recordings", @"Recovery list heading.") frame:NSMakeRect(20, 423, 450, 21)];
    heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    [content addSubview:heading];
    [content addSubview:[self label:NSLocalizedString(@"Original audio is kept until export succeeds or you confirm Discard.", @"Recovery data retention explanation.") frame:NSMakeRect(20, 401, 610, 18)]];
    NSScrollView *list = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 231, 610, 163)];
    list.borderType = NSBezelBorder;
    list.hasVerticalScroller = YES;
    self.tableView = [[NSTableView alloc] initWithFrame:list.bounds];
    self.tableView.identifier = @"RecordingRecoveryList";
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 30;
    self.tableView.allowsMultipleSelection = NO;
    self.tableView.allowsEmptySelection = NO;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.accessibilityLabel = NSLocalizedString(@"Unfinished recordings", @"Recovery list accessibility label.");
    NSArray *columns = @[@[@"title", @"Recording", @240], @[@"created", @"Created", @145], @[@"size", @"Raw size", @85], @[@"state", @"State", @110]];
    for (NSArray *spec in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = NSLocalizedString(spec[1], @"Recovery list column.");
        column.width = [spec[2] doubleValue];
        column.resizingMask = NSTableColumnNoResizing;
        [self.tableView addTableColumn:column];
    }
    list.documentView = self.tableView;
    [content addSubview:list];
    [content addSubview:[self label:NSLocalizedString(@"Destination", @"Recovery destination label.") frame:NSMakeRect(20, 204, 80, 18)]];
    self.destinationLabel = [self label:@"" frame:NSMakeRect(105, 204, 525, 18)];
    self.destinationLabel.selectable = YES;
    self.destinationLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.destinationLabel.accessibilityLabel = NSLocalizedString(@"Recording destination", @"Recovery destination accessibility label.");
    [content addSubview:self.destinationLabel];
    [content addSubview:[self label:NSLocalizedString(@"Details", @"Recovery error detail label.") frame:NSMakeRect(20, 181, 80, 18)]];
    NSScrollView *details = [[NSScrollView alloc] initWithFrame:NSMakeRect(105, 89, 525, 110)];
    details.hasVerticalScroller = YES;
    details.drawsBackground = NO;
    self.errorView = [[NSTextView alloc] initWithFrame:details.bounds];
    self.errorView.editable = NO;
    self.errorView.selectable = YES;
    self.errorView.drawsBackground = NO;
    self.errorView.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.errorView.textColor = NSColor.labelColor;
    self.errorView.textContainerInset = NSMakeSize(0, 0);
    self.errorView.verticallyResizable = YES;
    self.errorView.horizontallyResizable = NO;
    self.errorView.textContainer.widthTracksTextView = YES;
    self.errorView.autoresizingMask = NSViewWidthSizable;
    self.errorView.accessibilityLabel = NSLocalizedString(@"Recording recovery details", @"Recovery error details accessibility label.");
    details.documentView = self.errorView;
    [content addSubview:details];
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 57, 16, 16)];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.indeterminate = YES;
    self.progressIndicator.displayedWhenStopped = NO;
    self.progressIndicator.controlSize = NSControlSizeSmall;
    self.progressIndicator.accessibilityLabel = NSLocalizedString(@"Recording recovery operation in progress", @"Recovery progress accessibility label.");
    [content addSubview:self.progressIndicator];
    self.statusLabel = [self label:@"" frame:NSMakeRect(43, 55, 587, 20)];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [content addSubview:self.statusLabel];
    self.refreshButton = [self button:NSLocalizedString(@"Refresh", @"Refresh recovery list.") action:@selector(refresh:) frame:NSMakeRect(15, 13, 78, 30)];
    self.revealButton = [self button:NSLocalizedString(@"Reveal", @"Reveal recovery files in Finder.") action:@selector(revealSelected:) frame:NSMakeRect(98, 13, 78, 30)];
    self.discardButton = [self button:NSLocalizedString(@"Discard…", @"Ask to discard selected recording.") action:@selector(discardSelected:) frame:NSMakeRect(181, 13, 94, 30)];
    self.saveElsewhereButton = [self button:NSLocalizedString(@"Save Elsewhere…", @"Choose recovery export destination.") action:@selector(saveSelectedElsewhere:) frame:NSMakeRect(370, 13, 156, 30)];
    self.retryButton = [self button:NSLocalizedString(@"Retry", @"Retry selected recording export.") action:@selector(retrySelected:) frame:NSMakeRect(548, 13, 86, 30)];
    for (NSButton *button in @[self.refreshButton, self.revealButton, self.discardButton, self.saveElsewhereButton, self.retryButton]) [content addSubview:button];
    self.window = window;
    [window center];
    [self refreshPresentation];
}

- (void)showRecovery {
    NSAssert(NSThread.isMainThread, @"Recovery window belongs on main");
    if (!self.isWindowLoaded || !self.window.isVisible) self.presentationGeneration++;
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self refreshPresentation];
    if (!self.index.hasLoaded && !self.index.isRefreshing) [self.index refreshWithCompletion:nil];
}

- (void)setActionsEnabled:(BOOL)actionsEnabled {
    BOOL retiringDialogs = _actionsEnabled && !actionsEnabled;
    _actionsEnabled = actionsEnabled;
    if (retiringDialogs) {
        self.presentationGeneration++;
        [self retireDialogs];
    }
    [self refreshPresentation];
}

- (void)retireDialogs {
    self.dialogToken = nil;
    [self.savePanel cancel:nil];
    if (self.discardAlert.window.sheetParent) [self.discardAlert.window.sheetParent endSheet:self.discardAlert.window returnCode:NSAlertSecondButtonReturn];
    self.savePanel = nil;
    self.discardAlert = nil;
}

- (void)windowWillClose:(NSNotification *)notification {
    self.presentationGeneration++;
    [self retireDialogs];
}

- (NSDictionary *)selectedDisplayJob {
    NSString *identity = self.presentationSelection ?: self.index.selectedIdentity;
    for (NSDictionary *job in self.displayJobs) if ([job[@"directoryIdentity"] isEqual:identity]) return job;
    return nil;
}

- (NSString *)stateForJob:(NSDictionary *)job {
    AKRecoveryOperation *operation = self.operations[job[@"directoryIdentity"]];
    if (operation.finished) return self.index.isRefreshing ? NSLocalizedString(@"Checking result…", @"Refreshing a finished recording operation.") : NSLocalizedString(@"Refresh needed", @"Finished recording operation needs a successful scan.");
    if (operation) return [operation.kind isEqualToString:@"discard"] ? NSLocalizedString(@"Discarding…", @"Recording discard is pending.") : NSLocalizedString(@"Exporting…", @"Recording export is pending.");
    NSString *phase = job[@"phase"];
    if ([phase isEqualToString:@"failed"]) return NSLocalizedString(@"Export failed", @"Failed recording state.");
    if ([phase isEqualToString:@"unknown"]) return NSLocalizedString(@"Unknown", @"Recording state not recorded.");
    return NSLocalizedString(@"Interrupted", @"Abandoned unfinished recording state.");
}

- (void)refreshPresentation {
    NSAssert(NSThread.isMainThread, @"Recovery presentation belongs on main");
    // A result stays represented until a successful authoritative scan. A scan
    // error cannot erase a job merely because its claim hid it in an older scan.
    if (self.index.hasLoaded && !self.index.isRefreshing && !self.index.error) {
        for (NSString *identity in self.operations.allKeys.copy) {
            if (self.operations[identity].finished) [self.operations removeObjectForKey:identity];
        }
    }
    NSMutableArray *jobs = [self.index.jobs mutableCopy];
    NSMutableSet *identities = [NSMutableSet new];
    for (NSDictionary *job in jobs) if (job[@"directoryIdentity"]) [identities addObject:job[@"directoryIdentity"]];
    // An owned job disappears from discovery while its asynchronous work runs.
    // Keep its immutable snapshot so selection and truthful progress survive.
    for (NSString *identity in [self.operations.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![identities containsObject:identity]) { [jobs addObject:self.operations[identity].job]; [identities addObject:identity]; }
    }
    self.displayJobs = jobs;
    if (!self.presentationSelection || ![identities containsObject:self.presentationSelection]) self.presentationSelection = self.index.selectedIdentity;
    if (!self.presentationSelection || ![identities containsObject:self.presentationSelection]) self.presentationSelection = jobs.firstObject[@"directoryIdentity"];
    self.index.selectedIdentity = self.presentationSelection;
    if (!self.isWindowLoaded) return;
    self.updatingSelection = YES;
    [self.tableView reloadData];
    NSInteger row = -1;
    for (NSUInteger i = 0; i < jobs.count; i++) if ([jobs[i][@"directoryIdentity"] isEqual:self.presentationSelection]) { row = (NSInteger)i; break; }
    if (row >= 0) [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    else [self.tableView deselectAll:nil];
    self.updatingSelection = NO;
    NSDictionary *job = [self selectedDisplayJob];
    AKRecoveryOperation *operation = job ? self.operations[job[@"directoryIdentity"]] : nil;
    NSURL *destination = operation.destination ?: job[@"destinationURL"];
    self.destinationLabel.stringValue = destination.path ?: NSLocalizedString(@"No recording selected", @"No selected recovery destination.");
    self.destinationLabel.toolTip = destination.path;
    NSString *details = job[@"lastErrorDescription"] ?: @"";
    NSError *actual = job[@"lastError"];
    if ([actual isKindOfClass:NSError.class]) details = [NSString stringWithFormat:NSLocalizedString(@"Last recorded error: %@\n%@: %ld", @"Last known export error and diagnostic code."), actual.localizedDescription, actual.domain, (long)actual.code];
    NSString *actionError = job ? self.actionErrors[job[@"directoryIdentity"]] : nil;
    if (actionError.length) details = [NSString stringWithFormat:@"%@%@%@", actionError, details.length ? @"\n\n" : @"", details];
    if (operation.finished) {
        NSString *resultStatus = self.index.isRefreshing ? NSLocalizedString(@"The operation finished. Checking its current files…", @"Finished recording operation is being checked.") : NSLocalizedString(@"The operation finished, but its current files could not be checked. Choose Refresh to update this entry.", @"Finished recording operation needs a successful refresh.");
        details = [NSString stringWithFormat:@"%@\n\n%@", resultStatus, details];
    }
    else if (operation) details = [NSString stringWithFormat:NSLocalizedString(@"%@ The operation continues if you close this window.\n\n%@", @"Pending recording operation detail."), [self stateForJob:job], details];
    self.errorView.string = details;
    NSUInteger running = 0;
    for (AKRecoveryOperation *item in self.operations.allValues) if (!item.finished) running++;
    BOOL pending = self.index.isRefreshing || running > 0;
    if (pending) [self.progressIndicator startAnimation:nil]; else [self.progressIndicator stopAnimation:nil];
    if (self.index.error) self.statusLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Could not refresh: %@", @"Recovery discovery failure."), self.index.error.localizedDescription];
    else if (running) self.statusLabel.stringValue = running == 1 ? NSLocalizedString(@"1 operation in progress. It continues if this window is closed.", @"One pending recovery operation.") : [NSString stringWithFormat:NSLocalizedString(@"%lu operations in progress. They continue if this window is closed.", @"Pending recovery operation count."), (unsigned long)running];
    else if (self.index.isRefreshing) self.statusLabel.stringValue = NSLocalizedString(@"Checking retained recordings…", @"Recovery scan pending.");
    else self.statusLabel.stringValue = jobs.count == 1 ? NSLocalizedString(@"1 unfinished recording. Select it to recover or discard.", @"One unfinished recording.") : jobs.count ? [NSString stringWithFormat:NSLocalizedString(@"%lu unfinished recordings. Select one to recover or discard.", @"Recovery count and action guidance."), (unsigned long)jobs.count] : NSLocalizedString(@"No unfinished recordings.", @"Empty recovery list.");
    self.statusLabel.toolTip = self.statusLabel.stringValue;
    self.statusLabel.accessibilityLabel = self.statusLabel.stringValue;
    BOOL actionable = self.actionsEnabled && job && !operation && !self.dialogToken;
    self.retryButton.enabled = actionable && [job[@"destinationURL"] isKindOfClass:NSURL.class] && ![job[@"needsNewDestination"] boolValue];
    self.saveElsewhereButton.enabled = actionable;
    self.discardButton.enabled = actionable;
    self.revealButton.enabled = self.actionsEnabled && job && !self.dialogToken;
    self.refreshButton.enabled = self.actionsEnabled && !self.index.isRefreshing && !self.dialogToken;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.displayJobs.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.displayJobs.count) return nil;
    NSDictionary *job = self.displayJobs[(NSUInteger)row];
    NSTextField *label = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!label) { label = [NSTextField labelWithString:@""]; label.identifier = column.identifier; label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize]; label.lineBreakMode = NSLineBreakByTruncatingTail; }
    NSString *value = @"";
    if ([column.identifier isEqualToString:@"title"]) value = job[@"title"] ?: @"Recovered recording";
    else if ([column.identifier isEqualToString:@"created"] && [job[@"created"] isKindOfClass:NSDate.class]) value = [NSDateFormatter localizedStringFromDate:job[@"created"] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
    else if ([column.identifier isEqualToString:@"size"]) value = [NSByteCountFormatter stringFromByteCount:[job[@"retainedRawBytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    else if ([column.identifier isEqualToString:@"state"]) value = [self stateForJob:job];
    label.stringValue = value;
    label.toolTip = [column.identifier isEqualToString:@"size"] ? [NSString stringWithFormat:@"%@ (%llu bytes)", value, [job[@"retainedRawBytes"] unsignedLongLongValue]] : value;
    label.accessibilityLabel = value;
    return label;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (self.updatingSelection) return;
    NSInteger row = self.tableView.selectedRow;
    self.presentationSelection = row >= 0 && row < (NSInteger)self.displayJobs.count ? self.displayJobs[(NSUInteger)row][@"directoryIdentity"] : nil;
    self.index.selectedIdentity = self.presentationSelection;
    [self refreshPresentation];
}

- (IBAction)refresh:(id)sender {
    if (!self.actionsEnabled || self.index.isRefreshing || self.dialogToken) return;
    [self.index refreshWithCompletion:nil];
}

- (NSDictionary *)admissibleJob {
    NSDictionary *job = [self selectedDisplayJob];
    NSString *identity = job[@"directoryIdentity"];
    return self.actionsEnabled && !self.dialogToken && identity.length && !self.operations[identity] ? job : nil;
}

- (void)submitRetry:(NSDictionary *)job destination:(NSURL *)destination {
    if (!self.actionsEnabled || self.operations[job[@"directoryIdentity"]] || !destination) return;
    AKRecoveryOperation *operation = [AKRecoveryOperation new];
    operation.job = [job copy]; operation.kind = @"export"; operation.destination = destination;
    NSString *identity = job[@"directoryIdentity"];
    self.operations[identity] = operation;
    [self.actionErrors removeObjectForKey:identity];
    [self refreshPresentation];
    __weak RecordingRecoveryController *weakSelf = self;
    self.retryHandler(operation.job, destination, ^(BOOL succeeded) {
        RecoveryOnMain(^{
            RecordingRecoveryController *controller = weakSelf;
            if (!controller || controller.operations[identity] != operation || operation.finished) return;
            operation.finished = YES;
            if (!succeeded) controller.actionErrors[identity] = NSLocalizedString(@"The export request did not complete.", @"BOOL-only retry failure may include stale or busy admission.");
            [controller.index refreshWithCompletion:nil];
        });
    });
}

- (IBAction)retrySelected:(id)sender {
    NSDictionary *job = [self admissibleJob];
    if (!job || [job[@"needsNewDestination"] boolValue]) return;
    NSURL *destination = job[@"destinationURL"];
    if ([destination isKindOfClass:NSURL.class]) [self submitRetry:job destination:destination];
}

- (BOOL)dialogIsCurrent:(NSObject *)token generation:(NSUInteger)generation identity:(NSString *)identity {
    return self.actionsEnabled && self.dialogToken == token && self.presentationGeneration == generation &&
        [self.presentationSelection isEqualToString:identity] && self.window.isVisible && !self.operations[identity];
}

- (IBAction)saveSelectedElsewhere:(id)sender {
    NSDictionary *job = [self admissibleJob];
    if (!job || !self.window.isVisible) return;
    NSObject *token = [NSObject new]; self.dialogToken = token;
    NSUInteger generation = self.presentationGeneration;
    NSString *identity = job[@"directoryIdentity"];
    [self refreshPresentation];
    __weak RecordingRecoveryController *weakSelf = self;
    self.savePanelHandler(self.window, [job copy], ^(NSURL *destination) {
        RecoveryOnMain(^{
            RecordingRecoveryController *controller = weakSelf;
            BOOL current = [controller dialogIsCurrent:token generation:generation identity:identity];
            if (controller.dialogToken == token) controller.dialogToken = nil;
            if (current && destination) [controller submitRetry:job destination:destination];
            else [controller refreshPresentation];
        });
    });
}

- (IBAction)revealSelected:(id)sender {
    if (!self.actionsEnabled || self.dialogToken) return;
    NSURL *directory = [self selectedDisplayJob][@"directoryURL"];
    if ([directory isKindOfClass:NSURL.class]) self.revealHandler(directory);
}

- (IBAction)discardSelected:(id)sender {
    NSDictionary *job = [self admissibleJob];
    if (!job || !self.window.isVisible) return;
    NSObject *token = [NSObject new]; self.dialogToken = token;
    NSUInteger generation = self.presentationGeneration;
    NSString *identity = job[@"directoryIdentity"];
    [self refreshPresentation];
    __weak RecordingRecoveryController *weakSelf = self;
    self.discardConfirmationHandler(self.window, [job copy], ^(BOOL confirmed) {
        RecoveryOnMain(^{
            RecordingRecoveryController *controller = weakSelf;
            BOOL current = [controller dialogIsCurrent:token generation:generation identity:identity];
            if (controller.dialogToken == token) controller.dialogToken = nil;
            if (!current || !confirmed) { [controller refreshPresentation]; return; }
            AKRecoveryOperation *operation = [AKRecoveryOperation new];
            operation.job = [job copy]; operation.kind = @"discard";
            controller.operations[identity] = operation;
            [controller.actionErrors removeObjectForKey:identity];
            [controller refreshPresentation];
            controller.discardHandler(operation.job, ^(BOOL succeeded, NSError *error) {
                RecoveryOnMain(^{
                    RecordingRecoveryController *owner = weakSelf;
                    if (!owner || owner.operations[identity] != operation || operation.finished) return;
                    operation.finished = YES;
                    if (!succeeded) owner.actionErrors[identity] = error ? [NSString stringWithFormat:@"%@\n%@: %ld", error.localizedDescription, error.domain, (long)error.code] : NSLocalizedString(@"Discard did not complete. Refresh the recording before trying again.", @"Unknown discard failure.");
                    [owner.index refreshWithCompletion:nil];
                });
            });
        });
    });
}
@end
