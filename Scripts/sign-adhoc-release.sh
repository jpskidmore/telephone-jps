#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 source.app [signed-output.app]" >&2
    exit 64
fi

if [ "$(uname -s)" != Darwin ]; then
    echo "Ad-hoc release signing requires macOS." >&2
    exit 69
fi
for tool in codesign ditto xattr plutil; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing prerequisite: $tool" >&2
        exit 69
    }
done
test -x /usr/libexec/PlistBuddy || { echo "Missing prerequisite: PlistBuddy" >&2; exit 69; }

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
plutil -lint "$project_root/Telephone/Telephone.entitlements" \
    "$project_root/ReceiptValidation/ReceiptValidation.entitlements" >/dev/null
source_app_path=$1
app_path=${2:-$source_app_path}

if [ ! -d "$source_app_path/Contents/MacOS" ]; then
    echo "Not an application bundle: $source_app_path" >&2
    exit 66
fi

if [ "$app_path" != "$source_app_path" ]; then
    if [ -e "$app_path" ]; then
        echo "Refusing to overwrite signed output: $app_path" >&2
        exit 73
    fi
    ditto "$source_app_path" "$app_path"
fi

# Xcode and filesystem provenance can leave extended attributes on nested code.
# They are not part of the application and codesign correctly refuses bundles
# containing resource-fork or Finder metadata. A downloaded ZIP receives a new
# quarantine attribute from the browser after distribution.
xattr -cr "$app_path"

adhoc_entitlements=$(mktemp "${TMPDIR:-/tmp}/jps-telephone-adhoc-entitlements.XXXXXX")
trap 'rm -f "$adhoc_entitlements"' EXIT HUP INT TERM

# A Developer ID signs the app and its frameworks with one Team ID. Ad-hoc
# signatures have no Team ID, so hardened-runtime library validation otherwise
# terminates the app before main(). Keep the exception out of the normal project
# entitlements and add it only to this explicitly ad-hoc distribution signature.
cp "$project_root/Telephone/Telephone.entitlements" "$adhoc_entitlements"
/usr/libexec/PlistBuddy -c \
    'Add :com.apple.security.cs.disable-library-validation bool true' \
    "$adhoc_entitlements"

if [ -d "$app_path/Contents/Frameworks" ]; then
    find "$app_path/Contents/Frameworks" -type d -name '*.framework' -prune -print |
        while IFS= read -r framework_path; do
            codesign --force --sign - --options runtime "$framework_path"
        done
fi

xpc_path="$app_path/Contents/XPCServices/ReceiptValidation.xpc"
if [ -d "$xpc_path" ]; then
    codesign --force --sign - --options runtime \
        --entitlements "$project_root/ReceiptValidation/ReceiptValidation.entitlements" \
        "$xpc_path"
fi

codesign --force --sign - --options runtime \
    --entitlements "$adhoc_entitlements" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Ad-hoc release signing passed"
