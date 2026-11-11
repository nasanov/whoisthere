#!/usr/bin/env bash
# Build, sign (Developer ID), notarize, and staple whoisthere.
# Produces build/whoisthere-<version>.dmg and .zip, plus build/whoisthere.rb (the Homebrew cask).
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

# DMG: the app next to an Applications shortcut, signed and notarized in its own right
# so Gatekeeper accepts the disk image itself, not just the app inside it.
DMG="build/whoisthere-${VERSION}.dmg"
STAGE=build/dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/whoisthere.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname whoisthere -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
codesign --sign "Developer ID Application" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"

# Homebrew cask for the nasanov/homebrew-tap repo. Points at the GitHub release asset,
# so upload the DMG to a release tagged v<version> before pushing the cask.
SHA=$(shasum -a 256 "$DMG" | awk '{ print $1 }')
cat > build/whoisthere.rb <<CASK
cask "whoisthere" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/nasanov/whoisthere/releases/download/v#{version}/whoisthere-#{version}.dmg"
  name "whoisthere"
  desc "Menu bar app showing which dev servers are running, with one-click stop"
  homepage "https://github.com/nasanov/whoisthere"

  depends_on macos: ">= :sonoma"

  app "whoisthere.app"

  zap trash: [
    "~/Library/Application Support/whoisthere",
    "~/Library/Preferences/com.nasanov.whoisthere.plist",
  ]
end
CASK

echo "Done:"
echo "  $DMG"
echo "  $FINAL"
echo "  build/whoisthere.rb (Homebrew cask)"
