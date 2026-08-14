#!/bin/bash
# Build, sign, and install MacLocalASR as a proper .app bundle
# Usage: bash scripts/build_app.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$HOME/Applications/MacLocalASR.app"
ENTITLEMENTS="$SCRIPT_DIR/MacLocalASR.entitlements"

echo "=== Building release ==="
swift build --package-path "$REPO_ROOT/src" -c release

echo "=== Creating .app bundle ==="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$REPO_ROOT/src/.build/release/MacLocalASR" "$APP_DIR/Contents/MacOS/MacLocalASR"

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>app.maclocalasr.MacLocalASR</string>
    <key>CFBundleName</key>
    <string>Mac Local ASR</string>
    <key>CFBundleExecutable</key>
    <string>MacLocalASR</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Record voice for local speech recognition</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
PLIST

echo "=== Code signing ==="
# Sign by certificate hash because keychains may contain duplicate display names.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')
if [ -z "$IDENTITY" ]; then
    echo "WARNING: No Apple Development identity found. Using ad-hoc signing."
    codesign --force \
        --sign - \
        --identifier app.maclocalasr.MacLocalASR \
        --entitlements "$ENTITLEMENTS" \
        "$APP_DIR"
else
    echo "Signing with: $IDENTITY"
    codesign --force \
        --sign "$IDENTITY" \
        --identifier app.maclocalasr.MacLocalASR \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "$APP_DIR"
fi

echo "=== Verifying signature ==="
codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1

if [ "${RESET_MICROPHONE_PERMISSION:-0}" = "1" ]; then
    echo "=== Resetting microphone permission ==="
    tccutil reset Microphone app.maclocalasr.MacLocalASR 2>/dev/null || true
fi

echo ""
echo "=== App bundle ready at $APP_DIR ==="
echo "Launch with: open $APP_DIR"
echo "First launch will prompt for microphone permission."
