# Rebuilding the bundled dependencies

## Status and scope

The general six-dependency recipe below remains source-derived; the earlier
October cleanup did not execute it on macOS or establish byte-for-byte
reproduction of the bundled libraries. The narrow 3.0 CoreAudio UID driver
rebuild in section 7a was executed locally on 8 October 2026 and has separate
source/archive provenance and an inert native regression fixture. It does not
claim that all six libraries were rebuilt, that upstream signatures were
authenticated, or that physical hardware/provider behaviour was verified.

Use an Apple silicon Mac, macOS 15.6 or newer, a compatible full Xcode installation
with its command-line tools selected, Python 3, `make`, `patch`, and `pkg-config`.
Use checkout/staging paths without spaces because upstream Makefiles may not
support them; the existing `ThirdParty Sources` path is quoted below. Do not run
under Rosetta. No download, `sudo`, or system installation is needed by this recipe.

The committed sources are the input, rather than whatever a download URL currently
serves. `ThirdParty Sources/SHA256SUMS.txt` records SHA-256 for all six tarballs and
the LibreSSL detached signature. `Scripts/vendor-archives.sha256` separately pins
all 24 existing static libraries. Hash agreement detects changes to this snapshot;
it does not authenticate upstream authors or prove which sources produced a binary.

## 1. Verify inputs and prepare an isolated staging directory

Run from the repository root in one shell; the remaining sections use these variables:

```sh
set -eu
ROOT=$(pwd -P)
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
for tool in xcrun xcodebuild python3 make patch pkg-config tar; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
xcodebuild -version
python3 "$ROOT/Scripts/verify-dependency-manifests.py"
mkdir -p "$ROOT/build"
BUILD_ROOT=$(mktemp -d "$ROOT/build/dependencies.XXXXXX")
PREFIX="$BUILD_ROOT/install"
mkdir -p "$PREFIX"
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --find clang)
CXX=$(xcrun --find clang++)
export SDKROOT CC CXX
export MACOSX_DEPLOYMENT_TARGET=15.6
export CFLAGS="-arch arm64 -Os -mmacosx-version-min=15.6 -ffile-prefix-map=$ROOT=."
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch arm64 -mmacosx-version-min=15.6"
JOBS=${JOBS:-2}
for archive in opus-1.6.1 lame-3.100 libogg-1.3.6 libopusenc-0.3 libressl-4.3.2 pjproject-2.17; do
  tar -xzf "$ROOT/ThirdParty Sources/$archive.tar.gz" -C "$BUILD_ROOT"
done
printf 'Staging directory: %s\n' "$BUILD_ROOT"
```

Keep the source-manifest verifier's output, Xcode/SDK versions, compiler versions,
configuration logs, and final library hashes with any rebuilt distribution.
The included LibreSSL `.asc` can additionally be checked with `gpg --verify` only
after separately obtaining and verifying the upstream signing key. A matching
committed hash is not a substitute for signature authentication.

## 2. Opus 1.6.1

```sh
(cd "$BUILD_ROOT/opus-1.6.1"
 ./configure --build=aarch64-apple-darwin --host=aarch64-apple-darwin \
   --prefix="$PREFIX/Opus" --disable-shared --enable-static \
   --disable-extra-programs --disable-doc
 make -j "$JOBS"
 make install)
```

## 3. libogg 1.3.6

```sh
(cd "$BUILD_ROOT/libogg-1.3.6"
 ./configure --build=aarch64-apple-darwin --host=aarch64-apple-darwin \
   --prefix="$PREFIX/Ogg" --disable-shared --enable-static
 make -j "$JOBS"
 make install)
```

## 4. LAME 3.100

The bundled `config.guess` predates Apple silicon and can guess `x86_64` on modern
Darwin. Its `config.sub` accepts `aarch64`; the explicit build/host values below
avoid relying on that guess. The frontend executable is unnecessary for the app.

```sh
(cd "$BUILD_ROOT/lame-3.100"
 ./configure --build=aarch64-apple-darwin --host=aarch64-apple-darwin \
   --prefix="$PREFIX/LAME" --disable-shared --enable-static --disable-frontend
 make -j "$JOBS"
 make install)
```

## 5. libopusenc 0.3

The bundled `configure.ac` requires `opus >= 1.1` through `pkg-config`; use the
staged Opus installation. It does not require a separate libogg pkg-config entry.
The application project nevertheless explicitly links the bundled libogg archive.

