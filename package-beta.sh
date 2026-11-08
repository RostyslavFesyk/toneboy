#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Rostyslav Fesyk
set -euo pipefail
cd "$(dirname "$0")"
: "${TONEBOY_SIGN_IDENTITY:?Set TONEBOY_SIGN_IDENTITY to your Developer ID Application certificate name.}"
: "${TONEBOY_NOTARY_PROFILE:?Set TONEBOY_NOTARY_PROFILE to an existing notarytool Keychain profile.}"
if [[ "$TONEBOY_SIGN_IDENTITY" != 'Developer ID Application: '* ]]; then
    echo 'A Developer ID Application certificate is required for this direct-distribution beta.' >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -F -- "\"$TONEBOY_SIGN_IDENTITY\"" >/dev/null; then
    echo 'The selected signing identity is not available in your Keychain.' >&2
    exit 1
fi
# Validate credentials before building or uploading anything. Credentials stay in Keychain.
xcrun notarytool history --keychain-profile "$TONEBOY_NOTARY_PROFILE" >/dev/null
BETA_DIR="${TONEBOY_BETA_DIR:-$PWD/../beta}"
mkdir -p "$BETA_DIR"
export TONEBOY_APP_PATH="$BETA_DIR/toneboy.app"
export TONEBOY_SIGN_IDENTITY
bash build.sh
codesign --verify --strict "$TONEBOY_APP_PATH"
UPLOAD_ZIP="$BETA_DIR/toneboy-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$TONEBOY_APP_PATH" "$UPLOAD_ZIP"
xcrun notarytool submit "$UPLOAD_ZIP" --keychain-profile "$TONEBOY_NOTARY_PROFILE" \
    --wait --output-format json > "$BETA_DIR/notarization-result.json"
/usr/bin/python3 - "$BETA_DIR/notarization-result.json" <<'PY'
import json, sys
from pathlib import Path
report = json.loads(Path(sys.argv[1]).read_text())
if report.get('status') != 'Accepted':
    raise SystemExit('Apple has not accepted this build. Inspect notarization-result.json; do not distribute it.')
PY
xcrun stapler staple "$TONEBOY_APP_PATH"
xcrun stapler validate "$TONEBOY_APP_PATH"
spctl --assess --type execute --verbose=2 "$TONEBOY_APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$TONEBOY_APP_PATH" "$BETA_DIR/toneboy-beta.zip"
echo "Signed, notarized beta: $BETA_DIR/toneboy-beta.zip"
