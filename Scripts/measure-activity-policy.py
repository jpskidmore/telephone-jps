#!/usr/bin/env python3
"""Measure isolated ProcessInfo overhead; never launches Telephone or SIP.

Fresh processes, shared-cache warm-up, alternating AB/BA pairs. This does not measure real
App Nap, calling, physical sleep/wake, energy or battery life. See issue #66.
"""
import argparse, hashlib, json, platform, statistics, subprocess, tempfile
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('--seconds', type=float, default=2)
parser.add_argument('--pairs', type=int, default=3)
args = parser.parse_args()
if not .5 <= args.seconds <= 30 or not 3 <= args.pairs <= 10:
    parser.error('seconds must be 0.5–30 and pairs 3–10')
root = Path(__file__).resolve().parents[1]
source = root / 'Tests/ActivityPolicyMeasurementProbe.m'
production = root / 'Telephone/BackgroundActivityUserAgentEventTarget.swift'

def command(*parts):
    return subprocess.check_output(list(parts), text=True).strip()

with tempfile.TemporaryDirectory(prefix='jps-activity-policy-') as scratch:
    executable = Path(scratch) / 'activity-probe'
    compile_command = ['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                       '-mmacosx-version-min=15.6', str(source), '-framework', 'Foundation', '-o', str(executable)]
    subprocess.run(compile_command, check=True)
    def sample(policy, workload, seconds):
        return json.loads(command(str(executable), policy, workload, str(seconds)))
    for workload in ('idle', 'paced'):
        for policy in ('none', 'session'):
            sample(policy, workload, .2)
    samples = []
    for workload in ('idle', 'paced'):
        for pair in range(args.pairs):
            for policy in (('none', 'session') if pair % 2 == 0 else ('session', 'none')):
                result = sample(policy, workload, args.seconds)
                result['pair'] = pair + 1
                result['CPUPercent'] = 100 * (result['userCPUSeconds'] + result['systemCPUSeconds']) / result['wallSeconds']
                samples.append(result)
    summaries = []
    for workload in ('idle', 'paced'):
        for policy in ('none', 'session'):
            selected = [s for s in samples if s['workload'] == workload and s['policy'] == policy]
            summaries.append({'workload': workload, 'policy': policy,
                'CPUPercent': {'median': statistics.median(s['CPUPercent'] for s in selected),
                               'min': min(s['CPUPercent'] for s in selected), 'max': max(s['CPUPercent'] for s in selected)},
                'packageIdleWakeups': [s['packageIdleWakeups'] for s in selected],
                'interruptWakeups': [s['interruptWakeups'] for s in selected]})
    record = {'capturedAtUTC': datetime.now(timezone.utc).isoformat(),
        'sourceCommit': command('git', '-C', str(root), 'rev-parse', 'HEAD'),
        'metadata': {'macOS': command('sw_vers'), 'Xcode': command('xcodebuild', '-version'),
                     'machineModel': command('sysctl', '-n', 'hw.model'), 'architecture': platform.machine()},
        'method': {'secondsPerSample': args.seconds, 'pairsPerWorkload': args.pairs,
            'warmup': 'one discarded fresh-process 0.2-second sample per policy/workload; shared caches only',
            'ordering': 'fresh process per sample; AB/BA pairs; idle then paced; ProcessInfo initialised before both baselines',
            'CPU': 'getrusage RUSAGE_SELF timeval seconds+microseconds / monotonic wall duration; includes begin/end and snapshots',
            'wakeups': 'per-process package-idle and interrupt counter deltas; API failure aborts; zero does not establish per-counter coverage',
            'pacedWorkload': 'nanosleep at 200ms intervals; not SIP/ringing/audio or GUI polling'},
        'samples': samples, 'summaries': summaries,
        'sourceSHA256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in (source, Path(__file__).resolve(), production)},
        'limitations': ['CLI process overhead only; no Telephone App Nap eligibility or hidden AppKit state',
            'No actual SIP registration, incoming-call delivery, audio, provider or sleep/wake measurement',
            'No energy or battery measurement; near-zero differences do not establish equivalence or savings',
            'No app launch, real profile, Contacts, credentials, history or recordings',
            'Production policy unchanged; activity flag permits idle system sleep but is not a wake/readiness guarantee']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'samples': len(samples), 'output': str(args.output), 'summaries': summaries}, indent=2))
