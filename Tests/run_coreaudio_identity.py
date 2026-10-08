#!/usr/bin/env python3
"""Compile/run the exact patched native CoreAudio UID helper with inert boundaries."""
from pathlib import Path
import argparse, hashlib, json, subprocess, tarfile

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, type=Path)
qa = parser.parse_args().output.resolve()
qa.mkdir(parents=True, exist_ok=True)
with tarfile.open(repo / 'ThirdParty Sources/pjproject-2.17.tar.gz') as archive:
    source = archive.extractfile('pjproject-2.17/pjmedia/src/pjmedia-audiodev/coreaudio_dev.m').read()
target = qa / 'pjmedia/src/pjmedia-audiodev/coreaudio_dev.m'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(source)
patch = subprocess.run(['patch', '-p0'], input=(repo / 'ThirdParty/PJSIP/patches/coreaudio_dev.patch').read_text(),
                       text=True, cwd=qa, capture_output=True)
(qa / 'patch.log').write_text(patch.stdout + patch.stderr)
patch.check_returncode()
clang = subprocess.check_output(['xcrun', '--find', 'clang'], text=True).strip()
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
command = [clang, '-target', 'arm64-apple-macos15.6', '-isysroot', sdk, '-fobjc-arc', '-fblocks',
           '-DPJ_AUTOCONF=1', '-DPJMEDIA_AUDIO_DEV_HAS_COREAUDIO=1', '-DNDEBUG',
           '-I' + str(repo / 'ThirdParty/PJSIP/include'), '-DJPS_COREAUDIO_SOURCE="' + str(target) + '"',
           str(repo / 'Tests/CoreAudioIdentityHarness.m'), '-o', str(qa / 'CoreAudioIdentityHarness')]
for library in ['PJSIP', 'Opus', 'LibreSSL']:
    command += list(map(str, (repo / 'ThirdParty' / library / 'lib').glob('*.a')))
command += ['-Wl,-dead_strip']
for framework in ['Foundation', 'CoreAudio', 'AudioToolbox', 'AudioUnit', 'Security', 'SystemConfiguration']:
    command += ['-framework', framework]
compiled = subprocess.run(command, text=True, capture_output=True)
(qa / 'compile.log').write_text(compiled.stdout + compiled.stderr)
if compiled.returncode:
    print(compiled.stderr)
compiled.check_returncode()
result = subprocess.run([str(qa / 'CoreAudioIdentityHarness')], text=True, capture_output=True)
(qa / 'results.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end='')
result.check_returncode()
(qa / 'provenance.json').write_text(json.dumps({
    'compileArguments': command,
    'patchedSourceSha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    'harnessSha256': hashlib.sha256((repo / 'Tests/CoreAudioIdentityHarness.m').read_bytes()).hexdigest(),
    'boundary': 'Exact patched driver source; real private factory records/table from same translation unit. Only subsystem getter and CoreAudio property query substituted; no hardware or SDK startup.'
}, indent=2) + '\n')
