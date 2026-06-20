#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/Ezshot.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_EXECUTABLE="$MACOS_DIR/Ezshot"
BUILD_PRODUCT="$ROOT_DIR/.build/debug/ezshot"
REBUILD=0

if [ "${1:-}" = "--rebuild" ]; then
    REBUILD=1
fi

cd "$ROOT_DIR"

if [ "$REBUILD" -eq 1 ] || [ ! -x "$APP_EXECUTABLE" ]; then
    env \
        CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache" \
        SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache" \
        swift build

    rm -rf "$APP_DIR"
    mkdir -p "$MACOS_DIR"
    cp "$BUILD_PRODUCT" "$APP_EXECUTABLE"

    cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Ezshot</string>
    <key>CFBundleIdentifier</key>
    <string>dev.local.ezshot</string>
    <key>CFBundleName</key>
    <string>Ezshot</string>
    <key>CFBundleDisplayName</key>
    <string>Ezshot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Ezshot</string>
</dict>
</plist>
PLIST

    codesign --force --deep --sign - --identifier dev.local.ezshot "$APP_DIR"
fi

osascript -e 'tell application id "dev.local.ezshot" to quit' >/dev/null 2>&1 || true
open "$APP_DIR"
