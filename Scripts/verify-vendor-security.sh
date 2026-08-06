#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

rg -q '^#define PJ_VERSION_NUM_MAJOR[[:space:]]+2$' ThirdParty/PJSIP/include/pj/config.h
rg -q '^#define PJ_VERSION_NUM_MINOR[[:space:]]+17$' ThirdParty/PJSIP/include/pj/config.h
rg -q 'LIBRESSL_VERSION_TEXT[[:space:]]+"LibreSSL 4\.3\.2"' ThirdParty/LibreSSL/include/openssl/opensslv.h
strings ThirdParty/Opus/lib/libopus.a | rg -q '^libopus 1\.6\.1$'

if /usr/libexec/PlistBuddy -c \
    'Print :com.apple.security.cs.disable-library-validation' \
    Telephone/Telephone.entitlements >/dev/null 2>&1; then
    echo "Library validation remains disabled" >&2
    exit 1
fi

if rg -n '/Users/|/private/tmp/' ThirdParty --glob '*.pc' --glob '*.la'; then
    echo "Bundled metadata contains machine-specific paths" >&2
    exit 1
fi

for archive in \
    ThirdParty/PJSIP/lib/libpjsua-arm-apple-darwin.a \
    ThirdParty/PJSIP/lib/libpjsip-arm-apple-darwin.a \
    ThirdParty/PJSIP/lib/libpjmedia-arm-apple-darwin.a \
    ThirdParty/PJSIP/lib/libpjnath-arm-apple-darwin.a \
    ThirdParty/LibreSSL/lib/libssl.a \
    ThirdParty/LibreSSL/lib/libcrypto.a \
    ThirdParty/Opus/lib/libopus.a
do
    test -s "$archive"
    lipo "$archive" -verify_arch arm64
done

echo "Vendor security baseline passed"
