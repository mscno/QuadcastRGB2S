#!/bin/bash
# Keep public submission IDs/statuses even if Apple's queue outlasts the wait.
set -euo pipefail
[[ $# == 3 && -f "$1" && "$2" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Usage: notarize.sh archive label diagnostics-directory' >&2; exit 1; }
: "${NOTARY_PROFILE:?Set a notarytool keychain profile.}"
ARCHIVE="$1"; LABEL="$2"; DIAGNOSTICS="$3"
TIMEOUT="${NOTARY_TIMEOUT:-90m}"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*[smh]?$ ]] || { echo 'Invalid NOTARY_TIMEOUT duration.' >&2; exit 1; }
mkdir -p "$DIAGNOSTICS"
AUTH_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then AUTH_ARGS+=(--keychain "$NOTARY_KEYCHAIN"); fi
SUBMITTED="$DIAGNOSTICS/$LABEL-notarization-submission.json"
RESPONSE="$DIAGNOSTICS/$LABEL-notarization-status.json"
xcrun notarytool submit "$ARCHIVE" "${AUTH_ARGS[@]}" --no-wait --no-progress --output-format json > "$SUBMITTED"
SUBMISSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$SUBMITTED")"
[[ "$SUBMISSION" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]] || { echo 'Missing or invalid notarization submission ID.' >&2; exit 1; }
echo "Submitted $LABEL to Apple: $SUBMISSION. Waiting up to $TIMEOUT."
if ! xcrun notarytool wait "$SUBMISSION" "${AUTH_ARGS[@]}" --timeout "$TIMEOUT" --no-progress --output-format json > "$RESPONSE"; then
    # Timeout doesn't cancel processing. Fetch the actual current status once;
    # Apple may have accepted it just as the wait expired.
    xcrun notarytool info "$SUBMISSION" "${AUTH_ARGS[@]}" --output-format json > "$RESPONSE"
fi
STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$RESPONSE")"
if [[ "$STATUS" != Accepted ]]; then
    if [[ "$STATUS" == Invalid || "$STATUS" == Rejected ]]; then
        xcrun notarytool log "$SUBMISSION" "${AUTH_ARGS[@]}" "$DIAGNOSTICS/$LABEL-notarization-log.json" || true
    fi
    echo "Apple has not accepted $LABEL (status: $STATUS; submission: $SUBMISSION). No release DMG will be published." >&2
    echo 'Check this submission with notarytool info before uploading it again.' >&2
    exit 1
fi
echo "Apple accepted $LABEL."
