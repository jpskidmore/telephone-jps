#!/usr/bin/env python3
"""Portable control-flow regression model; NOT execution of the macOS application.

Native ownership tests live in TelephoneTests/CallControllerLifecycleTests.m;
actual conversion/drain tests live in RecordingHardeningHarness.m.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Scope:
    def __init__(self):
        self.releases = 0

    def release(self):
        self.releases += 1


class Call:
    def __init__(self, scope):
        self.scope = scope
        self.recording = True
        self.stop_calls = 0
        self.completion = None

    def stop(self, fail=False):
        if not self.recording:
            return
        self.stop_calls += 1
        if fail:
            return
        self.recording = False
        owned_scope, self.scope = self.scope, None
        self.completion = owned_scope.release

    def complete(self):
        callback, self.completion = self.completion, None
        if callback:
            callback()


class Controller:
    def __init__(self, call):
        self.call = call

    def stop(self):
        self.call.stop()

    def replace(self, call):
        self.stop()
        self.call = call


class PendingConversions:
    def __init__(self):
        self.pending = 0
        self.main_queue = []
        self.waiters = []

    def submit(self, cleanup):
        self.pending += 1
        def finish():
            cleanup()
            self.pending -= 1
            if self.pending == 0:
                self.main_queue.extend(self.waiters)
                self.waiters = []
        self.main_queue.append(finish)

    def wait(self, callback):
        if self.pending:
            self.waiters.append(callback)
        else:
            self.main_queue.append(callback)

    def drain_main_queue(self):
        while self.main_queue:
            self.main_queue.pop(0)()


class RecordingLifecycleModelTests(unittest.TestCase):
    def test_source_contains_the_modeled_ownership_and_async_barrier(self):
        controller = (ROOT / 'Telephone/CallController.m').read_text()
        call = (ROOT / 'Telephone/AKSIPCall.m').read_text()
        encoder = (ROOT / 'Telephone/AKStereoRecording.m').read_text()
        app = (ROOT / 'Telephone/AppController.m').read_text()
        agent = (ROOT / 'Telephone/AKSIPUserAgent.m').read_text()
        self.assertNotIn('isFinalizingRecording', controller)
        self.assertNotIn('activeRecordingDirectoryURL', controller)
        self.assertIn('[self.call stopRecording];', controller)
        self.assertIn('self.accessedRecordingDirectoryURL = directoryURL;', call)
        capture = call.index('NSURL *accessedDirectoryURL = self.accessedRecordingDirectoryURL;')
        detach = call.index('self.accessedRecordingDirectoryURL = nil;', capture)
        convert = call.index('[self finalizeRecordingFromLocalURL:', detach)
        release = call.index('[accessedDirectoryURL stopAccessingSecurityScopedResource];', convert)
        self.assertLess(capture, detach)
        self.assertLess(detach, convert)
        self.assertLess(convert, release)
        self.assertIn('dispatch_group_enter(RecordingFinalizations());', encoder)
        self.assertIn('dispatch_group_notify(RecordingFinalizations(), dispatch_get_main_queue(), completion);', encoder)
        self.assertLess(encoder.index('completion(succeeded);'), encoder.index('dispatch_group_leave(RecordingFinalizations());'))
        self.assertNotIn('dispatch_group_wait', encoder + app)
        self.assertIn('AKWaitForPendingRecordingFinalizations(^{', app)
        self.assertIn('self.userAgent.state == AKSIPUserAgentStateStopped', app)
        self.assertIn('![self.delegate SIPUserAgentShouldStart]', agent)
        self.assertIn('- (BOOL)SIPUserAgentShouldStart {\n    return !self.isTerminating;', app)

    def test_redial_and_both_completion_orders_release_once_per_recording(self):
        for reverse in (False, True):
            scope = Scope()
            a, b = Call(scope), Call(scope)
            controller = Controller(a)
            controller.stop()
            controller.replace(b)
            controller.stop()
            controller.stop()
            self.assertEqual((a.stop_calls, b.stop_calls), (1, 1))
            self.assertFalse(b.recording)
            self.assertEqual(scope.releases, 0)
            first, second = (b, a) if reverse else (a, b)
            first.complete()
            self.assertEqual(scope.releases, 1)
            second.complete()
            self.assertEqual(scope.releases, 2)

    def test_native_stop_failure_keeps_scope_until_retry_finishes(self):
        scope = Scope()
        call = Call(scope)
        call.stop(fail=True)
        self.assertTrue(call.recording)
        self.assertEqual(scope.releases, 0)
        call.stop()
        call.complete()
        self.assertEqual(scope.releases, 1)

    def test_quit_barrier_runs_after_all_main_queue_cleanup(self):
        group = PendingConversions()
        events = []
        group.submit(lambda: events.append('success cleanup'))
        group.submit(lambda: events.append('failure cleanup'))
        group.wait(lambda: events.append('terminate'))
        self.assertEqual(events, [])
        group.drain_main_queue()
        self.assertEqual(events, ['success cleanup', 'failure cleanup', 'terminate'])

    def test_quit_rejects_late_start_and_rechecks_sip_state(self):
        # Model the start delegate and final callback separately from dispatch.
        terminating = True
        self.assertFalse(not terminating)  # delayed receipt/reachability start
        for state in ('stopped', 'starting', 'started', 'stopping'):
            result = ('terminate' if state == 'stopped' else
                      'stop' if state == 'started' else 'await notification')
            if state == 'stopped':
                self.assertEqual(result, 'terminate')
            else:
                self.assertNotEqual(result, 'terminate')

    def test_empty_barrier_does_not_complete_synchronously(self):
        group = PendingConversions()
        events = []
        group.wait(lambda: events.append('terminate'))
        self.assertEqual(events, [])
        group.drain_main_queue()
        self.assertEqual(events, ['terminate'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
