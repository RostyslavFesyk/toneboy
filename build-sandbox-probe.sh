#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${TONEBAR_BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
swift build -c release --product toneboy-sandbox-probe --disable-sandbox --scratch-path "$BUILD_DIR"
APP="$PWD/../toneboy Sandbox Probe.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD_DIR/release/toneboy-sandbox-probe" "$APP/Contents/MacOS/toneboy-sandbox-probe"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName toneboy Sandbox Probe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName toneboy Sandbox Probe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable toneboy-sandbox-probe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.toneboy.sandboxprobe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$APP/Contents/Info.plist"
codesign --force --sign "${TONEBOY_SIGN_IDENTITY:--}" --options runtime \
    --entitlements Configuration/SandboxProbe.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
