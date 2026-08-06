//
//  CallControllerLifecycleTests.m
//  TelephoneTests
//

#import <XCTest/XCTest.h>

#import "AKSIPCall.h"
#import "CallController.h"

@interface AKStoppedRecordingCallStub : AKSIPCall
@end

@implementation AKStoppedRecordingCallStub

- (BOOL)isRecording {
    return NO;
}

@end

@interface CallController (LifecycleTests)
- (void)subscribeToWindowFloatingChanges;
@end

@interface CallControllerLifecycleTests : XCTestCase
@end

@implementation CallControllerLifecycleTests

- (void)testControllerCanDeallocateAfterItsCallHasStoppedRecording {
    __weak CallController *weakController = nil;

    @autoreleasepool {
        CallController *controller =
            [[CallController alloc] initWithWindowNibName:@"Call"
                                       accountController:nil
                                               userAgent:nil
                                                delegate:nil];
        [controller subscribeToWindowFloatingChanges];
        controller.call = [[AKStoppedRecordingCallStub alloc] init];
        weakController = controller;
    }

    // The 2.0.1 implementation aborted in objc_initWeak while releasing the
    // controller, before this assertion could run.
    XCTAssertNil(weakController);
}

@end
