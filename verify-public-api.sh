#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/../toneboy.app"
codesign --verify --strict "$APP"
/usr/bin/python3 - "$APP/Contents/MacOS/toneboy" <<'PY'
from pathlib import Path
import sys
binary = Path(sys.argv[1]).read_bytes()
for marker in [b'TCCAccessPreflight', b'TCCAccessRequest', b'kTCCServiceAudioCapture', b'/PrivateFrameworks/TCC']:
    assert marker not in binary, marker
print('Main app signature and absence of private TCC markers verified.')
PY
