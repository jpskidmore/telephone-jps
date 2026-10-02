# Automatic call recording

This local jps Telephone build adds optional automatic recording for connected calls.

## Use

1. Open **jps Telephone > Preferences > General**.
2. Tick **Automatically record all calls (ensure everyone consents)**.
3. Connected calls will display a red **● REC** indicator.
4. Choose the recording format and, if wanted, a different destination folder.
5. When a call ends, the stereo recording is finalized automatically.

The default folder is `Downloads/jps Telephone Recordings`. File names include the call date and time, direction, and remote party. Your microphone is the **left channel** and the remote party is the **right channel**.

The format choices deliberately keep technical settings out of the interface:

- **OGG — smallest files:** 24 kbps variable-bitrate Ogg Opus, with two uncoupled channels.
- **MP3 — good quality:** 64 kbps independent stereo MP3.
- **Source — no added loss:** lossless 16-bit stereo PCM WAV at the call audio sample rate. This preserves the audio delivered by PJSIP without another lossy encoding step; it is decoded call audio, rather than the original RTP codec packets.

The preference is off by default. Muted microphone audio is not added to the recording, and local microphone audio is disconnected from the recorder while the call is on local hold.

## Finalization and normal Quit

In the current source, each recording keeps its own destination-folder access
until its background conversion completes. A redial in the same window can start
and stop another recording while an earlier conversion is still pending. Normal
Quit waits asynchronously for SIP shutdown and registered recording completion;
large or queued recordings can therefore delay exit while the interface remains
responsive. Force Quit, a crash or power loss cannot provide that completion guarantee.

If conversion fails, recoverable source tracks may remain in the private working
folder. The existing WAV-readiness retry and recovery behavior are retained.
These lifecycle changes are part of the [unreleased source cleanup](docs/releases/unreleased.md)
and still require native macOS validation before binary distribution.

## Privacy and consent

Only enable recording when it is lawful and everyone who needs to consent has consented. Recording rules vary by location and circumstances.

## Build

Application metadata remains version 2.0.3, build 154. The cleanup is an unreleased
source update, not a newly tested binary. Build the Release configuration on Apple
silicon with:

```sh
xcodebuild -project Telephone.xcodeproj -scheme Telephone -configuration Release -derivedDataPath build/DerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CLANG_MODULE_CACHE_PATH=build/ModuleCache build
```

Run the full native checks with `./Scripts/run-macos-validation.sh`; see
[validation prerequisites and limits](docs/VALIDATION.md).
