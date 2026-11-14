#!/bin/zsh
# builds the release zip: dist/claude-launcher.zip (one name for every version, so the readme's
# download link always takes the latest), signed with a secure timestamp,
# notarized and stapled, and prints its sha256 for the homebrew cask.
#   NOTARY_PROFILE  the notarytool keychain profile (default "claude-launcher"), stored once with
#                     xcrun notarytool store-credentials claude-launcher --key AuthKey.p8 --key-id ID --issuer UUID
#   or APPSTORE_CONNECT_API_KEY_PATH, APPSTORE_CONNECT_API_KEY_ID and APPSTORE_CONNECT_API_ISSUER_ID
#   SKIP_NOTARIZE   1 builds the zip without notarizing (not for publishing)
set -euo pipefail
cd "${0:A:h}/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="build/Claude Launcher.app"
DIST="dist"
ZIP="$DIST/claude-launcher.zip"

SIGN_TIMESTAMP=1 ./scripts/build.sh

mkdir -p "$DIST"
rm -f "$ZIP"

if [[ "${SKIP_NOTARIZE:-0}" != 1 ]]; then
  if [[ -n "${APPSTORE_CONNECT_API_KEY_PATH:-}" && -n "${APPSTORE_CONNECT_API_KEY_ID:-}" && -n "${APPSTORE_CONNECT_API_ISSUER_ID:-}" ]]; then
    CREDS=(--key "$APPSTORE_CONNECT_API_KEY_PATH" --key-id "$APPSTORE_CONNECT_API_KEY_ID" --issuer "$APPSTORE_CONNECT_API_ISSUER_ID")
  else
    CREDS=(--keychain-profile "${NOTARY_PROFILE:-claude-launcher}")
  fi
  echo "-> notarizing"
  UPLOAD="$DIST/upload.zip"
  ditto -c -k --keepParent "$APP" "$UPLOAD"
  xcrun notarytool submit "$UPLOAD" "${CREDS[@]}" --wait --timeout 30m
  rm -f "$UPLOAD"
  echo "-> stapling"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
fi

echo "-> packing $ZIP (version $VERSION)"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "sha256 $(shasum -a 256 "$ZIP" | awk '{print $1}')"
