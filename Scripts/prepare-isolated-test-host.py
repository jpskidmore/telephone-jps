#!/usr/bin/env python3
"""Isolate a prebuilt Debug TelephoneTests host; never starts the application."""
from pathlib import Path
import plistlib, shutil, subprocess, sys, uuid
if len(sys.argv) != 2:
    raise SystemExit('usage: prepare-isolated-test-host.py derived-data-directory')
products = Path(sys.argv[1]).resolve() / 'Build/Products'
runs = list(products.glob('TelephoneTests_*.xctestrun'))
if len(runs) != 1:
    raise SystemExit('Build TelephoneTests with build-for-testing first; expected exactly one xctestrun')
metadata = plistlib.loads(runs[0].read_bytes())
target = metadata['TelephoneTests']
if '/Debug/' not in target['TestHostPath']:
    raise SystemExit('Only a Debug test host may be isolated')
source = products / 'Debug/jps Telephone.app'
host = products / 'Debug/Isolated Telephone.app'
if host.exists(): shutil.rmtree(host)
subprocess.run(['ditto', '--norsrc', '--noextattr', str(source), str(host)], check=True)
info = host/'Contents/Info.plist'
values = plistlib.loads(info.read_bytes())
values['CFBundleIdentifier'] = 'uk.jpsit.telephone.tests.' + uuid.uuid4().hex
values.pop('NSMainNibFile', None)
info.write_bytes(plistlib.dumps(values))
subprocess.run(['xattr', '-cr', str(host)], check=True)
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(host)], check=True)
target['TestHostBundleIdentifier'] = values['CFBundleIdentifier']
target['TestHostPath'] = '__TESTROOT__/Debug/Isolated Telephone.app'
target['DependentProductPaths'] = [s.replace('jps Telephone.app', 'Isolated Telephone.app') for s in target['DependentProductPaths']]
output = products/'IsolatedTelephoneTests.xctestrun'
output.write_bytes(plistlib.dumps(metadata))
assert 'NSMainNibFile' not in plistlib.loads(info.read_bytes())
assert plistlib.loads((source/'Contents/Info.plist').read_bytes()).get('NSMainNibFile'), 'Production metadata must retain its normal nib'
print(output)
