# Bundled dependency sources and recording encoders

The app statically links recording support from LAME, libogg, libopusenc and Opus,
and SIP/TLS support from PJSIP and LibreSSL. The complete, unmodified upstream
archives are retained in `ThirdParty Sources/`; the PJSIP configuration and two
local patches are retained under `ThirdParty/PJSIP/`.

| Component | Included source archive | Included licence/notices |
| --- | --- | --- |
| LAME 3.100 | `lame-3.100.tar.gz` | `lame-3.100/COPYING` (GNU Library General Public License, version 2); also read `LICENSE` and file-level notices |
| libogg 1.3.6 | `libogg-1.3.6.tar.gz` | `libogg-1.3.6/COPYING` (BSD-style notice) |
| libopusenc 0.3 | `libopusenc-0.3.tar.gz` | `libopusenc-0.3/COPYING` (BSD-style notice) |
| Opus 1.6.1 | `opus-1.6.1.tar.gz` | `opus-1.6.1/COPYING`, file-level notices, and patent licence files referenced there |
| LibreSSL 4.3.2 | `libressl-4.3.2.tar.gz` | `libressl-4.3.2/COPYING` and notices retained in source files |
| PJSIP 2.17 | `pjproject-2.17.tar.gz` | `pjproject-2.17/COPYING`, its third-party subtree and file-level notices |

SHA-256 values for every included source archive and the LibreSSL detached
signature are authoritative in
[`ThirdParty Sources/SHA256SUMS.txt`](../ThirdParty%20Sources/SHA256SUMS.txt).
The committed binary inventory is separately pinned in
[`Scripts/vendor-archives.sha256`](../Scripts/vendor-archives.sha256).
Run `python3 Scripts/verify-dependency-manifests.py` from the repository root to
verify both manifests and resolve every project-linked archive.

Upstream source locations:

- LAME: <https://sourceforge.net/projects/lame/files/lame/3.100/>
- libogg: <https://downloads.xiph.org/releases/ogg/>
- libopusenc and Opus: <https://downloads.xiph.org/releases/opus/>
- LibreSSL: <https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/>
- PJSIP: <https://github.com/pjsip/pjproject/releases/tag/2.17>

See [the six-dependency build guide](../docs/DEPENDENCY_BUILDS.md) for staged
rebuild commands and their unverified native-build status. Hashes identify the
bundled snapshot; they do not independently authenticate an upstream publisher.

## Distribution notice checklist

`Telephone/Credits.rtf` is an application resource. It retains inherited notices
and now includes the complete `COPYING` text from LAME, libogg and libopusenc.
This Markdown inventory itself is not an application resource. The source
archives carry additional file-level and subcomponent notices; this summary does
not replace them or establish distribution compliance.

Before a binary release, inspect the actual application and source package for:

- the application's GPL `LICENSE` and original copyright notices
- the full matching source archives, the PJSIP patches and configuration, and
  build instructions for the distributed version
- all included component/subcomponent notices and licences, including inherited
  ASN.1, PJSIP codec/SRTP components, TLS and Opus patent notices
- `Contents/Resources/Credits.rtf`, including the recording-library notices
- the release's actual source/binary checksums and native validation report

The October 2026 cleanup did not build or inspect a new release ZIP, so packaging
and any additional source/relinking obligations must be checked before distribution.
