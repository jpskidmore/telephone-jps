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

## Privacy and consent

Only enable recording when it is lawful and everyone who needs to consent has consented. Recording rules vary by location and circumstances.

## Build

The app is version 2.0.3, build 154. Build the Release configuration for Apple silicon with:

```sh
xcodebuild -project Telephone.xcodeproj -scheme Telephone -configuration Release -derivedDataPath build/DerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CLANG_MODULE_CACHE_PATH=build/ModuleCache build
```
