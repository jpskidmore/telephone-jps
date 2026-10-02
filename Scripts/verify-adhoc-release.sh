#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 '/path/to/jps Telephone.app'" >&2
    exit 64
fi
if [ "$(uname -s)" != Darwin ]; then
    echo "Ad-hoc release verification requires macOS and Xcode command-line tools." >&2
    exit 69
fi
for tool in codesign plutil python3 rg xcrun; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing prerequisite: $tool" >&2
        exit 69
    }
done
xcrun --find lipo >/dev/null

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=$1
main_binary="$app_path/Contents/MacOS/jps Telephone"
test -f "$main_binary" || { echo "Missing app executable: $main_binary" >&2; exit 66; }
verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/jps-telephone-verification.XXXXXX")
trap 'rm -rf "$verification_dir"' 0 HUP INT TERM

codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun lipo "$main_binary" -verify_arch arm64
plutil -convert json -o "$verification_dir/project.json" \
    "$project_root/Telephone.xcodeproj/project.pbxproj"
# The colon spelling emits an XML plist rather than human-readable output.
codesign -d --entitlements :- "$app_path" 2>/dev/null > "$verification_dir/entitlements.plist"
python3 - "$project_root" "$app_path" "$verification_dir" <<'PY'
import json
from pathlib import Path
import plistlib
import sys
root, app, temporary = map(Path, sys.argv[1:])
objects = json.loads((temporary / "project.json").read_text())["objects"]
targets = [o for o in objects.values()
           if o.get("isa") == "PBXNativeTarget" and o.get("name") == "Telephone"]
if len(targets) != 1:
    raise SystemExit("Expected exactly one Telephone application target")
configurations = objects[targets[0]["buildConfigurationList"]]["buildConfigurations"]
versions = {(str(objects[c]["buildSettings"]["MARKETING_VERSION"]),
             str(objects[c]["buildSettings"]["CURRENT_PROJECT_VERSION"]))
            for c in configurations}
if len(versions) != 1:
    raise SystemExit("Application target versions disagree across configurations")
version, build = versions.pop()

def read_dictionary(path):
    with path.open("rb") as source:
        result = plistlib.load(source)
    if not isinstance(result, dict):
        raise SystemExit(f"Expected plist dictionary: {path}")
    return result

info = read_dictionary(app / "Contents/Info.plist")
for key, value in {"CFBundleShortVersionString": version, "CFBundleVersion": build,
                   "CFBundleIdentifier": "uk.jpsit.telephone"}.items():
    if info.get(key) != value:
        raise SystemExit(f"App {key} differs from expected value {value}")
normal = read_dictionary(root / "Telephone/Telephone.entitlements")
if "com.apple.security.cs.disable-library-validation" in normal:
    raise SystemExit("Ad-hoc exception leaked into normal project entitlements")
if normal.get("com.apple.security.app-sandbox") is not True:
    raise SystemExit("Normal project sandbox entitlement is missing or disabled")
signed = read_dictionary(temporary / "entitlements.plist")
for key in ("com.apple.security.app-sandbox", "com.apple.security.cs.disable-library-validation"):
    if signed.get(key) is not True:
        raise SystemExit(f"Ad-hoc signature is missing true entitlement: {key}")
print(f"Application metadata matches project: {version} ({build})")
PY

set +e
rg -a -l '/Users/[A-Za-z0-9._-]+/' "$app_path"
path_status=$?
set -e
case "$path_status" in
    0) echo "Release bundle contains an absolute local user path" >&2; exit 1 ;;
    1) ;;
    *) echo "Could not inspect release bundle paths (rg status $path_status)" >&2; exit 1 ;;
esac

echo "Ad-hoc release verification passed (not a launch or notarization check)"