```sh
(cd "$BUILD_ROOT/libopusenc-0.3"
 PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR="$PREFIX/Opus/lib/pkgconfig" \
 ./configure --build=aarch64-apple-darwin --host=aarch64-apple-darwin \
   --prefix="$PREFIX/OpusEnc" --disable-shared --enable-static \
   --disable-examples --disable-doc
 make -j "$JOBS"
 make install)
```

## 6. LibreSSL 4.3.2

```sh
(cd "$BUILD_ROOT/libressl-4.3.2"
 ./configure --build=aarch64-apple-darwin --host=aarch64-apple-darwin \
   --prefix="$PREFIX/LibreSSL" --with-openssldir=/etc/ssl \
   --disable-shared --enable-static --disable-tests
 make -j "$JOBS"
 make install)
```

This follows the existing dependency configuration, which disables LibreSSL's
upstream tests. It is not a claim that those tests have passed. `/etc/ssl` sets a
library default; this recipe does not install into or alter the system trust store.
The app's existing bundled trust list is unchanged.

## 7. PJSIP 2.17

Reuse the exact checked-in configuration and both patches. The `arm-apple-darwin`
host name preserves the archive suffix expected by `Telephone.xcodeproj`;
`-arch arm64` selects the actual object architecture. Do not substitute an
`aarch64-...` suffix without updating the application's linker references.

```sh
(cd "$BUILD_ROOT/pjproject-2.17"
 cp "$ROOT/ThirdParty/PJSIP/include/pj/config_site.h" pjlib/include/pj/config_site.h
 for patch_file in coreaudio_dev.patch sock_qos_darwin.patch; do
   patch --dry-run -p0 < "$ROOT/ThirdParty/PJSIP/patches/$patch_file"
   patch -p0 < "$ROOT/ThirdParty/PJSIP/patches/$patch_file"
 done
 ./configure --prefix="$PREFIX/PJSIP" \
   --with-opus="$PREFIX/Opus" --with-ssl="$PREFIX/LibreSSL" \
   --disable-video --disable-libyuv --disable-libwebrtc \
   --host=arm-apple-darwin CFLAGS="$CFLAGS -DNDEBUG" CXXFLAGS="$CXXFLAGS -DNDEBUG"
 make dep
 make -j "$JOBS" lib
 make install)
```

## 7a. 3.0 native CoreAudio UID helper and local archive rebuild

The checked-in `coreaudio_dev.patch` now adds `jps_coreaudio_device_uid` alongside
the historical CoreAudio volume-capability changes. The helper validates the
current PJSIP global device index, resolves its real driver-table/local-device
record, and reads the physical device UID from that record's CoreAudio
`AudioDeviceID`. It checks driver identity, indices, missing/invalid UID results
and buffer capacity, balancing the returned CFString reference on every path.
The caller serialises the query with native enumeration/refresh on the SIP/audio
control worker. No display-name guess or separately enumerated array position
is used to identify duplicate devices.

For 3.0, only `coreaudio_dev.o` in
`ThirdParty/PJSIP/lib/libpjmedia-audiodev-arm-apple-darwin.a` was rebuilt/replaced.
The other PJSIP and codec/TLS archives were retained. The executed source came
from the pinned `pjproject-2.17.tar.gz` with the committed patches applied and the
checked-in configured PJSIP headers. The local compile used Apple clang, the
macOS 27.0 SDK, arm64 target and macOS 15.6 deployment target:

```sh
jpsRepoRoot=$(pwd -P)
jpsSdkPath=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-macos15.6 -isysroot "$jpsSdkPath" \
  -Os -DNDEBUG -DPJ_AUTOCONF=1 -DPJ_IS_BIG_ENDIAN=0 -DPJ_IS_LITTLE_ENDIAN=1 \
  -DPJMEDIA_AUDIO_DEV_HAS_COREAUDIO=1 -I ThirdParty/PJSIP/include \
  "-ffile-prefix-map=$jpsRepoRoot=." \
  -c build/v3-pjsip-source/pjproject-2.17/pjmedia/src/pjmedia-audiodev/coreaudio_dev.m \
  -o build/v3-pjsip-source/coreaudio_dev.o
xcrun ar -r ThirdParty/PJSIP/lib/libpjmedia-audiodev-arm-apple-darwin.a \
  build/v3-pjsip-source/coreaudio_dev.o
xcrun ranlib ThirdParty/PJSIP/lib/libpjmedia-audiodev-arm-apple-darwin.a
```

