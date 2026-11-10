#!/bin/bash
# Regenerates the README screenshots in docs/screenshots/.
# Renders the real menu with sample data (debug screenshot mode), then stages it on a
# macOS-style desktop with headless Chrome.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
RAW="$(mktemp -d)"
OUT=docs/screenshots

xcodegen generate >/dev/null
xcodebuild -scheme whoisthere -configuration Debug -derivedDataPath build build -quiet
# A generic home folder keeps your username out of the sample paths.
CFFIXED_USER_HOME=/Users/you WHOISTHERE_SCREENSHOTS="$RAW" build/Build/Products/Debug/whoisthere.app/Contents/MacOS/whoisthere

mkdir -p "$OUT"
for theme in light dark; do
  for shot in menu menu-details; do
    # Canvas height = panel height + menu bar + margin, so the menu fills the frame.
    h=$(sips -g pixelHeight "$RAW/$shot-$theme.png" | awk '/pixelHeight/ { print int($2 / 2) + 90 }')
    "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
      --window-size=820,"$h" --virtual-time-budget=2000 \
      --screenshot="$OUT/$shot-$theme.png" \
      "file://$PWD/scripts/screenshots/frame.html?theme=$theme&shot=$RAW/$shot-$theme.png" 2>/dev/null
  done
done
rm -rf "$RAW"
ls -1 "$OUT"
