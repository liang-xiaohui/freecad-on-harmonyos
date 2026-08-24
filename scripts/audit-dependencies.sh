#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"
QT_PREFIX="${QT_PREFIX:-$CPP_LIB_ROOT/install/qt/5.12.12-src/ohos/$ABI}"
BOOST_PREFIX="${BOOST_PREFIX:-$CPP_LIB_ROOT/install/boost/1.86.0/ohos/$ABI}"
EIGEN_PREFIX="${EIGEN_PREFIX:-$CPP_LIB_ROOT/install/eigen/3.4.1/ohos/$ABI}"
OCCT_PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/7.8.1/ohos/$ABI}"
XERCES_PREFIX="${XERCES_PREFIX:-$CPP_LIB_ROOT/install/xerces-c/3.2.4/ohos/$ABI}"
COIN_PREFIX="${COIN_PREFIX:-$CPP_LIB_ROOT/install/coin3d/4.0.2/ohos/$ABI}"
missing_count=0

ok() {
    echo "OK      $1"
}

missing() {
    echo "MISSING $1"
    missing_count=$((missing_count + 1))
}

check_file() {
    label=$1
    path=$2
    if [ -f "$path" ]; then ok "$label"; else missing "$label ($path)"; fi
}

echo "== FreeCAD 1.1.2 HarmonyOS dependency audit =="
check_file "FreeCAD source" "$CPP_LIB_ROOT/sources/freecad/1.1.2/CMakeLists.txt"
check_file "Qt Core" "$QT_PREFIX/lib/cmake/Qt5Core/Qt5CoreConfig.cmake"
check_file "Qt XmlPatterns" "$QT_PREFIX/lib/cmake/Qt5XmlPatterns/Qt5XmlPatternsConfig.cmake"
check_file "Qt Svg" "$QT_PREFIX/lib/cmake/Qt5Svg/Qt5SvgConfig.cmake"
check_file "Qt UiTools" "$QT_PREFIX/lib/cmake/Qt5UiTools/Qt5UiToolsConfig.cmake"
check_file "Qt LinguistTools" "$QT_PREFIX/lib/cmake/Qt5LinguistTools/Qt5LinguistToolsConfig.cmake"
check_file "Boost headers" "$BOOST_PREFIX/include/boost/version.hpp"
check_file "Boost filesystem" "$BOOST_PREFIX/lib/libboost_filesystem.a"
check_file "Boost program_options" "$BOOST_PREFIX/lib/libboost_program_options.a"
check_file "Boost regex target" "$BOOST_PREFIX/lib/cmake/boost_regex-1.86.0/boost_regex-config.cmake"
check_file "Boost system target" "$BOOST_PREFIX/lib/cmake/boost_system-1.86.0/boost_system-config.cmake"
check_file "Boost thread" "$BOOST_PREFIX/lib/libboost_thread.a"
check_file "Boost date_time" "$BOOST_PREFIX/lib/libboost_date_time.a"
check_file "Eigen" "$EIGEN_PREFIX/include/eigen3/Eigen/Core"
check_file "Xerces-C" "$XERCES_PREFIX/lib/cmake/XercesC/XercesCConfig.cmake"
check_file "OpenCASCADE" "$OCCT_PREFIX/lib/cmake/opencascade/OpenCASCADEConfig.cmake"
check_file "Coin3D" "$COIN_PREFIX/lib/cmake/Coin-4.0.2/CoinConfig.cmake"
check_file "gl4es" "$CPP_LIB_ROOT/install/gl4es/81547d9/ohos/$ABI/usr/lib/gl4es/libGL.so"

python_root="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI}"
python_bin="${PYTHON_BIN:-$NATIVE_SDK/llvm/python3/bin/python3}"

if [ -n "$python_root" ] && [ -f "$python_root/lib/libpython3.11.so" ]; then
    ok "Python 3.11 ABI ($python_root)"
    if PYTHONHOME="$python_root" "$python_bin" -c \
        'import _socket, binascii, ctypes, http.server, threading, zlib' \
        >/dev/null 2>&1; then
        ok "Python runtime modules"
    else
        missing "Python runtime modules (_socket/threading/http.server)"
    fi
else
    missing "Python 3.11 runtime"
fi

if command -v swig >/dev/null 2>&1; then
    ok "SWIG ($(command -v swig))"
else
    missing "SWIG host tool"
fi

echo ""
if [ "$missing_count" -ne 0 ]; then
    echo "$missing_count dependency checks are not ready."
    exit 1
fi
echo "All dependency checks passed."
