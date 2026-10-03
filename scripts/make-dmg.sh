#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 ]]; then
    echo 'Usage: bash scripts/make-dmg.sh /path/to/QuadcastRGBApp.app /path/to/output.dmg' >&2
    exit 1
fi
APP="$1"
DMG="$2"
[[ -d "$APP/Contents/MacOS" ]] || { echo 'App bundle does not exist.' >&2; exit 1; }
command -v dmgbuild >/dev/null || { echo 'Install dmgbuild==1.6.7 in a Python venv first; see docs/RELEASING.md.' >&2; exit 1; }
[[ ! -e "$DMG" ]] || { echo "Refusing to replace existing disk image: $DMG" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
mkdir -p "$(dirname "$DMG")"
dmgbuild -s scripts/dmg-settings.py -D "app=$APP" 'QuadCast RGB' "$DMG"
hdiutil verify "$DMG"
# Packaging must not add Finder/resource-fork attributes that break the app signature.
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quadcast-dmg-check.XXXXXX")"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then hdiutil detach "$MOUNT_DIR" >/dev/null || return; fi
    rmdir "$MOUNT_DIR"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG" >/dev/null
MOUNTED=1
codesign --verify --deep --strict "$MOUNT_DIR/QuadcastRGBApp.app"
[[ -L "$MOUNT_DIR/Applications" && "$(readlink "$MOUNT_DIR/Applications")" == /Applications ]]
cmp -s "$APP/Contents/MacOS/QuadcastRGBApp" "$MOUNT_DIR/QuadcastRGBApp.app/Contents/MacOS/QuadcastRGBApp"
echo "Built $DMG (notarization is handled by release.sh)"
