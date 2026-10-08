#!/usr/bin/env python3
"""Link current Debug URI objects; run isolated synthetic native parser regressions."""
import hashlib, json, pathlib, subprocess, os

import sys
repo = pathlib.Path(__file__).resolve().parents[1]
scratch = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else pathlib.Path('/private/tmp/jps-telephone-uri-regressions')
scratch.mkdir(parents=True, exist_ok=True)
derived = pathlib.Path(os.environ.get('JPS_DEBUG_DERIVED_DATA', str(repo/'build/v3-debug'))).resolve()
objects = derived/'Build/Intermediates.noindex/Telephone.build/Debug/Telephone.build/Objects-normal/arm64'
products = derived/'Build/Products/Debug'
sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
clang = subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
sources = ['AKSIPURI.o', 'AKSIPURIParser.o', 'AKNSString+PJSUA.o', 'URI+AKSIPURI.o', 'AccountControllerToAccountAdapter.o']
args = [clang, '-target', 'arm64-apple-macos15.6', '-isysroot', sdk,
        '-fobjc-arc', '-fmodules', '-DPJ_AUTOCONF=1', '-DPJ_IS_BIG_ENDIAN=0', '-DPJ_IS_LITTLE_ENDIAN=1', '-I'+str(repo/'Telephone'), '-I'+str(repo/'ThirdParty/PJSIP/include'),
        '-F'+str(products), str(repo/'Tests/SIPURIRegressionHarness.m'), *[str(objects/s) for s in sources],
        '-L'+str(repo/'ThirdParty/PJSIP/lib'), '-lpjsip-arm-apple-darwin', '-lpjlib-util-arm-apple-darwin', '-lpj-arm-apple-darwin',
        '-framework', 'UseCases', '-framework', 'Foundation', '-framework', 'Domain',
        '-Wl,-rpath,'+str(products), '-Wl,-rpath,/usr/lib/swift',
        '-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx',
        '-o', str(scratch/'uri_probe')]
subprocess.run(args, check=True)
result = subprocess.run([str(scratch/'uri_probe')], check=True, capture_output=True, text=True)
# pj_init writes a startup banner before logging is disabled.
payload = result.stdout[result.stdout.index('[\n'):]
data = json.loads(payload)
checks = [
    data[0]['productionNativeParsed'] == 1,
    data[0]['reference']['parsed'] == 1,
    data[1]['productionNativeParsed'] == 1 and data[1]['reference']['parsed'] == 1,
    data[2]['productionNativeParsed'] == 1 and data[2]['reference']['parsed'] == 1,
    data[1]['utf16Units'] == 42 and data[1]['utf8Bytes'] == 43,
    data[2]['utf16Units'] == 32 and data[2]['utf8Bytes'] == 36,
    data[3]['reference']['port'] == 5070 and data[3]['productionNativePort'] == 5070,
    data[3]['callAdapterString'] == 'sip:alice@example.invalid:5070;transport=tcp',
    data[3]['historyAdapterString'] == 'sip:alice@example.invalid:5070',
    data[3]['typedAKString'] == 'sip:alice@example.invalid:5070',
    data[4]['reference']['port'] == 5070 and data[4]['productionNativePort'] == 5070,
    data[4]['swiftParsedString'] == 'sip:alice@[2001:db8::1]:5070',
    data[4]['swiftReparsed']['parsed'] == 1,
    data[6]['port'] == 5070 and data[6]['copyPort'] == 5070,
    data[7]['historyMakeAdapterInput'] == 'sip:alice@example.invalid:5070' and data[7]['output'] == 'sip:alice@example.invalid:5070',
]
assert all(checks), checks
(scratch/'uri-results.json').write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n')
provenance = {'source': 'current Debug objects', 'sourceFiles': {f:hashlib.sha256((repo/'Telephone'/f).read_bytes()).hexdigest() for f in ['AKSIPURI.m','AKSIPURIParser.m','URI+AKSIPURI.swift','AccountControllerToAccountAdapter.m']}, 'objects': {s: hashlib.sha256((objects/s).read_bytes()).hexdigest() for s in sources}, 'pjsipVersion': '2.17.0', 'command': args, 'boundary': 'Private parser init + private pools + fake started object only. No PJSUA init/endpoint/transports/accounts/media/defaults/Keychain/UI/network.'}
provenance['reproductionAssertionsPassed'] = len(checks)
(scratch/'uri-provenance.json').write_text(json.dumps(provenance, indent=2)+'\n')
print(json.dumps({'passed':len(checks),'issues':[10,11,12],'noNativeSIP':True},indent=2))
