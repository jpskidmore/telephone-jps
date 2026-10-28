#!/usr/bin/env python3
"""Compare the current pure snapshot engine with frozen, complete legacy outputs."""
from __future__ import annotations
import argparse, datetime, hashlib, json, pathlib, subprocess, sys
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', type=pathlib.Path, required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
parser.add_argument('--sizes', type=int, nargs='+', default=[100, 1000, 10000])
args = parser.parse_args()
baseline = args.baseline.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
sources = [ROOT / 'UseCases/Contact.swift', ROOT / 'UseCases/ContactCompletionSnapshot.swift', HERE / 'Candidate.swift']
source_hashes = {str(p.relative_to(ROOT)): sha(p) for p in sources}
for path in sources[:2]:
    text = path.read_text()
    if any(name in text for name in ('ABAddressBook', 'CNContactStore', 'standardUserDefaults', 'import Contacts', 'import AddressBook')):
        parser.error(f'Candidate benchmark requires pure value sources, found store dependency in {path}')
binary = out / 'candidate'
command = ['xcrun', 'swiftc', '-O', '-swift-version', '6', *map(str, sources), '-o', str(binary)]
proc = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(out / 'build.log').write_bytes(proc.stdout)
if proc.returncode:
    sys.stderr.write(proc.stdout.decode(errors='replace'))
    raise SystemExit(proc.returncode)
if source_hashes != {str(p.relative_to(ROOT)): sha(p) for p in sources}:
    raise SystemExit('Candidate inputs changed during compilation; rebuild against a frozen source set')
manifest = {'createdAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'scope': 'Pure snapshot engine CPU over the full frozen synthetic fixture; no real AddressBook index/store/disk latency.',
            'sourceSHA256': source_hashes, 'compileCommand': command,
            'baselineManifestSHA256': sha(baseline / 'manifest.json'), 'baselineInputSHA256': {},
            'generatedSHA256': {}, 'summary': []}
for size in args.sizes:
    inputs = [baseline / f'baseline-{size}-fixtures.json', baseline / f'baseline-{size}-outputs.json', baseline / f'baseline-{size}.json']
    for path in inputs:
        manifest['baselineInputSHA256'][path.name] = sha(path)
    result_path = out / f'candidate-{size}.json'
    proc = subprocess.run([str(binary), *map(str, inputs), str(result_path)], cwd=ROOT,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / f'candidate-{size}.log').write_bytes(proc.stdout)
    result = json.loads(result_path.read_text())
    if proc.returncode or result['parityFailures']:
        sys.stderr.write(json.dumps(result['parityFailures'], indent=2) + '\n')
        raise SystemExit(f'Full ordered parity failed for {size} contacts')
    manifest['summary'].append({'contacts': result['contacts'], 'fixtureSet': size, 'fullOrderedCompletionInputs': result['completionInputsCompared'],
                                'tokenRecordAndDestinationInputs': result['tokenInputsCompared'],
                                'parityFailures': 0, 'coldSnapshotConstructionMS': result['coldSnapshotConstructionMS'],
                                'queryWallMS': result['aggregateQueryWallMS'],
                                'tokenLookupOnlyWallMS': result['aggregateTokenLookupOnlyWallMS']})
for path in sorted(out.iterdir()):
    if path.is_file() and path.name != 'manifest.json':
        manifest['generatedSHA256'][path.name] = sha(path)
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest['summary'], indent=2))
