#!/bin/sh
# 构建 FreeCAD v1.1.2 GUI（Qt6 目标线，OHOS arm64-v8a）。
# 前置：scripts/configure-freecad-gui-qt6-ohos.sh 配置成功。
set -eu
if (set -o pipefail) 2>/dev/null; then
    set -o pipefail
fi

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
BUILD="${FREECAD_GUI_BUILD:-$CPP_LIB_ROOT/build/freecad/$FREECAD_VERSION/ohos-$ABI-gui-qt6-full}"
QT_PREFIX="${QT_PREFIX:-$CPP_LIB_ROOT/install/qt/6.8.3/ohos/$ABI}"

[ -f "$BUILD/build.ninja" ] || {
    echo "未配置：先运行 scripts/configure-freecad-gui-qt6-ohos.sh" >&2
    exit 1
}

export LD_LIBRARY_PATH="$QT_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$CMAKE_BIN" --build "$BUILD" -j "$JOBS" 2>&1 | tee "$BUILD/build.log"
echo "==> build finished（install 另跑：cmake --install $BUILD）"
