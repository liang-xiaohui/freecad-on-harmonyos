#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

OCCT_VERSION="${OCCT_VERSION:-7.8.1}"
OCCT_PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/$OCCT_VERSION/ohos/$ABI}"
BUILD="$CPP_LIB_ROOT/build/probes/occt-smoke/ohos-$ABI"
PREFIX="$CPP_LIB_ROOT/install/probes/occt-smoke/ohos/$ABI"

cmake_configure "$PROJECT_DIR/probes/occt-smoke" "$BUILD" "$PREFIX" \
    -DCMAKE_PREFIX_PATH="$OCCT_PREFIX" \
    -DCMAKE_FIND_ROOT_PATH="$NATIVE_SDK;$OCCT_PREFIX" \
    -DOpenCASCADE_DIR="$OCCT_PREFIX/lib/cmake/opencascade"

"$CMAKE_BIN" --build "$BUILD" -j "$JOBS"
echo "Built OCCT probe: $BUILD/occt-smoke"
