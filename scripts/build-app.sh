#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -m)" == arm64 ]] || { echo 'Build the Apple Silicon app on an arm64 Mac.' >&2; exit 1; }
VERSION="$(python3 scripts/version.py)"
OUTPUT_DIR="${APP_OUTPUT_DIR:-$PWD/dist/preview}"
BUILD_DIR="$PWD/.build/DerivedData-package"
APP="$OUTPUT_DIR/QuadcastRGBApp.app"
mkdir -p "$OUTPUT_DIR" .build
xcodebuild build -project QuadcastRGBApp/QuadcastRGBApp.xcodeproj \
    -scheme QuadcastRGBApp -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$BUILD_DIR" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$VERSION" \
    > .build/package-build.log 2>&1 || { tail -80 .build/package-build.log >&2; exit 1; }
rm -rf "$APP"
ditto "$BUILD_DIR/Build/Products/Release/QuadcastRGBApp.app" "$APP"
# Sign the embedded library first, then the app. Never deep-sign nested code.
SIGN_ARGS=(--force --sign "${SIGNING_IDENTITY:--}")
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
    if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then SIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN"); fi
fi
bash scripts/sign-sparkle.sh "$APP"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Frameworks/libhidapi.0.dylib"
codesign "${SIGN_ARGS[@]}" --entitlements QuadcastRGBApp/QuadcastRGBApp/QuadcastRGBApp.entitlements "$APP"
codesign --verify --deep --strict "$APP"
python3 scripts/verify-app.py "$APP"
echo "Built $APP"
