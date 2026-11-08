#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${TONEBAR_BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
# Tests use isolated preferences and a fake engine: no permission prompts,
# real output changes, or sleep commands are performed.
swift test --disable-sandbox --scratch-path "$BUILD_DIR"
