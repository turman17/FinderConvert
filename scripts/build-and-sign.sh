#!/bin/bash
set -e

# Signing identity: set SIGNING_IDENTITY env var to your Developer ID for distribution.
# For development/testing, defaults to ad-hoc signing ("-").
#
# Examples:
#   Development (ad-hoc):  ./scripts/build-and-sign.sh
#   Distribution:          SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-and-sign.sh
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

# Build the project using xcodebuild (without signing during Xcode build to avoid provisioning profile requirements)
echo "Building FinderConvert..."
xcodebuild -project FinderConvert.xcodeproj \
           -scheme FinderConvert \
           -derivedDataPath .local/DerivedData \
           -configuration Debug \
           build

BUILT_APP=".local/DerivedData/Build/Products/Debug/FinderConvert.app"
BUILT_APPEX="${BUILT_APP}/Contents/PlugIns/FinderConvertActionExtension.appex"

# Copy the AppIcon into Resources
echo "Copying AppIcon..."
cp FinderConvert/AppIcon.icns "${BUILT_APP}/Contents/Resources/AppIcon.icns"

# Codesign with entitlements and hardened runtime.
# --options runtime enables the hardened runtime, required for notarization.
echo "Signing FinderConvertActionExtension with entitlements..."
codesign -f -s "$SIGNING_IDENTITY" \
    --entitlements FinderConvertActionExtension/FinderConvertActionExtension.entitlements \
    --options runtime \
    "$BUILT_APPEX"

echo "Signing FinderConvert with entitlements..."
codesign -f -s "$SIGNING_IDENTITY" \
    --entitlements FinderConvert/FinderConvert.entitlements \
    --options runtime \
    "$BUILT_APP"

# Install/Update in /Applications
echo "Installing to /Applications..."
rm -rf /Applications/FinderConvert.app
cp -R "$BUILT_APP" /Applications/FinderConvert.app

# Register with LaunchServices and PlugInKit
echo "Registering with LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/FinderConvert.app

echo "Registering and enabling plugin..."
pluginkit -a /Applications/FinderConvert.app/Contents/PlugIns/FinderConvertActionExtension.appex
pluginkit -e use -i com.finderconvert.app.ActionExtension

# Restart Finder
echo "Relaunching Finder..."
killall Finder

echo "Build and registration completed successfully! Now open /Applications/FinderConvert.app once."
