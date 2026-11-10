#!/usr/bin/env bash
# Build, sign (Developer ID), notarize, and staple whoisthere.
# Requires: DEVELOPMENT_TEAM (Apple team ID) and NOTARY_PROFILE
# (keychain profile created once via `xcrun notarytool store-credentials`).
set -euo pipefail

: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM must be set to your Apple Developer team ID}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE must be set to your notarytool keychain profile name}"

cd "$(dirname "$0")/.."

ARCHIVE=build/whoisthere.xcarchive
EXPORT=build/export
APP="$EXPORT/whoisthere.app"
EXPORT_PLIST=build/ExportOptions.plist

mkdir -p build
rm -rf "$ARCHIVE" "$EXPORT" build/whoisthere.zip

xcodegen generate

xcodebuild archive \
  -scheme whoisthere \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM}</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$EXPORT_PLIST"

ditto -c -k --keepParent "$APP" build/whoisthere.zip

xcrun notarytool submit build/whoisthere.zip \
  --keychain-profile "$NOTARY_PROFILE" --wait

xcrun stapler staple "$APP"

# Fail the release unless the ticket is stapled and Gatekeeper accepts the app
# (set -e aborts on either non-zero exit).
xcrun stapler validate "$APP"
spctl -a -vv "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
FINAL="build/whoisthere-${VERSION}.zip"
rm -f "$FINAL"
ditto -c -k --keepParent "$APP" "$FINAL"

echo "Done: $FINAL"
