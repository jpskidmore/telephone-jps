# Automatic call recording

jps Telephone includes optional automatic recording for connected calls.
Start with [current maintenance and release status](docs/MAINTENANCE.md) for the
installed and published baseline. Later source improvements do not update the
installed application until a separate verified build is delivered.

## Use

1. Open **jps Telephone → Settings… → General**.
2. Choose the recording format and, if wanted, a different destination folder.
3. Tick **Automatically record all calls (ensure everyone consents)**.
4. A connected call displays a red **● REC** indicator when recording starts successfully.
5. When a call ends, the stereo recording is finalised automatically.

The default folder is `Downloads/jps Telephone Recordings`. File names include the call date and time, direction, and remote party. Your microphone is the **left channel** and the remote party is the **right channel**.

The format choices deliberately keep technical settings out of the interface:

- **OGG — smallest files:** 24 kbps variable-bitrate Ogg Opus, with two uncoupled channels.
- **MP3 — good quality:** 64 kbps independent stereo MP3.
- **Source — no added loss:** lossless 16-bit stereo PCM WAV at the call audio sample rate. This preserves the audio delivered by PJSIP without another lossy encoding step; it is decoded call audio, rather than the original RTP codec packets.

The preference is off by default. Muted microphone audio is not added to the recording, and local microphone audio is disconnected from the recorder while the call is on local hold.

## Recording feedback — source improvement, 26 October 2026

The compact recording status opens details with the actual folder. **Starting**
means capture is not yet confirmed; **Failed** offers Retry using current
settings and Choose Folder; **REC** confirms capture, and **REC*** indicates a
fallback folder. Reveal Folder opens that actual destination. A retry cannot
recover earlier audio. Read [verification and limits](docs/maintenance/2026-10-26-recording-feedback.md).
This source improvement has not been installed or released.

## Finalisation and normal Quit

Each recording keeps its own destination-folder access
until its background conversion completes. A redial in the same window can start
and stop another recording while an earlier conversion is still pending. Normal
Quit waits asynchronously for SIP shutdown and registered recording completion;
large or queued recordings can therefore delay exit while the interface remains
responsive. Force Quit, a crash or power loss cannot provide that completion guarantee.

If conversion fails, the original tracks remain in a protected recovery job.
Use **jps Telephone → Recover Recordings…** for **Retry**, **Save Elsewhere…**,
**Show Recovery Files**, or **Later**. Read the [recovery guide](docs/RECORDING_RECOVERY.md)
for destination safety, retained files and Quit choices.

Published controlled checks do not establish real recording capture, physical
audio behaviour or sandbox grants. Record those manual outcomes separately on
the exact installed build; see [validation limits](docs/VALIDATION.md).

## Privacy and consent

Only enable recording when it is lawful and everyone who needs to consent has consented. Recording rules vary by location and circumstances.

## Build

The supported baseline targets Apple silicon and macOS 15.6 or later. Recorded SDK checks do not establish acceptance on every supported OS, including macOS 27.
For later authorised changes, follow [the maintenance entry point](docs/MAINTENANCE.md)
and [local validation, build and packaging requirements](docs/VALIDATION.md).
Use isolated synthetic tests, preserve user data and immutable releases, and
keep all builds local. This documentation update adds no build or test result.
