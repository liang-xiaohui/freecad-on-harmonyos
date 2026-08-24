#!/bin/sh
# 构建 Qt 6.8.3 附加模块：qtsvg（Svg/SvgWidgets）与 qttools（UiTools 等）。
# 依赖：先运行 scripts/build-qt6-gui-ohos.sh 完成 qtbase 的 configure+build+install。
#
# 用法：
#   sh scripts/build-qt6-modules-ohos.sh            # 全部
#   sh scripts/build-qt6-modules-ohos.sh qtsvg      # 仅 qtsvg
#   sh scripts/build-qt6-modules-ohos.sh qttools    # 仅 qttools
set -eu
if (set -o pipefail) 2>/dev/null; then
    set -o pipefail
fi

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

export PATH="$HOME/.harmonybrew/bin:$PATH"
PATCH_DIR="$CPP_LIB_ROOT/patches/qt-6.8-ohos"
export PATH="$PATCH_DIR/host-shim:$PATH"   # uname 伪装（HarmonyOS -> Linux）
export NATIVE_OHOS_SDK="$NATIVE_SDK"

QT_VERSION="${QT_VERSION:-6.8.3}"
QT_PREFIX="$CPP_LIB_ROOT/install/qt/$QT_VERSION/ohos/$ABI"
CMAKE_BIN="$NATIVE_SDK/build-tools/cmake/bin/cmake"
NINJA_BIN="$NATIVE_SDK/build-tools/cmake/bin/ninja"

export LD_LIBRARY_PATH="$QT_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

[ -x "$QT_PREFIX/bin/qt-configure-module" ] || {
    echo "qtbase 未安装：先运行 scripts/build-qt6-gui-ohos.sh" >&2
    exit 1
}

build_module() {
    name=$1
    src="$CPP_LIB_ROOT/sources/qt/$name-$QT_VERSION"
    build="$CPP_LIB_ROOT/build/qt/$name-$QT_VERSION-ohos"
    [ -d "$src" ] || { echo "源码缺失：$src" >&2; exit 1; }
    rm -rf "$build"
    mkdir -p "$build"
    echo "==> configure $name"
    "$CMAKE_BIN" -S "$src" -B "$build" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$NINJA_BIN" \
        -U CMAKE_AR -U CMAKE_C_COMPILER_AR -U CMAKE_CXX_COMPILER_AR \
        -U CMAKE_LINKER -U CMAKE_NM -U CMAKE_OBJCOPY -U CMAKE_OBJDUMP \
        -U CMAKE_STRIP \
        -DCMAKE_PREFIX_PATH="$QT_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$QT_PREFIX" \
        -DCMAKE_C_COMPILER="$CPP_LIB_ROOT/scripts/ohos-bin/clang" \
        -DCMAKE_CXX_COMPILER="$CPP_LIB_ROOT/scripts/ohos-bin/clang++" \
        -DCMAKE_AR:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-ar" \
        -DCMAKE_C_COMPILER_AR:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-ar" \
        -DCMAKE_CXX_COMPILER_AR:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-ar" \
        -DCMAKE_LINKER:FILEPATH="$NATIVE_SDK/llvm/bin/ld.lld" \
        -DCMAKE_NM:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-nm" \
        -DCMAKE_OBJCOPY:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-objcopy" \
        -DCMAKE_OBJDUMP:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-objdump" \
        -DCMAKE_RANLIB="$PATCH_DIR/host-shim/llvm-ranlib" \
        -DCMAKE_STRIP="$NATIVE_SDK/llvm/bin/llvm-strip" \
        -DCMAKE_MODULE_PATH="$PATCH_DIR/cmake-platform" \
        -DQT_QMAKE_TARGET_MKSPEC=linux-clang \
        -DEGL_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include" \
        -DEGL_LIBRARY="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos/libEGL.so" \
        -DGLESv2_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include" \
        -DGLESv2_LIBRARY="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos/libGLESv2.so" \
        -DZLIB_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include" \
        -DZLIB_LIBRARY="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos/libz.so" \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF
    echo "==> build $name"
    "$CMAKE_BIN" --build "$build" -- -j "$JOBS" 2>&1 | tee "$build/build.log"
    echo "==> install $name"
    "$CMAKE_BIN" --install "$build"
    QT_PREFIX="$QT_PREFIX" OHOS_SDK="$OHOS_SDK" NATIVE_SDK="$NATIVE_SDK" \
        sh "$PROJECT_DIR/scripts/sign-qt6-host-tools-ohos.sh"
}

case "${1:-all}" in
    qtsvg) build_module qtsvg ;;
    qttools) build_module qttools ;;
    all)
        build_module qtsvg
        build_module qttools
        ;;
    *) echo "usage: $0 [all|qtsvg|qttools]" >&2; exit 2 ;;
esac
echo "==> done"
