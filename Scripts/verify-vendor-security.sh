#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

if [ "$(uname -s)" != Darwin ]; then
    echo "Full vendor verification requires macOS and Xcode command-line tools." >&2
    echo "Portable hash/inventory check: python3 Scripts/verify-dependency-manifests.py" >&2
    exit 69
fi
for tool in python3 rg strings xcrun; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing prerequisite: $tool" >&2
        exit 69
    }
done
xcrun --find lipo >/dev/null
python3 Scripts/verify-dependency-manifests.py

rg -q '^#define PJ_VERSION_NUM_MAJOR[[:space:]]+2$' ThirdParty/PJSIP/include/pj/config.h
rg -q '^#define PJ_VERSION_NUM_MINOR[[:space:]]+17$' ThirdParty/PJSIP/include/pj/config.h
rg -q 'LIBRESSL_VERSION_TEXT[[:space:]]+"LibreSSL 4\.3\.2"' ThirdParty/LibreSSL/include/openssl/opensslv.h

# A malformed/missing plist is an error, never proof of an absent entitlement.
python3 - <<'PY'
import plistlib
with open("Telephone/Telephone.entitlements", "rb") as source:
    entitlements = plistlib.load(source)
if not isinstance(entitlements, dict):
    raise SystemExit("Project entitlements must be a dictionary")
if entitlements.get("com.apple.security.app-sandbox") is not True:
    raise SystemExit("Project app sandbox entitlement is missing or disabled")
if "com.apple.security.cs.disable-library-validation" in entitlements:
    raise SystemExit("Library-validation exception is present in project entitlements")
PY

# Capture command status separately so a failed reader cannot look like no match.
opus_strings=$(mktemp "${TMPDIR:-/tmp}/jps-opus-strings.XXXXXX")
trap 'rm -f "$opus_strings"' 0 HUP INT TERM
strings ThirdParty/Opus/lib/libopus.a > "$opus_strings"
rg -q '^libopus 1\.6\.1$' "$opus_strings"

set +e
rg -n '/Users/|/private/tmp/' ThirdParty --glob '*.pc' --glob '*.la'
metadata_status=$?
set -e
case "$metadata_status" in
    0) echo "Bundled metadata contains machine-specific paths" >&2; exit 1 ;;
    1) ;; # No matches.
    *) echo "Could not inspect bundled metadata (rg status $metadata_status)" >&2; exit 1 ;;
esac

# Check every pinned archive, not only the networking subset. Hash/inventory
# validation above also ensures every project -l flag resolves to an archive.
while IFS= read -r entry; do
    archive=${entry#*  }
    xcrun lipo "$archive" -verify_arch arm64
done < Scripts/vendor-archives.sha256

echo "Vendor baseline passed (hashes, inventory, arm64, metadata, entitlements)"
echo "This is not a vulnerability scan or proof of source-to-binary reproducibility."
