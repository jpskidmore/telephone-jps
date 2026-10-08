#!/usr/bin/env python3
"""Require recorded verification of the finite 2.1.8 audit before packaging."""
from pathlib import Path
import json
repo = Path(__file__).resolve().parents[1]
record = json.loads((repo/'docs/audit-2.1.8/repair-progress.json').read_text())
items = record['items']
assert sorted(i['number'] for i in items) == list(range(2, 52)), 'Expected exactly the 50 baseline issues'
incomplete = [i['number'] for i in items if i['status'] != 'fixed_verified' or not i['rootCause'] or not i['fixCommits'] or not i['regressions'] or not i['verifiedAtUTC']]
if incomplete: raise SystemExit('Release gate closed: missing verified repairs for ' + ', '.join(map(str, incomplete)))
print('Release repair gate passed: all 50 baseline findings have recorded verified fixes')
