#!/usr/bin/env python3
"""Portable source wiring checks, not execution of Cocoa or PJSIP.

The production failure gate itself is executed by the native Foundation-only
AudioDeviceControllerHarness. These checks prevent bypassing its integration.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
def source(path):
    return (ROOT / path).read_text()

class AudioRecoveryWiringTests(unittest.TestCase):
    def test_all_conference_connections_use_one_backend(self):
        sites = []
        for path in (ROOT / 'Telephone').glob('*.m'):
            for line in path.read_text().splitlines():
                if re.search(r'\bpjsua_conf_connect\s*\(', line):
                    sites.append((path.name, line))
        self.assertEqual(len(sites), 1)
        self.assertEqual(sites[0][0], 'AKSIPUserAgent.m')
        self.assertIn('connectSource:', sites[0][1])

    def test_media_checks_identity_current_state_and_first_connection(self):
        media = source('Telephone/PJSUAOnCallMediaState.m')
        self.assertIn('call.dialogIdentifier isEqualToString:dialogIdentifier', media)
        self.assertIn('info.state == PJSIP_INV_STATE_DISCONNECTED', media)
        self.assertIn('info.media_cnt == 0', media)
        self.assertIn('if ([agent connectAudioSource:port destination:0] != PJ_SUCCESS) return;', media)
        # Holding/signaling notifications remain even when hardware failed.
        self.assertIn('PostMediaStateChangeNotification(call, status);', media)

    def test_recording_and_reconnect_are_gated_but_stop_is_not(self):
        call = source('Telephone/AKSIPCall.m')
        start = call.split('- (BOOL)startRecordingToURL:(NSURL *)URL {', 1)[1].split('- (void)stopRecording', 1)[0]
        self.assertIn('[AKSIPUserAgent sharedUserAgent].hasAudioFailure', start)
        self.assertLess(start.index('hasAudioFailure'), start.index('pjsua_recorder_create'))
        stop = call.split('- (BOOL)stopNativeRecorders {', 1)[1].split('- (void)finalizeRecording', 1)[0]
        self.assertIn('pjsua_recorder_destroy', stop)
        self.assertNotIn('hasAudioFailure', stop)

    def test_outgoing_work_is_gated_and_generation_checked(self):
        account = source('Telephone/AKSIPAccount.m')
        self.assertIn('if (![agent beginOutgoingCall])', account)
        self.assertIn('audioGeneration != parameters.audioGeneration', account)
        self.assertIn('agent.audioGeneration == parameters.audioGeneration', account)
        self.assertIn('reportAudioFailure:makeStatus operation:@"make-call"', account)
        agent = source('Telephone/AKSIPUserAgent.m')
        self.assertIn('[self.audioDeviceController beginOutgoingCall]', agent)
        self.assertIn('self.audioGeneration++', agent.split('- (void)stop {', 1)[1].split('- (void)stopAndWait', 1)[0])

    def test_device_events_do_not_reset_and_retry_uses_current_preferences(self):
        agent = source('Telephone/AKSIPUserAgent.m')
        refresh = agent.split('- (void)updateAudioDevices {', 1)[1].split('- (void)updateCodecs', 1)[0]
        self.assertNotIn('resetFailure', refresh)
        self.assertNotIn('resetAudioFailure', refresh)
        self.assertIn('if (![self stopSound])', refresh)
        self.assertIn('self.soundIOSelectionRetry()', agent)
        self.assertIn('weak soundIOSelection', source('Telephone/CompositionRoot.swift'))

    def test_failure_is_visible_and_recording_stops(self):
        call = source('Telephone/CallController.m')
        self.assertIn('NSLocalizedString(@"Audio unavailable"', call)
        self.assertIn('self.userAgent.hasAudioFailure', call.split('- (void)setStatus:', 1)[1].split('- (void)setCallActive:', 1)[0])
        app = source('Telephone/AppController.m')
        recovery = app.split('- (void)SIPUserAgentAudioStateDidChange:', 1)[1].split('- (IBAction)addAccountOnFirstLaunch:', 1)[0]
        self.assertIn('beginSheetModalForWindow:', recovery)
        self.assertNotIn('runModal', recovery)
        self.assertIn('installAudioRecoveryMenuItem', app)

    def test_recovery_does_not_synthesize_none_media_or_reopen_idle(self):
        agent = source('Telephone/AKSIPUserAgent.m')
        restore = agent.split('- (void)restoreCurrentAudioConnections {', 1)[1].split('- (int)inputDeviceIDWithID:', 1)[0]
        self.assertIn('info.media[0].status == PJSUA_CALL_MEDIA_ACTIVE ||', restore)
        self.assertIn('info.media[0].status == PJSUA_CALL_MEDIA_LOCAL_HOLD ||', restore)
        self.assertIn('info.media[0].status == PJSUA_CALL_MEDIA_REMOTE_HOLD)', restore)
        self.assertIn('info.media[0].status == PJSUA_CALL_MEDIA_NONE)', restore)
        self.assertIn('info.role == PJSIP_ROLE_UAC && call.state == kAKSIPCallEarlyState', restore)
        retry = agent.split('- (BOOL)retrySoundAfterFailure {', 1)[1].split('- (pj_status_t)connectAudioSource:', 1)[0]
        self.assertIn('self.activeCallsCount == 0', retry)
        self.assertIn('pjsua_conf_disconnect(self.ringbackSlot, 0)', retry)

    def test_completed_shutdown_clears_warning_without_native_queries(self):
        agent = source('Telephone/AKSIPUserAgent.m')
        finish = agent.split('- (void)finishStopping {', 1)[1].split('- (BOOL)addAccount:', 1)[0]
        self.assertIn('BOOL hadAudioFailure', finish)
        self.assertIn('AKSIPUserAgentAudioStateDidChangeNotification', finish)
        call = source('Telephone/CallController.m')
        observer = call.split('- (void)SIPUserAgentAudioStateDidChange:', 1)[1].split('\n- (', 1)[0]
        self.assertLess(observer.index('!self.userAgent.isStarted'), observer.index('self.call.isOnLocalHold'))

    def test_audio_failure_does_not_suppress_off_hold_transition(self):
        call = source('Telephone/CallController.m')
        media = call.split('- (void)SIPCallMediaDidBecomeActive:', 1)[1].split('- (void)SIPCallDidLocalHold:', 1)[0]
        self.assertIn('if (!self.userAgent.hasAudioFailure)', media)
        self.assertIn('[self setCallOnHold:NO]', media)
        self.assertNotIn('return;', media)

    def test_enumeration_releases_buffer_on_throw(self):
        text = source('Telephone/UserAgentAudioDevices.swift')
        self.assertLess(text.index('defer { bytes.deallocate() }'), text.index('try copyDevicesBytes'))

    def test_app_build_contains_production_gate(self):
        project = source('Telephone.xcodeproj/project.pbxproj')
        self.assertEqual(project.count('AKAudioDeviceController.m in Sources'), 2)
        self.assertIn('AFA000020000000000000002', project)

if __name__ == '__main__':
    unittest.main(verbosity=2)
