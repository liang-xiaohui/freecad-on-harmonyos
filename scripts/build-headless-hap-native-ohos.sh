#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

BUILD="$CPP_LIB_ROOT/build/freecad-hap-acceptance/ohos-$ABI"
PREFIX="$CPP_LIB_ROOT/install/freecad-hap-acceptance/ohos/$ABI"
OCCT_ROOT="${OCCT_ROOT:-$CPP_LIB_ROOT/install/occt/7.8.1/ohos/$ABI}"

cmake_configure "$PROJECT_DIR/entry/src/main/cpp" "$BUILD" "$PREFIX" \
    -DCPP_LIB_ROOT="$CPP_LIB_ROOT" \
    -DOCCT_ROOT="$OCCT_ROOT"
"$CMAKE_BIN" --build "$BUILD" -j "$JOBS"

ENTRY_LIBRARY="$BUILD/libfreecadacceptance.so"
[ -f "$ENTRY_LIBRARY" ] || {
    echo "错误：未产出 $ENTRY_LIBRARY" >&2
    exit 1
}

readelf -h "$ENTRY_LIBRARY" | grep -F 'Machine:' | grep -F 'AArch64' >/dev/null
runpath=$(readelf -d "$ENTRY_LIBRARY" | sed -n 's/.*Library runpath: \[\(.*\)\]/\1/p')
[ "$runpath" = '$ORIGIN' ] || {
    echo "错误：libfreecadacceptance.so RUNPATH=$runpath，期望 \$ORIGIN" >&2
    exit 1
}

echo "Built native HAP entry: $ENTRY_LIBRARY"
