#!/bin/bash
# Build and verify a ZIP extraction before updating distribution.
set -euo pipefail
cd "$(dirname "$0")/.."
staging=$(mktemp -d "${TMPDIR:-/tmp}/COREType-Package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
CORETYPE_APP_OUTPUT="$staging/COREType.app" bash scripts/build-app.sh
ditto -c -k --sequesterRsrc --keepParent "$staging/COREType.app" "$staging/COREType-macOS.zip"
ditto -x -k "$staging/COREType-macOS.zip" "$staging/extracted"
codesign --verify --deep --strict "$staging/extracted/COREType.app"
cmp "$staging/COREType.app/Contents/Info.plist" "$staging/extracted/COREType.app/Contents/Info.plist"
cmp "$staging/COREType.app/Contents/MacOS/COREType" "$staging/extracted/COREType.app/Contents/MacOS/COREType"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staging/extracted/COREType.app/Contents/Info.plist")
architecture=$(lipo -archs "$staging/extracted/COREType.app/Contents/MacOS/COREType")
[[ "$architecture" == arm64 ]] || { printf 'The distribution installer currently supports arm64 only.\n' >&2; exit 1; }
(
    cd "$staging"
    shasum -a 256 COREType-macOS.zip > SHA256.txt
)
output="${CORETYPE_DISTRIBUTION_DIR:-$PWD/distribution}"
mkdir -p "$output"
for filename in COREType-macOS.zip SHA256.txt install-app.sh; do
    [[ ! -L "$output/$filename" ]] || { printf 'Refusing to replace a distribution symlink.\n' >&2; exit 1; }
done
cp "$staging/COREType-macOS.zip" "$output/COREType-macOS.zip"
cp "$staging/SHA256.txt" "$output/SHA256.txt"
cp scripts/install-app.sh "$output/install-app.sh"
printf 'Packaged COREType %s (%s): %s/COREType-macOS.zip\n' "$version" "$architecture" "$output"
