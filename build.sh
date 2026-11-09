#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${TONEBAR_BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
swift build -c release --disable-sandbox --scratch-path "$BUILD_DIR"
APP="${TONEBOY_APP_PATH:-$PWD/../toneboy.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/toneboy" "$APP/Contents/MacOS/toneboy"
cp Resources/toneboy.icns "$APP/Contents/Resources/toneboy.icns"
rm -f "$APP/Contents/Resources/Themes.metallib"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${TONEBOY_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$TONEBOY_SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built: $APP"
