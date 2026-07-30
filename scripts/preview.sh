#!/bin/bash
# Live preview loop for FinderConvert: compiles FinderConvertApp.swift directly
# against prebuilt FinderConvertCore objects (no xcodebuild), wraps it in a
# minimal .app bundle in .local/preview/, and relaunches it whenever sources
# change. Full builds/installs remain manual via scripts/build-and-sign.sh.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/FinderConvertCore"
OUT="$ROOT/.local/preview"
APP_SRC="$ROOT/FinderConvert/FinderConvertApp.swift"
BUNDLE="$OUT/FinderConvertPreview.app"
BIN="$BUNDLE/Contents/MacOS/FinderConvertPreview"
LOG="$OUT/preview-build.log"

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

if [ ! -f "$BUNDLE/Contents/Info.plist" ]; then
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>FinderConvertPreview</string>
    <key>CFBundleIdentifier</key><string>com.finderconvert.preview</string>
    <key>CFBundleName</key><string>FinderConvertPreview</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
fi

build() {
    # Incremental core rebuild (fast no-op when core is unchanged)
    (cd "$CORE" && swift build 2>&1 | grep -E "error" ) && { echo "CORE BUILD FAILED"; return 1; }

    swiftc "$APP_SRC" \
        -parse-as-library \
        -I "$CORE/.build/debug/Modules" \
        -Xcc -fmodule-map-file="$CORE/Sources/CLame/module.modulemap" \
        -Xcc -fmodule-map-file="$CORE/Sources/CWebP/module.modulemap" \
        "$CORE"/.build/debug/FinderConvertCore.build/*.o \
        -L "$CORE/Sources/CLame" -lmp3lame \
        -L "$CORE/Sources/CWebP" -lwebp -lsharpyuv \
        -framework AVFoundation -framework WebKit -framework PDFKit -framework UserNotifications \
        -o "$BIN" 2> "$LOG"
    if [ $? -ne 0 ]; then
        echo "BUILD FAILED $(date +%H:%M:%S) — see $LOG:"
        grep -m 5 "error:" "$LOG"
        return 1
    fi
    # Core package resources (localized strings etc.)
    cp -R "$CORE/.build/debug/FinderConvertCore_FinderConvertCore.bundle" "$BUNDLE/Contents/Resources/" 2>/dev/null
    cp "$ROOT/FinderConvert/AppIcon.icns" "$BUNDLE/Contents/Resources/" 2>/dev/null
    codesign -f -s - "$BUNDLE" 2>/dev/null
    return 0
}

relaunch() {
    pkill -f FinderConvertPreview.app/Contents/MacOS 2>/dev/null
    sleep 0.3
    open "$BUNDLE"
    echo "RELAUNCHED $(date +%H:%M:%S)"
}

fingerprint() {
    stat -f %m "$APP_SRC"
    find "$CORE/Sources" -name '*.swift' -exec stat -f %m {} + 2>/dev/null | sort | tail -5
}

echo "Initial build..."
if build; then relaunch; else echo "initial build failed"; fi

LAST="$(fingerprint)"
while true; do
    sleep 2
    NOW="$(fingerprint)"
    if [ "$NOW" != "$LAST" ]; then
        LAST="$NOW"
        echo "CHANGE DETECTED $(date +%H:%M:%S), rebuilding..."
        if build; then relaunch; fi
    fi
done
