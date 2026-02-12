#!/bin/sh
set -eu

# Resolve hidapi library directory via pkg-config first, then common Homebrew locations.
HIDAPI_DIR="$(pkg-config --variable=libdir hidapi 2>/dev/null || true)"
if [ -z "${HIDAPI_DIR}" ]; then
    for candidate in /opt/homebrew/lib /usr/local/lib; do
        if [ -d "${candidate}" ]; then
            HIDAPI_DIR="${candidate}"
            break
        fi
    done
fi

if [ -z "${HIDAPI_DIR}" ]; then
    echo "Embed libhidapi: unable to resolve hidapi library directory" >&2
    exit 1
fi

HIDAPI_LIB=""
for lib in "${HIDAPI_DIR}/libhidapi.0.dylib" "${HIDAPI_DIR}/libhidapi.dylib"; do
    if [ -f "${lib}" ]; then
        HIDAPI_LIB="${lib}"
        break
    fi
done

if [ -z "${HIDAPI_LIB}" ]; then
    echo "Embed libhidapi: hidapi dylib not found in ${HIDAPI_DIR}" >&2
    exit 1
fi

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "${FRAMEWORKS_DIR}"
DEST_LIB="${FRAMEWORKS_DIR}/libhidapi.0.dylib"
if [ -e "${DEST_LIB}" ]; then
    chmod u+w "${DEST_LIB}" 2>/dev/null || true
    rm -f "${DEST_LIB}" 2>/dev/null || true
fi
cp -f "${HIDAPI_LIB}" "${DEST_LIB}"

# Homebrew dylibs may already carry an ad-hoc signature. Remove it before
# mutating load commands to avoid signature invalidation warnings.
if /usr/bin/codesign -dv "${DEST_LIB}" >/dev/null 2>&1; then
    /usr/bin/codesign --remove-signature "${DEST_LIB}" >/dev/null 2>&1 || true
fi

# Make the embedded dylib discoverable via @rpath.
/usr/bin/install_name_tool -id @rpath/libhidapi.0.dylib "${DEST_LIB}"

BINARY="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH}"
OLD_NAME="$(/usr/bin/otool -L "${BINARY}" | awk '/libhidapi/ {print $1; exit}')"
if [ -n "${OLD_NAME}" ]; then
    /usr/bin/install_name_tool -change "${OLD_NAME}" @rpath/libhidapi.0.dylib "${BINARY}"
fi

DEBUG_DYLIB="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_FOLDER_PATH}/${PRODUCT_NAME}.debug.dylib"
if [ -f "${DEBUG_DYLIB}" ]; then
    OLD_DEBUG_NAME="$(/usr/bin/otool -L "${DEBUG_DYLIB}" | awk '/libhidapi/ {print $1; exit}')"
    if [ -n "${OLD_DEBUG_NAME}" ]; then
        /usr/bin/install_name_tool -change "${OLD_DEBUG_NAME}" @rpath/libhidapi.0.dylib "${DEBUG_DYLIB}"
    fi
fi

# In CI we disable code signing. Locally sign with the resolved identity,
# otherwise fall back to ad-hoc for unsigned debug runs.
if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
    if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
        /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${DEST_LIB}"
    else
        /usr/bin/codesign --force --sign - "${DEST_LIB}"
    fi
fi
