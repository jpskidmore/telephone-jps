#!/usr/bin/env python3
"""Run isolated synthetic legacy completion CPU baseline; never opens a Contacts store."""
from __future__ import annotations
import argparse, datetime, hashlib, json, pathlib, subprocess, sys
BASELINE = '83d691eaa9d7f348b895720c79c2637ae080d2e6'
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def historical(path):
    return subprocess.check_output(['git', 'show', f'{BASELINE}:{path}'], cwd=ROOT)

def extract_method(source, marker):
    start = source.index(marker)
    end = source.find('\n- (', start + 3)
    if end < 0:
        end = source.index('\n@end', start)
    return source[start:end].rstrip() + '\n'

def run(command, log, expected=0):
    proc = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_bytes(proc.stdout)
    if proc.returncode != expected:
        sys.stderr.write(proc.stdout.decode(errors='replace'))
        raise SystemExit(f'{command[0]} returned {proc.returncode}, expected {expected}; see {log}')

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--products', type=pathlib.Path, required=True,
                    help='Locally validated Debug products containing UseCases.framework and Domain.framework')
parser.add_argument('--output', type=pathlib.Path, required=True)
parser.add_argument('--sizes', type=int, nargs='+', default=[100, 1000, 10000])
args = parser.parse_args()
products = args.products.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
for name in ('UseCases', 'Domain'):
    if not (products / f'{name}.framework' / name).is_file():
        parser.error(f'Missing {name}.framework under {products}')
manifest = {'baselineCommit': BASELINE, 'createdAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'scope': 'Synthetic detached directory scan CPU, not real system AddressBook store/index/disk latency.',
            'historicalSourceSHA256': {}, 'generatedSHA256': {}, 'frameworkSHA256': {}}
source = {}
paths = ['ActiveAccountViewController.m', 'AKABRecord+Querying.m', 'AKABAddressBook+Localizing.m',
         'AKSIPURI.m', 'AKSIPURI.h', 'AKSIPURIFormatter.m', 'AKSIPURIFormatter.h',
         'AKTelephoneNumberFormatter.m', 'AKTelephoneNumberFormatter.h', 'AKABRecord+Querying.h',
         'AKABAddressBook+Localizing.h', 'UserDefaultsKeys.swift']
for name in paths:
    data = historical(f'Telephone/{name}')
    source[name] = data.decode()
    manifest['historicalSourceSHA256'][f'Telephone/{name}'] = hashlib.sha256(data).hexdigest()
    if name not in ('ActiveAccountViewController.m', 'AKABRecord+Querying.m',
                    'AKABAddressBook+Localizing.m', 'UserDefaultsKeys.swift'):
        if name == 'AKSIPURI.m':
            # These imports are unused by every method in this pure value object.
            # Removing only imports keeps PJSIP absent from the benchmark process.
            for line in ('#import <pjsua-lib/pjsua.h>', '#import "AKNSString+PJSUA.h"', '#import "AKSIPUserAgent.h"'):
                data = data.replace(line.encode(), ('// Standalone benchmark omits unused import: ' + line).encode())
        (out / name).write_bytes(data)
view = source['ActiveAccountViewController.m']
pieces = {
    'COMPLETION_METHOD': extract_method(view, '- (NSArray *)tokenField:(NSTokenField *)tokenField\n        completionsForSubstring:'),
    'TOKEN_METHOD': extract_method(view, '- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:'),
}
for key, name, marker in [('NAME_METHODS', 'AKABRecord+Querying.m', '- (NSString *)ak_fullNameWithNameOrdering:'),
                          ('LABEL_METHOD', 'AKABAddressBook+Localizing.m', '- (NSString *)ak_localizedLabel:')]:
    text = source[name]
    pieces[key] = text[text.index(marker):text.index('\n@end')]
scaffold = (HERE / 'Baseline.m.in').read_text()
for key, text in pieces.items():
    scaffold = scaffold.replace('/*' + key + '*/', text)
    (out / (key.lower() + '.m.inc')).write_text(text)
(out / 'Baseline.m').write_text(scaffold)
clang = ['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-O2', '-Wno-deprecated-declarations']
frameworks = ['-framework', 'Foundation', '-framework', 'AppKit', '-framework', 'AddressBook', '-framework', 'Contacts']
run(clang + frameworks + [str(HERE / 'DetachedProof.m'), '-o', str(out / 'detached-proof')], out / 'proof-build.log')
run([str(out / 'detached-proof')], out / 'detached-proof.json')
proof = json.loads((out / 'detached-proof.json').read_text())
if not proof['qualified'] or proof['storeEntryAttempts'] or any(x['actual'] != x['expected'] for x in proof['results']):
    raise SystemExit('Native detached predicate qualification failed')
binary = out / 'legacy-baseline'
command = clang + ['-I', str(out), '-F', str(products)] + frameworks + [
    '-framework', 'UseCases', '-framework', 'Domain', '-Wl,-rpath,' + str(products),
    str(out / 'Baseline.m'), str(out / 'AKSIPURI.m'), str(out / 'AKSIPURIFormatter.m'),
    str(out / 'AKTelephoneNumberFormatter.m'), '-o', str(binary)]
run(command, out / 'baseline-build.log')
manifest['compileCommand'] = command
for probe in ('addressbook', 'bookalloc', 'recordalloc', 'aballoc', 'cnalloc'):
    run([str(binary), '--probe-' + probe], out / ('guard-' + probe + '.log'), expected=70)
results = []
for size in args.sizes:
    if size < 25:
        parser.error('Synthetic corpus requires at least 25 contacts')
    path = out / f'baseline-{size}.json'
    run([str(binary), str(size), str(path)], out / f'baseline-{size}.log')
    result = json.loads(path.read_text())
    if result['forbiddenStoreEntryAttempts'] or result['syntheticLockCalls'] != result['syntheticUnlockCalls']:
        raise SystemExit('Forbidden store entry or unbalanced synthetic lock calls')
    results.append({'contacts': size, 'queryWallMS': result['aggregateQueryWallMS'],
                    'tokenWarmWallMS': result['aggregateTokenWarmWallMS'],
                    'coldSyntheticConstructionMS': result['coldSyntheticConstructionMS']})
for name in ('UseCases', 'Domain'):
    manifest['frameworkSHA256'][str(products / f'{name}.framework' / name)] = sha(products / f'{name}.framework' / name)
for path in sorted(out.iterdir()):
    if path.is_file() and path.name != 'manifest.json':
        manifest['generatedSHA256'][path.name] = sha(path)
manifest['summary'] = results
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(results, indent=2))