This command requires an already extracted/patched source tree at the stated
path. To prepare a clean tree, extract the pinned tarball into
`build/v3-pjsip-source`, apply both committed patches from that tree using `-p0`,
and verify its source hash before replacing an archive member. Preserve the
original archive first. The explicit `PJMEDIA_AUDIO_DEV_HAS_COREAUDIO=1` flag is
required: compiling with the driver disabled is not a valid helper rebuild.
Check the archive contains one `coreaudio_dev.o`, the defined
`_jps_coreaudio_device_uid` symbol and the defined `_pjmedia_coreaudio_factory`
symbol, then verify arm64 architecture and the reviewed manifest hash.

The reviewed 8 October snapshot records:

| Artifact | SHA-256 |
|---|---|
| Patched `coreaudio_dev.m` | `3800e3342cf5282330701db01676a8fa3b35ea73ce190d61ce1f3c25f3e99e93` |
| Updated `libpjmedia-audiodev-arm-apple-darwin.a` | `5f748d0db746d208bfd01190441adfaa67d27ec087fec4cffc9c9d2663c172e9` |

`Scripts/vendor-archives.sha256` pins the reviewed archive. Dependency verification
passes 7 source-manifest files, 24 static archives and 21 project link references;
these are inventory/hash counts, not test cases or a vulnerability assessment.
Keep actual compiler commands, SDK versions and provenance when rebuilding with
a different compiler; do not overwrite expected hashes merely to make checks pass.

The native fixture compiles the exact driver source obtained by extracting the
tarball and applying the current patch:

```sh
python3 Tests/run_coreaudio_identity.py --output build/native-uid-fixture
```

It writes `patch.log`, `compile.log`, `results.log` and `provenance.json` with exact
compile arguments and source/harness hashes. The current fixture passed 18
assertions using real private factory/device table structures from that same
translation unit; only the subsystem getter and CoreAudio property query are
substituted. It does not initialise PJSUA, query physical devices, open audio or
register SIP. Domain/mapping tests separately cover duplicate names, UID selection
and legacy-name fallback. Final controlled hosted validation passed. The reviewed
archive is included in the locally built, signed, packaged and installed
**3.0/build 161**, published as GitHub Latest from
`6363412d56e2bc142a54058321b7873a69068c62`. The
[completed release verification](releases/3.0-verification.md) links the pinned
archive to the exact source/app packages and seven uploaded asset hash/size
matches. Preserve v2.1.8 and v3.0 tags/assets unchanged. The native fixture remains
bounded synthetic evidence, not physical-device testing or complete
source-to-binary reproducibility evidence.

## 8. Inspect staged outputs before replacing bundled files

```sh
python3 - "$PREFIX" <<'PYTHON'
from pathlib import Path
import hashlib
import subprocess
import sys
archives = sorted(Path(sys.argv[1]).glob("*/lib/*.a"))
if not archives:
    raise SystemExit("No staged archives found")
for archive in archives:
    subprocess.run(["xcrun", "lipo", str(archive), "-verify_arch", "arm64"], check=True)
    print(hashlib.sha256(archive.read_bytes()).hexdigest(), archive)
PYTHON
```

The architecture check stops on any failed archive. The app expects these six
installations under
`ThirdParty/{Opus,Ogg,LAME,OpusEnc,LibreSSL,PJSIP}`. This recipe deliberately stops
at staging. Replacing the bundled headers/libraries is a separate reviewed vendor
change, not a necessary step for building from the existing checkout.

When making that change:

1. Preserve the original archives, licences, notices, PJSIP patches and
   `config_site.h`; inspect any changed generated headers and required link flags
2. Copy only reviewed installation outputs. Do not publish generated `.pc` or
   `.la` metadata with private checkout/staging paths
3. Inspect `git status --ignored` and explicitly add reviewed files when needed:
   `.gitignore` excludes several vendor directories, including new files there
4. Update `Scripts/vendor-archives.sha256` only after reviewing the rebuilt binary
   inventory; do not replace expected hashes merely to silence a failing check
5. Run `Scripts/verify-vendor-security.sh` and `Scripts/run-macos-validation.sh`,
   then the separate [release checks](VALIDATION.md) before distributing a binary

Matching architecture and passing tests still do not establish byte-for-byte
reproducibility. Preserve actual build evidence instead of treating this recipe as
proof that a rebuild has already succeeded.
