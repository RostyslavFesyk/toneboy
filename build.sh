#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${TONEBAR_BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
swift build -c release --disable-sandbox --scratch-path "$BUILD_DIR"
APP="$PWD/../toneboy.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/toneboy" "$APP/Contents/MacOS/toneboy"
rm -f "$APP/Contents/Resources/Themes.metallib"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built: $APP"
