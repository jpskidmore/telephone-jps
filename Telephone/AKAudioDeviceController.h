//
//  AKAudioDeviceController.h
//  Telephone
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This seam lets the production failure gate be tested without loading PJSUA or
// opening hardware. The backend returns raw pj_status_t values as int (0 = OK).
@protocol AKAudioDeviceBackend <NSObject>
- (int)selectInput:(int)input output:(int)output;
- (int)useNullSoundDevice;
- (int)connectSource:(int)source destination:(int)destination;
@end

typedef void (^AKAudioDeviceLogger)(NSString *message);
typedef void (^AKAudioDeviceFailureHandler)(int status);

// Synchronous, main-thread-owned failure gate. The application must serialize
// all access on its main thread; this class neither dispatches nor uses locks.
// It bounds repeated backend attempts, not the duration of one backend call.
// The logger must not reenter the controller. The failure handler is called
// synchronously after fallback has finished, with the first failure still
// latched, and may safely inspect state or attempt a gated operation.
@interface AKAudioDeviceController : NSObject

- (instancetype)initWithBackend:(id<AKAudioDeviceBackend>)backend
                         logger:(nullable AKAudioDeviceLogger)logger NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, readonly) BOOL hasFailed;
@property(nonatomic, readonly) int lastFailureStatus;
@property(nonatomic, readonly) BOOL outgoingCallPending;
// At most one call per failure episode. Assigning this after a failure does not
// replay it. The owner should avoid a retain cycle when capturing itself.
@property(nonatomic, copy, nullable) AKAudioDeviceFailureHandler failureHandler;

// Reserve admission before dispatching an outgoing SDK request. A failed gate
// or an already pending request rejects admission. Neither method calls the
// backend. The owner also checks user-agent lifecycle and visible recovery state.
- (BOOL)beginOutgoingCall;
// The owner must verify the lifecycle generation before finishing a request,
// and finish/report its result in the same main-thread completion without
// yielding or invoking user callbacks between those two operations.
- (void)finishOutgoingCall;

// Any selection failure latches, attempts null sound once, and notifies once.
// Changing IDs alone never retries hardware. While latched, these operations
// return the first failure without calling the backend.
- (int)selectInput:(int)input output:(int)output;
- (int)connectSource:(int)source destination:(int)destination;

// A direct null/stop failure latches and notifies without retrying null sound.
// While already latched it returns the original failure without backend work.
- (int)useNullSoundDevice;

// For SDK entry points that may open audio internally (for example make-call).
// The caller times/logs its own SDK operation, then reports its raw result here
// on the main thread. Only recognized audio errors latch and trigger fallback.
// Known diagnostic labels: make-call, answer-call, media-state, external.
// Any other label is logged as "external" to avoid leaking arbitrary content.
- (void)reportAudioFailure:(int)status operation:(NSString *)operation;
+ (BOOL)isAudioDeviceFailure:(int)status;

// For operations that are unambiguously audio setup, including failures before
// selection reaches this gate. Any nonzero status latches. Additional safe
// labels: device-refresh and retry-selection. Never use for general SIP errors.
- (void)reportDeviceFailure:(int)status operation:(NSString *)operation;

// The only way out of a failure episode. The caller must make this an explicit
// user retry, not a device-change or call-state automatic retry. No hardware
// operation is performed. Retains the last attempted selection IDs for logs.
// Does not clear outgoingCallPending: an explicit retry cannot bypass in-flight
// SDK work. Only the matching lifecycle-checked completion may finish that work.
- (void)resetFailure;

@end

NS_ASSUME_NONNULL_END
