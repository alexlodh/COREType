#!/bin/bash
# Install the packaged app for the current user without a compiler or sudo.
set -euo pipefail
fail() { printf 'COREType: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'This installer requires macOS.'
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || fail 'The prebuilt app requires an Apple silicon Mac.'
os_major=$(sw_vers -productVersion | cut -d . -f 1)
[[ "$os_major" -ge 14 ]] || fail 'COREType requires macOS 14 or later.'

script_dir=$(cd "$(dirname "$0")" && pwd)
default_archive="$script_dir/../distribution/COREType-macOS.zip"
if [[ -f "$script_dir/COREType-macOS.zip" ]]; then default_archive="$script_dir/COREType-macOS.zip"; fi
archive="${1:-$default_archive}"
[[ "$#" -le 1 ]] || fail 'Usage: bash scripts/install-app.sh [path/to/COREType-macOS.zip]'
[[ -f "$archive" ]] || fail "App ZIP not found: $archive"
checksum_file="$(dirname "$archive")/SHA256.txt"
[[ -f "$checksum_file" ]] || fail "Checksum file not found: $checksum_file"
expected=$(awk '$2 == "COREType-macOS.zip" { print $1 }' "$checksum_file")
[[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'SHA256.txt must contain one COREType-macOS.zip checksum.'
actual=$(shasum -a 256 "$archive" | awk '{ print $1 }')
[[ "$actual" == "$expected" ]] || fail 'ZIP checksum mismatch. Download the ZIP and SHA256.txt again.'

install_dir="${CORETYPE_INSTALL_DIR:-$HOME/Applications}"
destination="$install_dir/COREType.app"
[[ ! -L "$destination" ]] || fail "Refusing to replace a symlink: $destination"
if [[ -e "$destination" ]]; then
    [[ -d "$destination" ]] || fail "The install destination is not an app directory: $destination"
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)
    [[ "$identifier" == org.sasha.coretype ]] || fail "The existing app is not COREType: $destination"
    if ps -axo comm= | awk -v executable="$destination/Contents/MacOS/COREType" '$0 == executable { found=1 } END { exit(found ? 0 : 1) }'; then
        fail 'Quit COREType before installing an update.'
    fi
fi

staging=$(mktemp -d "${TMPDIR:-/tmp}/COREType-Install.XXXXXX")
install_staging=''
previous_app=''
trash_bucket=''
installed=false
replacement_moved=false
cleanup() {
    if [[ "$installed" != true ]]; then
        if [[ "$replacement_moved" == true && -e "$destination" ]]; then
            mv "$destination" "$install_staging/failed-COREType.app"
        fi
        if [[ -n "$previous_app" && -d "$previous_app" ]]; then
            mv "$previous_app" "$destination"
            rmdir "$trash_bucket"
        fi
    fi
    rm -rf "$staging"
    if [[ -n "$install_staging" ]]; then rm -rf "$install_staging"; fi
}
trap cleanup EXIT

# Accept only the expected bundle and Apple's optional ZIP metadata directory.
zipinfo -1 "$archive" > "$staging/entries.txt"
while IFS= read -r entry; do
    case "$entry" in
        /*|../*|*/../*|*/..) fail 'The ZIP contains an unsafe path.' ;;
    esac
    case "$entry" in
        COREType.app/*|__MACOSX/*) ;;
        *) fail "Unexpected ZIP entry: $entry" ;;
    esac
done < "$staging/entries.txt"
ditto --qtn -x -k "$archive" "$staging"
app="$staging/COREType.app"
[[ -d "$app" && ! -L "$app" ]] || fail 'The ZIP does not contain a COREType app bundle.'
[[ -x "$app/Contents/MacOS/COREType" ]] || fail 'The app executable is missing or has lost its executable permission.'
# Preserve download quarantine explicitly when present. macOS may normalize
# its metadata when the extracted bundle is copied to the install directory.
archive_quarantine=$(xattr -p com.apple.quarantine "$archive" 2>/dev/null || true)
if [[ -n "$archive_quarantine" ]]; then xattr -w com.apple.quarantine "$archive_quarantine" "$app"; fi
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
[[ "$identifier" == org.sasha.coretype ]] || fail 'The ZIP contains a different application.'
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")

mkdir -p "$install_dir"
install_staging=$(mktemp -d "$install_dir/.COREType-Install.XXXXXX")
ditto --qtn "$app" "$install_staging/COREType.app"
codesign --verify --deep --strict "$install_staging/COREType.app"
if [[ -e "$destination" ]]; then
    mkdir -p "$HOME/.Trash"
    trash_bucket=$(mktemp -d "$HOME/.Trash/COREType-Previous.XXXXXX")
    previous_app="$trash_bucket/COREType.app"
    mv "$destination" "$previous_app"
fi
mv "$install_staging/COREType.app" "$destination"
replacement_moved=true
codesign --verify --deep --strict "$destination"
installed=true
printf 'Installed COREType %s: %s\n' "$version" "$destination"
if [[ -n "$previous_app" ]]; then printf 'Previous app moved to Trash: %s\n' "$previous_app"; fi
printf 'Launch with: open "%s"\n' "$destination"
