#!/bin/bash
# Build and install MacLocalASR as a proper .app bundle
# Usage: bash scripts/build_app.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$HOME/Applications/MacLocalASR.app"

echo "=== Building release ==="
swift build --package-path "$REPO_ROOT/src" -c release

echo "=== Creating .app bundle ==="
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

echo "=== App bundle created at $APP_DIR ==="
echo "Launch with: open $APP_DIR"
echo ""
echo "First launch requires microphone permission:"
echo "  System Settings → Privacy & Security → Microphone → Enable Mac Local ASR"