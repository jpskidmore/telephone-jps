#!/usr/bin/env python3
"""Require executed Contacts regressions in the isolated native result bundle."""
import json
from pathlib import Path
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: verify-contacts-regressions.py TelephoneTests.xcresult')
required = {
    'ContactsRecoveryTests/testFailedFirstUseDoesNotPromptAgainOnActivationButExplicitRetryCanRequest()',
    'ContactsRecoveryTests/testFirstUseRequestsOnceThenPublishesHistoryAndDiallerMatches()',
    'ContactsRecoveryTests/testFirstUseRespectsExistingAuthorizedDeniedAndRestrictedChoices()',
    'ContactsRecoveryTests/testDeniedContactsDoNotFetchOrRequestAccessDuringEnumeration()',
    'ContactsRecoveryTests/testPermissionRevokedDuringFetchDiscardsSnapshotWithTypedFailure()',
    'DiallerContactsTests/testDeniedReadClearsSnapshotAndCannotReturnAfterStatusReallowsWithoutReload()',
}
data = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', sys.argv[1], '--compact']))
passed = set()
def visit(node):
    if node.get('nodeType') == 'Test Case' and node.get('result') == 'Passed':
        passed.add(node.get('nodeIdentifier'))
    for child in node.get('children', []):
        visit(child)
for node in data['testNodes']:
    visit(node)
missing = required - passed
if missing:
    raise SystemExit('Contacts release gate missing passing cases: ' + ', '.join(sorted(missing)))
# The isolated host cannot safely run normal startup against an owner profile.
# Verify its separate production startup hook without claiming UI integration.
root = Path(__file__).resolve().parent.parent
source = (root / 'Telephone/AppController.m').read_text()
launch = source.split('- (void)applicationDidFinishLaunching:', 1)[1].split('\n- (', 1)[0]
if '[self.compositionRoot startContactAccess];' not in launch:
    raise SystemExit('Normal startup is missing the first-use Contacts hook')
print(f'Contacts release gate passed: {len(required)} executed synthetic regressions plus startup source-wiring check (not real Contacts acceptance)')
