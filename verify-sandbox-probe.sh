#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/../toneboy Sandbox Probe.app"
codesign --verify --strict "$APP"
ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS"
/usr/bin/python3 - "$APP" "$ENTITLEMENTS" <<'PY'
from pathlib import Path
import plistlib, sys
app = Path(sys.argv[1])
entitlements = plistlib.loads(Path(sys.argv[2]).read_bytes())
assert entitlements == {
    'com.apple.security.app-sandbox': True,
    'com.apple.security.device.audio-input': True,
}, entitlements
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'app.toneboy.sandboxprobe'
assert info['NSAudioCaptureUsageDescription']
binary = (app/'Contents/MacOS/toneboy-sandbox-probe').read_bytes()
for marker in [b'TCCAccessPreflight', b'TCCAccessRequest', b'kTCCServiceAudioCapture', b'/PrivateFrameworks/TCC']:
    assert marker not in binary, marker
print('Sandbox entitlements, separate bundle identity, usage description, and absence of private TCC markers verified.')
print('This static audit does not prove capture permission or App Store eligibility.')
PY
