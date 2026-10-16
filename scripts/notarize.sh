#!/usr/bin/env bash
#
# Notarizes a signed CapsJump.app, staples the ticket to it, proves the result the
# way Gatekeeper will judge it, and zips the stapled app for release. A zip can't carry a
# ticket, so the app inside it does: submit a zip of the app, staple the app, zip again.
# The order follows github.com/stigmer/stigmer's client-apps/desktop/scripts/
# macos-notarize-dmg.sh.
#
# Usage: scripts/notarize.sh <CapsJump.app> <out.zip>
#
# Environment:
#   APPLE_API_KEY          App Store Connect API key id
#   APPLE_API_ISSUER       App Store Connect issuer id
#   APPLE_API_KEY_PATH     path to the AuthKey_<id>.p8 file
#   APPLE_SIGNING_IDENTITY the identity both executables must carry
#   NOTARY_TIMEOUT         optional, default 30m; a hung notary fails the job

set -euo pipefail

fail() {
  echo "notarize: $*" >&2
  exit 1
}

[ "$(uname -s)" = Darwin ] || fail "notarytool is macOS-only"
[ $# -eq 2 ] || { echo "usage: notarize.sh <CapsJump.app> <out.zip>" >&2; exit 2; }
APP="$1"
ZIP="$2"
[ -d "$APP" ] || fail "app bundle not found: $APP"
for name in APPLE_API_KEY APPLE_API_ISSUER APPLE_API_KEY_PATH APPLE_SIGNING_IDENTITY; do
  [ -n "${!name:-}" ] || fail "$name is not set"
done
[ -f "$APPLE_API_KEY_PATH" ] || fail "notarization key not found: $APPLE_API_KEY_PATH"

# Both executables must carry the identity before anything is uploaded.
for exe in "$APP/Contents/MacOS/CapsJump" "$APP/Contents/Helpers/capsjump"; do
  codesign -dvv "$exe" 2>&1 | grep -qF "Authority=$APPLE_SIGNING_IDENTITY" \
    || fail "$exe is not signed by \"$APPLE_SIGNING_IDENTITY\""
done

notary_auth=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")
SUBMISSION="$(mktemp -d)/CapsJump-submission.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"

echo "notarize: submitting (timeout ${NOTARY_TIMEOUT:-30m})"
set +e
submit_log="$(xcrun notarytool submit "$SUBMISSION" "${notary_auth[@]}" --wait --timeout "${NOTARY_TIMEOUT:-30m}" 2>&1 | tee /dev/stderr)"
submit_exit=$?
set -e
submission_id="$(sed -nE 's/^ *id: ([0-9a-f-]+)$/\1/p' <<<"$submit_log" | head -n1)"
status="$(sed -nE 's/^ *status: (.*)$/\1/p' <<<"$submit_log" | tail -n1)"
[ -n "$submission_id" ] || fail "notarytool exited $submit_exit before a submission id was issued"
if [ "$status" != "Accepted" ] || [ "$submit_exit" -ne 0 ]; then
  echo "notarize: notary status is \"${status:-unknown}\"; fetching the log for $submission_id" >&2
  xcrun notarytool log "$submission_id" "${notary_auth[@]}" >&2 || true
  fail "notarization was not accepted"
fi

echo "notarize: stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
assessment="$(spctl --assess --type execute -vv "$APP" 2>&1 | tee /dev/stderr)"
grep -q 'source=Notarized Developer ID' <<<"$assessment" \
  || fail "Gatekeeper does not report the app as Notarized Developer ID"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "notarize: $ZIP holds the notarized, stapled app"
