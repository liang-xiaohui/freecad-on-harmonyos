#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
SRC="$CPP_LIB_ROOT/sources/freecad/$FREECAD_VERSION"
BUILD="$CPP_LIB_ROOT/build/freecad/$FREECAD_VERSION/ohos-$ABI-gui"
PREFIX="$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-gui"
QT_PREFIX="${QT_PREFIX:-$CPP_LIB_ROOT/install/qt/5.12.12-src/ohos/$ABI}"
COIN_PREFIX="${COIN_PREFIX:-$CPP_LIB_ROOT/install/coin/4.0.0/ohos/$ABI}"
BOOST_PREFIX="${BOOST_PREFIX:-$CPP_LIB_ROOT/install/boost/1.86.0/ohos/$ABI}"
EIGEN_PREFIX="${EIGEN_PREFIX:-$CPP_LIB_ROOT/install/eigen/3.4.1/ohos/$ABI}"
XERCES_PREFIX="${XERCES_PREFIX:-$CPP_LIB_ROOT/install/xerces-c/3.2.4/ohos/$ABI}"
OCCT_PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/7.8.1/ohos/$ABI}"
YAML_CPP_PREFIX="${YAML_CPP_PREFIX:-$CPP_LIB_ROOT/install/yaml-cpp/0.8.0/ohos/$ABI}"
FMT_SOURCE="${FMT_SOURCE:-$CPP_LIB_ROOT/sources/fmt/9.1.0}"
PYTHON_ROOT="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI}"
PYTHON_HOST_BIN="${PYTHON_HOST_BIN:-$NATIVE_SDK/llvm/python3/bin/python3}"
ICU_LIBRARY="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos/libicu.so"
OPENGL_LIBRARY="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos/libGLv4.so"
OPENGL_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include"

[ -f "$SRC/CMakeLists.txt" ] || {
    echo "FreeCAD source is missing. Run $PROJECT_DIR/scripts/prepare-freecad-source.sh" >&2
    exit 1
}
[ -f "$PYTHON_ROOT/include/python3.11/Python.h" ] || {
    echo "Python development files are missing under $PYTHON_ROOT" >&2
    exit 1
}
[ -x "$PYTHON_HOST_BIN" ] || {
    echo "Python host interpreter is missing: $PYTHON_HOST_BIN" >&2
    exit 1
}
[ -f "$COIN_PREFIX/lib/libCoin.so.4.0.0" ] || {
    echo "Coin3D is missing under $COIN_PREFIX" >&2
    exit 1
}
[ -f "$OPENGL_LIBRARY" ] || {
    echo "OHOS libGLv4 is missing: $OPENGL_LIBRARY" >&2
    exit 1
}

PREFIX_PATH="$QT_PREFIX;$COIN_PREFIX;$BOOST_PREFIX;$EIGEN_PREFIX;$XERCES_PREFIX;$OCCT_PREFIX;$YAML_CPP_PREFIX;$PYTHON_ROOT"
FIND_ROOT_PATH="$NATIVE_SDK;$QT_PREFIX;$COIN_PREFIX;$BOOST_PREFIX;$EIGEN_PREFIX;$XERCES_PREFIX;$OCCT_PREFIX;$YAML_CPP_PREFIX;$PYTHON_ROOT"
# Sketcher's Python binding generation requires a host SWIG executable, which
# is not part of the current build environment.

cmake_configure "$SRC" "$BUILD" "$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX_PATH" \
    -DCMAKE_FIND_ROOT_PATH="$FIND_ROOT_PATH" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
    -DCMAKE_INSTALL_RPATH='$ORIGIN' \
    -DOpenCASCADE_DIR="$OCCT_PREFIX/lib/cmake/opencascade" \
    -DFREECAD_QT_VERSION=5 \
    -DQt5_DIR="$QT_PREFIX/lib/cmake/Qt5" \
    -DCoin_DIR="$COIN_PREFIX/lib/cmake/Coin-4.0.0" \
    -DOPENGL_gl_LIBRARY="$OPENGL_LIBRARY" \
    -DOPENGL_INCLUDE_DIR="$OPENGL_INCLUDE_DIR" \
    -DOHOS_ALLOW_UNDEFINED_SYMBOLS=ON \
    -DPython3_ROOT_DIR="$PYTHON_ROOT" \
    -DPython3_EXECUTABLE="$PYTHON_HOST_BIN" \
    -DPython3_LIBRARY="$PYTHON_ROOT/lib/libpython3.11.so" \
    -DPython3_INCLUDE_DIR="$PYTHON_ROOT/include/python3.11" \
    -DICU_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include" \
    -DICU_UC_LIBRARY_RELEASE="$ICU_LIBRARY" \
    -DICU_I18N_LIBRARY_RELEASE="$ICU_LIBRARY" \
    -DPYCXX_INCLUDE_DIRS="$SRC/src/3rdParty/PyCXX" \
    -DPYCXX_SOURCE_DIR="$SRC/src/3rdParty/PyCXX/CXX" \
    -DFETCHCONTENT_SOURCE_DIR_FMT="$FMT_SOURCE" \
    -DINSTALL_TO_SITEPACKAGES=OFF \
    -DBUILD_GUI=ON \
    -DFREECAD_CHECK_PIVY=OFF \
    -DFREECAD_USE_SHIBOKEN=OFF \
    -DFREECAD_USE_PYSIDE=OFF \
    -DFREECAD_USE_3DCONNEXION_LEGACY=OFF \
    -DBUILD_FEM=OFF \
    -DBUILD_SMESH=OFF \
    -DBUILD_FEM_NETGEN=OFF \
    -DBUILD_ADDONMGR=OFF \
    -DBUILD_ARCH=OFF \
    -DBUILD_ASSEMBLY=OFF \
    -DBUILD_BIM=OFF \
    -DBUILD_CAM=OFF \
    -DBUILD_CLOUD=OFF \
    -DBUILD_DRAFT=OFF \
    -DBUILD_DRAWING=OFF \
    -DBUILD_IDF=OFF \
    -DBUILD_HELP=OFF \
    -DBUILD_IMPORT=OFF \
    -DBUILD_INSPECTION=OFF \
    -DBUILD_JTREADER=OFF \
    -DBUILD_MATERIAL=ON \
    -DBUILD_MATERIAL_EXTERNAL=OFF \
    -DBUILD_MEASURE=OFF \
    -DBUILD_MESH=ON \
    -DBUILD_MESH_PART=OFF \
    -DBUILD_FLAT_MESH=OFF \
    -DBUILD_OPENSCAD=OFF \
    -DBUILD_PART=ON \
    -DBUILD_PART_DESIGN=OFF \
    -DBUILD_PATH=OFF \
    -DBUILD_PLOT=OFF \
    -DBUILD_POINTS=OFF \
    -DBUILD_REVERSEENGINEERING=OFF \
    -DBUILD_ROBOT=OFF \
    -DBUILD_SHOW=OFF \
    -DBUILD_SKETCHER=OFF \
    -DBUILD_SPREADSHEET=OFF \
    -DBUILD_START=OFF \
    -DBUILD_TEST=OFF \
    -DBUILD_TECHDRAW=OFF \
    -DBUILD_TUX=OFF \
    -DBUILD_WEB=OFF \
    -DBUILD_SURFACE=OFF \
    -DENABLE_DEVELOPER_TESTS=OFF \
    -DFREECAD_USE_FREETYPE=OFF \
    -DFREECAD_USE_PCL=OFF \
    -DFREECAD_USE_EXTERNAL_FMT=OFF

echo "Configured GUI FreeCAD in $BUILD"
