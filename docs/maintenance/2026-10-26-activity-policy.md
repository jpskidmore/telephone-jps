# SIP activity policy investigation — 26 October 2026

Issue [#66](https://github.com/jpskidmore/telephone-jps/issues/66), baseline `d8ad20a10921727a306d9ef1b5b6ed476adb535e`.

## Decision: retain the existing policy

Keep the session activity while the SIP user agent is started. **No production policy or settings change is made.** There is no comparative real-app evidence that removing or narrowing it preserves incoming-call readiness in hidden/idle conditions. Actual provider and physical sleep/wake acceptance is explicitly pending by owner choice in #62. Changing a scheduling hint before that evidence is available would introduce a reliability trade-off without an established app-level benefit.

This is the issue's documented retention decision, supported by the bounded reproducible comparison below and an audited lifecycle. It does not show that the current policy is necessary, optimal, energy-neutral or best for battery life. No optimisation or battery-life gain is claimed. Reassess only if measured app-level cost and comparative readiness evidence justify a separate policy change; do not change polling and activity policy simultaneously when attributing any result.

## What the current source requests

`BackgroundActivityUserAgentEventTarget` acquires one `userInitiatedAllowingIdleSystemSleep` token after successful SIP start, holds it regardless of call/window state and ends it on stop or failed-start notification. Repeated start/stop notifications are idempotent. The fresh isolated production-source activity fixture passes failed start, duplicate successful start, failed restart and repeated stop/restart cases using an inert user agent and fake ProcessInfo. No SIP worker, real profile or hardware is started.

Apple explicitly says the option permits idle system sleep. The installed macOS 27 SDK defines it as user-initiated activity with the idle-system-sleep-disabled bit removed. The SDK describes hints that relax system heuristics, warns against unnecessarily extended activity and says preferences may override requests. This token is **not a wake guarantee or proof that incoming calls arrive during sleep**. Actual hidden-app App Nap behaviour is unmeasured. The SIP control worker's QoS is a separate policy and is unchanged.

## Reproducible bounded comparison

Run from the repository on the Mac:

```
python3 Scripts/measure-activity-policy.py /private/tmp/activity-comparison.json --pairs 4
```

The standalone Foundation process starts no application or SIP endpoint. Each sample has a fresh process, equal ProcessInfo initialisation before both baselines, two seconds of an idle or synthetic paced-sleep workload, and either no activity or the existing session option. Four alternating AB/BA pairs per workload give 16 samples; discarded short fresh-process runs warm shared caches only. The measured interval includes begin/end activity and counter-snapshot overhead. It is not a steady-state app profile. The paced workload is nanosleep every 200 ms, not ringing, audio, registration or the application's polling implementation.

CPU uses `getrusage(RUSAGE_SELF)` seconds/microseconds divided by monotonic wall duration. Wakeups are per-process `proc_pid_rusage` package-idle and interrupt counter deltas. An API failure aborts rather than becoming zero. Successful zero counters are observations, not proof that every counter is available or that no system work occurred. Individual samples, ranges, exact units, machine/OS/Xcode metadata and source hashes are in the adjacent JSON. An earlier exploratory run was discarded after review equalised ProcessInfo initialisation and clarified CPU units; only the final record is accepted.

Final machine: macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), arm64 MacBookPro17,1. `none` is a synthetic control, not an adopted candidate app policy.

| Synthetic workload | Policy | Median CPU | Range | Package-idle wakeups per sample | Interrupt wakeups per sample |
| --- | --- | ---: | ---: | --- | --- |
| idle | none | 0.002537% | 0.002289–0.002836% | [0, 0, 0, 0] | [1, 1, 1, 1] |
| idle | session | 0.022884% | 0.020795–0.028753% | [0, 0, 0, 0] | [1, 1, 1, 1] |
| paced | none | 0.017141% | 0.014906–0.019270% | [0, 0, 0, 0] | [10, 10, 10, 10] |
| paced | session | 0.036528% | 0.035433–0.042854% | [0, 1, 0, 0] | [10, 10, 10, 10] |

These short CLI results do not measure Telephone energy use, hidden AppKit/App Nap eligibility, SIP readiness, real audio, or sleep recovery. Similar or small differences prove neither equivalence nor savings. No energy-impact or battery measurement was taken.

## Real-app comparison matrix — pending, not synthetic passes

Any future candidate must be isolated from the owner's profile, identify its exact source/build and differ only in the activity policy. Use the same Mac, OS, power source and app/account configuration; record background load and run order. Capture equal 15-minute intervals, alternate baseline/candidate order and repeat at least three times. Record CPU seconds/percent, wakeups, Activity Monitor Energy Impact and App Nap state separately; the energy index is not a battery-life estimate. Provider/destination, permission and hardware details must be supplied before actual calls.

| Scenario | Capture and readiness evidence | Status |
| --- | --- | --- |
| Registered idle, visible then hidden | CPU/wakeups/energy/App Nap; registration retained | Pending #62 |
| Incoming ringing after idle, visible/hidden | Timestamp delivery; missed-call accounting | Pending #62 |
| Active incoming/outgoing call, visible/hidden | Call continuity and actual audio; CPU/wakeups | Pending #62 |
| Real system sleep then wake | Fixed sleep interval, registration recovery and subsequent incoming call | Pending #62 |
| Stop/restart after each state | Acquisition/release balance, no surviving/duplicate tokens | Synthetic balance passed; real-app checks pending #62 |

No alternate production policy is prototyped or adopted by this investigation. A synthetic timer pause must never be labelled system sleep, and synthetic callbacks must never be labelled delivered provider calls.

## Evidence and references

Final local comparison: `/private/tmp/jps-activity66-verified-20261026.json` and its log. Fresh token-balance build/run logs: `/private/tmp/jps-activity66-regression-build.log` and `...-run.log`. The existing fixture compiles `BackgroundActivityUserAgentEventTarget.swift` and `AKSIPUserAgentEventSource.swift` with the previously built unchanged UseCases/Domain frameworks and an inert user agent. Full app suites were not rerun because production source is unchanged. The supported deployment remains macOS 15.6.

Official references checked: [activity option](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/userinitiatedallowingidlesystemsleep), [begin/end activity](https://developer.apple.com/documentation/foundation/processinfo/beginactivity(options:reason:)), the installed `NSProcessInfo.h` option/heuristics declarations, and [Apple's XNU measurement interface notes](https://github.com/apple-oss-distributions/xnu/blob/main/doc/observability/recount.md). No cloud workflow, owner profile, Contacts/Keychain/history/recordings, provider call, physical-device test, installation or release was used. The next ranked source item is #67.
