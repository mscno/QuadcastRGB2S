#!/bin/bash
set -euo pipefail

#───────────────────────────────────────────────────────────────────────────────
# package-dmg.sh — Build, sign, create DMG, notarize, and staple
#
# Usage:
#   ./QuadcastRGBApp/scripts/package-dmg.sh                # full pipeline
#   ./QuadcastRGBApp/scripts/package-dmg.sh --skip-notarize  # local / unsigned
#
# Environment (optional overrides):
#   DEVELOPER_ID    — signing identity  (default: auto-detect "Developer ID Application")
#   TEAM_ID         — Apple team ID     (default: from Xcode project)
#   APPLE_ID        — Apple ID email    (required for notarization)
#   APPLE_PASSWORD  — app-specific pwd  (required for notarization, or use keychain)
#───────────────────────────────────────────────────────────────────────────────

APP_NAME="QuadcastRGBApp"
VOLUME_NAME="QuadCast RGB"
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
XCODE_PROJECT="${PROJECT_DIR}/QuadcastRGBApp/QuadcastRGBApp.xcodeproj"
BUILD_DIR="${PROJECT_DIR}/.build/DerivedData-dmg"
STAGING_DIR="${PROJECT_DIR}/.build/dmg-staging"
OUTPUT_DMG="${PROJECT_DIR}/${APP_NAME}.dmg"

SKIP_NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
    esac
done

# ── Resolve signing identity ─────────────────────────────────────────────────

if [ -z "${DEVELOPER_ID:-}" ]; then
    DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
fi

if [ -z "${DEVELOPER_ID}" ]; then
    echo "⚠  No Developer ID Application certificate found."
    echo "   Building with ad-hoc signature (not distributable via Gatekeeper)."
    echo "   Install a Developer ID certificate or set DEVELOPER_ID env var."
    echo ""
    SIGN_ARGS=( --sign - )
    SKIP_NOTARIZE=true
else
    echo "Signing with: ${DEVELOPER_ID}"
    SIGN_ARGS=( --sign "${DEVELOPER_ID}" )
fi

# ── Resolve team ID ──────────────────────────────────────────────────────────

if [ -z "${TEAM_ID:-}" ]; then
    TEAM_ID=$(grep -o 'DEVELOPMENT_TEAM = [^;]*' "${XCODE_PROJECT}/project.pbxproj" | head -1 | awk '{print $3}' || true)
fi

# ── Step 1: Build release ────────────────────────────────────────────────────

echo ""
echo "═══ Building Release ═══"
BUILD_LOG="${PROJECT_DIR}/.build/xcodebuild.log"
mkdir -p "${PROJECT_DIR}/.build"
xcodebuild build \
    -project "${XCODE_PROJECT}" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${BUILD_DIR}" \
    DEVELOPMENT_TEAM="${TEAM_ID:-}" \
    > "${BUILD_LOG}" 2>&1 || { echo "Build failed:"; tail -20 "${BUILD_LOG}"; exit 1; }
tail -3 "${BUILD_LOG}"

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "ERROR: Build product not found at ${APP_PATH}" >&2
    exit 1
fi
echo "Built: ${APP_PATH}"

# ── Step 2: Re-sign the app bundle (deep) ───────────────────────────────────

echo ""
echo "═══ Code Signing ═══"
/usr/bin/codesign --force --deep --options runtime --timestamp \
    "${SIGN_ARGS[@]}" \
    --entitlements "${PROJECT_DIR}/QuadcastRGBApp/QuadcastRGBApp/QuadcastRGBApp.entitlements" \
    "${APP_PATH}"
echo "Signed: ${APP_PATH}"
/usr/bin/codesign -dv "${APP_PATH}" 2>&1 | head -3 || true

# ── Step 3: Create DMG with Applications symlink ─────────────────────────────

echo ""
echo "═══ Creating DMG ═══"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${OUTPUT_DMG}"
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "${OUTPUT_DMG}"

rm -rf "${STAGING_DIR}"
echo "Created: ${OUTPUT_DMG}"

# ── Step 4: Sign the DMG itself ──────────────────────────────────────────────

/usr/bin/codesign --force --timestamp "${SIGN_ARGS[@]}" "${OUTPUT_DMG}"
echo "DMG signed."

# ── Step 5: Notarize ─────────────────────────────────────────────────────────

if [ "${SKIP_NOTARIZE}" = true ]; then
    echo ""
    echo "═══ Skipping notarization ═══"
    echo "Done. DMG at: ${OUTPUT_DMG}"
    exit 0
fi

echo ""
echo "═══ Notarizing ═══"

if [ -z "${APPLE_ID:-}" ] || [ -z "${TEAM_ID:-}" ]; then
    echo "ERROR: Set APPLE_ID and TEAM_ID env vars for notarization." >&2
    echo "  APPLE_ID=you@example.com TEAM_ID=XXXXX ./scripts/package-dmg.sh" >&2
    exit 1
fi

# APPLE_PASSWORD can be a keychain reference like @keychain:AC_PASSWORD
# or a plain app-specific password. Create one at appleid.apple.com.
if [ -z "${APPLE_PASSWORD:-}" ]; then
    echo "Tip: store an app-specific password in Keychain:"
    echo "  xcrun notarytool store-credentials AC_PASSWORD --apple-id \$APPLE_ID --team-id \$TEAM_ID"
    echo ""
    echo "Attempting keychain profile 'AC_PASSWORD'..."
    NOTARY_AUTH=( --keychain-profile "AC_PASSWORD" )
else
    NOTARY_AUTH=( --apple-id "${APPLE_ID}" --team-id "${TEAM_ID}" --password "${APPLE_PASSWORD}" )
fi

xcrun notarytool submit "${OUTPUT_DMG}" "${NOTARY_AUTH[@]}" --wait

# ── Step 6: Staple ───────────────────────────────────────────────────────────

echo ""
echo "═══ Stapling ═══"
xcrun stapler staple "${OUTPUT_DMG}"

echo ""
echo "Done. Distributable DMG at: ${OUTPUT_DMG}"
