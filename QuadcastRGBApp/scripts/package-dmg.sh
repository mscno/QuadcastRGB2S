#!/bin/bash
# Compatibility entry point; explicit preview vs distributable release.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# == 1 && "$1" == --skip-notarize ]]; then
    APP_OUTPUT_DIR="$PWD/dist/preview" bash scripts/build-app.sh
    bash scripts/make-dmg.sh "$PWD/dist/preview/QuadcastRGBApp.app" "$PWD/dist/preview/QuadcastRGB2S-preview.dmg"
    echo 'Local preview only. Run scripts/release.sh for signed, notarized distribution.'
elif [[ $# == 0 ]]; then
    exec bash scripts/release.sh
else
    echo 'Usage: package-dmg.sh [--skip-notarize]' >&2
    exit 1
fi
