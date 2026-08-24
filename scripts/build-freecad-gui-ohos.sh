#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
BUILD="$CPP_LIB_ROOT/build/freecad/$FREECAD_VERSION/ohos-$ABI-gui"

"$PROJECT_DIR/scripts/configure-freecad-gui-ohos.sh"
cmake_build_install "$BUILD"
echo "Built and installed GUI FreeCAD under $CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-gui"
