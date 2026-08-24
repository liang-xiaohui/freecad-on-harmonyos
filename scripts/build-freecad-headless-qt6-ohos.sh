#!/bin/sh
set -eu
if (set -o pipefail) 2>/dev/null; then
    set -o pipefail
fi
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"
FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
BUILD="$CPP_LIB_ROOT/build/freecad/$FREECAD_VERSION/ohos-$ABI-headless-qt6"
"$PROJECT_DIR/scripts/configure-freecad-headless-qt6-ohos.sh"
"$CMAKE_BIN" --build "$BUILD" -j "$JOBS" 2>&1 | tee "$BUILD/build.log"
echo "==> build done"
