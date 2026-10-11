#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift-env.sh build --product COREType -c release
binary_dir=$(bash scripts/swift-env.sh build -c release --show-bin-path)
output="${CORETYPE_APP_OUTPUT:-$PWD/dist/COREType.app}"
# Assemble the complete bundle in a fresh local directory. Never overlay an
# older release: removed source files and resources must not survive a rebuild.
staging=$(mktemp -d /tmp/COREType-Build.XXXXXX)
trap 'rm -rf "$staging"' EXIT
app="$staging/COREType.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/COREType" "$app/Contents/MacOS/COREType"
cp -R Sources/COREType/Resources/. "$app/Contents/Resources/"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/modules"
xcrun swiftc -module-cache-path .build/modules scripts/Icon.swift -o .build/IconMaker
.build/IconMaker .build/COREType.iconset
python3 scripts/pack_icon.py .build/COREType.iconset "$app/Contents/Resources/COREType.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>COREType</string>
<key>CFBundleDisplayName</key><string>COREType</string>
<key>CFBundleIdentifier</key><string>org.sasha.coretype</string>
<key>CFBundleExecutable</key><string>COREType</string>
<key>CFBundleIconFile</key><string>COREType</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Independent offline typing app. CORE Econ excerpts: CC BY-NC-ND 4.0; attribution included.</string>
</dict></plist>
PLIST
printf 'APPL????' > "$app/Contents/PkgInfo"
# File Provider may attach FinderInfo to new .app folders. Remove only
# signing-incompatible Finder metadata from this generated bundle.
# Preserve quarantine and all other security-related attributes.
python3 - "$app" <<'PY'
import os, subprocess, sys
root = sys.argv[1]
paths = [root]
for directory, dirs, files in os.walk(root):
    paths += [os.path.join(directory, item) for item in dirs + files]
for path in paths:
    attributes = subprocess.check_output(['xattr', path], text=True).splitlines()
    for attribute in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
        if attribute in attributes: subprocess.run(['xattr', '-d', attribute, path], check=True)
PY
codesign --force --sign - "$app"
codesign --verify --strict "$app"
# Preserve the previous generated app until the replacement is fully verified.
# A misconfigured output must never trash an unrelated file or application.
if [[ -e "$output" ]]; then
    python3 - "$output" <<'PY'
from pathlib import Path
import plistlib
import sys

output = Path(sys.argv[1])
if output.is_symlink() or not output.is_dir():
    raise SystemExit('Refusing to replace a non-directory or symlink app output: ' + str(output))
try:
    info = plistlib.loads((output / 'Contents/Info.plist').read_bytes())
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit('Refusing to replace an unrecognized app output: ' + str(error))
if info.get('CFBundleIdentifier') != 'org.sasha.coretype':
    raise SystemExit('Refusing to replace an app that is not COREType: ' + str(output))
PY
    xcrun swiftc -module-cache-path .build/modules scripts/trash-items.swift -o .build/TrashItems
    mkdir -p work
    cleanup_record="work/build-cleanup-$(date +%Y%m%d-%H%M%S)-$$.json"
    .build/TrashItems "$output" > "$cleanup_record"
    printf 'Previous bundle moved to Trash: %s\n' "$cleanup_record"
fi
mkdir -p "$(dirname "$output")"
mv "$app" "$output"
codesign --verify --strict "$output"
printf '\nBuilt: %s\n' "$output"
