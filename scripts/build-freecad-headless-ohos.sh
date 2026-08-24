#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
BUILD="$CPP_LIB_ROOT/build/freecad/$FREECAD_VERSION/ohos-$ABI-headless"
PREFIX="$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-headless"
PYTHON_ROOT="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI}"
YAML_CPP_PREFIX="${YAML_CPP_PREFIX:-$CPP_LIB_ROOT/install/yaml-cpp/0.8.0/ohos/$ABI}"

if [ ! -f "$PYTHON_ROOT/lib/python3.11/lib-dynload/_socket.cpython-311-aarch64-linux-ohos.so" ]; then
    CPP_LIB_ROOT="$CPP_LIB_ROOT" "$PROJECT_DIR/scripts/build-python-runtime-ohos.sh"
fi
if [ ! -f "$YAML_CPP_PREFIX/lib/cmake/yaml-cpp/yaml-cpp-config.cmake" ]; then
    CPP_LIB_ROOT="$CPP_LIB_ROOT" "$PROJECT_DIR/scripts/build-yaml-cpp-ohos.sh"
fi
export PYTHON_ROOT

CPP_LIB_ROOT="$CPP_LIB_ROOT" FREECAD_VERSION="$FREECAD_VERSION" \
    "$PROJECT_DIR/scripts/prepare-freecad-source.sh"
CPP_LIB_ROOT="$CPP_LIB_ROOT" FREECAD_VERSION="$FREECAD_VERSION" \
    "$PROJECT_DIR/scripts/configure-freecad-headless-ohos.sh"
cmake_build_install "$BUILD"

CPP_LIB_ROOT="$CPP_LIB_ROOT" FREECAD_VERSION="$FREECAD_VERSION" \
    "$PROJECT_DIR/scripts/audit-freecad-headless-ohos.sh"

echo "Built and installed headless FreeCAD: $PREFIX"
