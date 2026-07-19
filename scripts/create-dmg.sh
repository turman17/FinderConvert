#!/bin/bash
set -e

APP_NAME="FinderConvert"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-v${VERSION}"
DMG_OUTPUT="$HOME/Desktop/${DMG_NAME}.dmg"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BG_IMAGE="${PROJECT_DIR}/docs/dmg-background.tiff"

echo "Creating DMG for ${APP_NAME} v${VERSION}..."

# Clean
rm -f "$DMG_OUTPUT"

# Staging
STAGING="/tmp/${DMG_NAME}-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "/Applications/${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Build DMG
create-dmg \
    --volname "$APP_NAME" \
    --background "$BG_IMAGE" \
    --window-pos 200 200 \
    --window-size 660 400 \
    --icon-size 80 \
    --icon "${APP_NAME}.app" 190 180 \
    --icon "Applications" 470 180 \
    --hide-extension "${APP_NAME}.app" \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$STAGING"

rm -rf "$STAGING"

echo ""
echo "✅ DMG created: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
