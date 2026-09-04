#!/bin/bash
# Cut a release: stamp the version, build and sign, produce the zip + dmg,
# compute the cask sha256, and (with gh installed) publish a GitHub release.
#
# Usage: scripts/release.sh 1.1.0
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version, e.g. 1.1.0>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Stamping version $VERSION"
plutil -replace CFBundleShortVersionString -string "$VERSION" FinderConvert/Info.plist
plutil -replace CFBundleShortVersionString -string "$VERSION" FinderConvertActionExtension/Info.plist
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" FinderConvert.xcodeproj/project.pbxproj

echo "==> Building and signing"
bash scripts/build-and-sign.sh

BUILT_APP="/Applications/FinderConvert.app"
OUT="$ROOT/.local/release"
mkdir -p "$OUT"
ZIP="$OUT/FinderConvert-v$VERSION.zip"

echo "==> Packaging $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$BUILT_APP" "$ZIP"

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

echo ""
echo "Artifact:  $ZIP"
echo "sha256:    $SHA256"
echo ""
echo "Cask stanza for homebrew-tap/Casks/finderconvert.rb:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""
echo ""

if command -v gh >/dev/null 2>&1; then
    read -r -p "Create GitHub release v$VERSION and upload the zip? [y/N] " REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        gh release create "v$VERSION" "$ZIP" \
            --title "FinderConvert $VERSION" \
            --generate-notes
        echo "Release published. Update the cask in your homebrew-tap with the sha256 above."
    fi
else
    echo "gh CLI not found — create the GitHub release manually and attach the zip."
fi
