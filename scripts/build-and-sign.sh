#!/bin/bash
set -e

# Signing identity. A stable certificate identity keeps TCC permission
# grants (Full Disk Access, Desktop/Documents/Downloads access) valid across
# rebuilds; ad-hoc ("-") mints a new identity every build, which resets every
# granted permission on each reinstall.
#
# Auto-picks the first Apple Development certificate in the keychain.
# Override with SIGNING_IDENTITY (e.g. a Developer ID for distribution),
# or set SIGNING_IDENTITY="-" to force ad-hoc.
if [ -z "${SIGNING_IDENTITY:-}" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development/ {print $2; exit}')"
    SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
fi
echo "Signing identity: $SIGNING_IDENTITY"

# Build the project using xcodebuild (without signing during Xcode build to avoid provisioning profile requirements)
echo "Building FinderConvert..."
CONFIGURATION="${CONFIGURATION:-Release}"

xcodebuild -project FinderConvert.xcodeproj \
           -scheme FinderConvert \
           -derivedDataPath .local/DerivedData \
           -configuration "$CONFIGURATION" \
           build

BUILT_APP=".local/DerivedData/Build/Products/${CONFIGURATION}/FinderConvert.app"
BUILT_APPEX="${BUILT_APP}/Contents/PlugIns/FinderConvertActionExtension.appex"

# Strip symbol tables so the public build doesn't expose internal structure
echo "Stripping symbols..."
strip -rSTx "${BUILT_APP}/Contents/MacOS/FinderConvert" 2>/dev/null || true
strip -rSTx "${BUILT_APPEX}/Contents/MacOS/FinderConvertActionExtension" 2>/dev/null || true

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
