#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/jps Telephone.app" >&2
    exit 64
fi

app_path=$1
main_binary="$app_path/Contents/MacOS/jps Telephone"

codesign --verify --deep --strict --verbose=2 "$app_path"
test "$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")" = "2.0.3"
test "$(plutil -extract CFBundleVersion raw "$app_path/Contents/Info.plist")" = "154"
file "$main_binary" | rg -q 'Mach-O 64-bit executable arm64'

if rg -a -l '/Users/[A-Za-z0-9._-]+/' "$app_path" >/dev/null; then
    echo "Release bundle contains an absolute local user path" >&2
    exit 1
fi

verification_entitlements=$(mktemp "${TMPDIR:-/tmp}/jps-telephone-verification-entitlements.XXXXXX")
trap 'rm -f "$verification_entitlements"' EXIT HUP INT TERM

# `codesign --entitlements -` uses a human-readable format on current macOS;
# the legacy colon spelling still emits the XML plist required for inspection.
codesign -d --entitlements :- "$app_path" 2>/dev/null > "$verification_entitlements"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$verification_entitlements")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' "$verification_entitlements")" = "true"

if /usr/libexec/PlistBuddy -c \
    'Print :com.apple.security.cs.disable-library-validation' \
    "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/Telephone/Telephone.entitlements" \
    >/dev/null 2>&1; then
    echo "Ad-hoc exception leaked into normal project entitlements" >&2
    exit 1
fi

echo "Ad-hoc release verification passed"
