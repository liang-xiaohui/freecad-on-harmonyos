#!/bin/sh
# 构建 Qt 6.8.3 qtbase 的 GUI 模块（Gui/Widgets/OpenGL/OpenGLWidgets/PrintSupport/Network/Xml/Concurrent）
# 用于 FreeCAD v1.1.2 完整 GUI 的 Qt6 目标依赖线。
#
# 构建方式：OHOS PC 本机原生构建（host == target）。
#   - 编译器：OHOS SDK clang（默认 sysroot 指向 OHOS native sysroot）
#   - uname shim：把 HarmonyOS 伪装为 Linux（CMake/Qt 的 LINUX 特性检测）
#   - llvm-ranlib shim：SDK 无 llvm-ranlib，用 llvm-ar s 等价
#   - 链接产物由 ohos-bin/clang 包装器自动 chmod +x + 自签名（否则共享目录不可执行）
# 前置：sources/qt/6.8.3 已解压并打好 patches/qt-6.8-ohos/01-ohos-no-pthread-cancel.patch。
# FreeCAD GUI 使用已在真机显示主界面的 v11 QPA 基线：补丁 02 + 03，
# 再叠加不改变 backing-store 的安全修复 09 + 10 + 11。
# 04..08 是后续 OpenGL backing-store 实验，已证实会在首次刷新时崩溃，禁止自动应用。
#
# 用法：
#   sh scripts/build-qt6-gui-ohos.sh            # configure + build + install
#   sh scripts/build-qt6-gui-ohos.sh configure  # 仅 configure
#   sh scripts/build-qt6-gui-ohos.sh build      # 仅 build + install（复用已有 configure）
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
export NATIVE_OHOS_SDK="$NATIVE_SDK"       # ohos-bin/clang 包装器的真实 SDK 路径

QT_VERSION="${QT_VERSION:-6.8.3}"
QPA_GL4ES_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/02-gl4es-external-context.patch"
QPA_WINDOW_SURFACE_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/03-require-window-surface-before-gl4es.patch"
QPA_FILE_ICON_GUARD_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/09-guard-optional-file-icon-service.patch"
QPA_NO_SURFACELESS_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/10-disable-surfaceless-context.patch"
QPA_GL4ES_PROC_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/11-use-egl-proc-address-for-gl4es.patch"
QPA_DEFER_CURSOR_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/12-defer-detached-input-cursor.patch"
COLLATOR_WARN_ONCE_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/13-collator-warn-once.patch"
QPA_POPUP_PARENT_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/14-popup-parent-of-embedded-dialog.patch"
QPA_ORPHAN_QLABEL_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/15-embed-orphan-qlabel.patch"
QPA_STARTUP_CONTENT_PATCH="$PROJECT_DIR/patches/qt-6.8-ohos/16-reuse-startup-content.patch"
QPA_GL4ES_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohoseglplatformcontext.cpp"
QPA_GL4ES_HEADER="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohoseglplatformcontext.h"
QPA_OFFSCREEN_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohosplatformoffscreensurface.cpp"
QPA_INTEGRATION_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohosplatformintegration.cpp"
QPA_BACKING_STORE_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohosplatformbackingstoregl.cpp"
QPA_THEME_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohosplatformtheme.cpp"
QPA_INPUT_CONTEXT_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohosinputcontext.cpp"
QPA_JS_MAIN_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/qohosjsmain.cpp"
QPA_WINDOW_PROXY_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/render/qohoswindowproxy.cpp"
QPA_VIEW_SOURCE="$CPP_LIB_ROOT/sources/qt/$QT_VERSION/src/plugins/platforms/ohos/render/qohosview.cpp"

SRC="$CPP_LIB_ROOT/sources/qt/$QT_VERSION"
BUILD="$CPP_LIB_ROOT/build/qt/$QT_VERSION-ohos-gui"
PREFIX="$CPP_LIB_ROOT/install/qt/$QT_VERSION/ohos/$ABI"
SYSROOT="$NATIVE_SDK/sysroot"
CMAKE_BIN="$NATIVE_SDK/build-tools/cmake/bin/cmake"
NINJA_BIN="$NATIVE_SDK/build-tools/cmake/bin/ninja"

export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

[ -f "$SRC/CMakeLists.txt" ] || { echo "Qt source is missing: $SRC" >&2; exit 1; }
[ -f "$QPA_GL4ES_SOURCE" ] || { echo "Qt OHOS QPA source is missing: $QPA_GL4ES_SOURCE" >&2; exit 1; }

apply_gl4es_qpa_patch() {
    # The OHOS Qt source archive ships these files with CRLF.  The local
    # patches are LF unified diffs, so normalize only the files they touch;
    # leaving the rest of qtbase byte-for-byte unchanged avoids noisy source
    # churn while making patch failures observable.
    for qpa_source in \
        "$QPA_GL4ES_SOURCE" \
        "$QPA_OFFSCREEN_SOURCE" \
        "$QPA_INTEGRATION_SOURCE" \
        "$QPA_BACKING_STORE_SOURCE" \
        "$QPA_THEME_SOURCE" \
        "$QPA_INPUT_CONTEXT_SOURCE" \
        "$QPA_JS_MAIN_SOURCE" \
        "$QPA_WINDOW_PROXY_SOURCE" \
        "$QPA_VIEW_SOURCE"; do
        [ -f "$qpa_source" ] || continue
        sed -i 's/\r$//' "$qpa_source"
    done

    apply_qpa_patch() {
        patch_file=$1
        marker_file=$2
        marker=$3
        description=$4

        if grep -Fq -- "$marker" "$marker_file"; then
            return 0
        fi

        echo "==> $description"
        if ! patch -d "$SRC" -p1 --dry-run < "$patch_file"; then
            echo "错误：Qt QPA 补丁无法应用：$patch_file" >&2
            echo "       源文件可能处于部分修改状态，请清理 Qt 源码后重试。" >&2
            exit 1
        fi
        if ! patch -d "$SRC" -p1 < "$patch_file"; then
            echo "错误：Qt QPA 补丁应用失败：$patch_file" >&2
            exit 1
        fi
        if ! grep -Fq -- "$marker" "$marker_file"; then
            echo "错误：Qt QPA 补丁应用后 marker 缺失：$marker_file" >&2
            exit 1
        fi
    }

    if ! grep -Fq 'gl4es_activate_external_context' "$QPA_GL4ES_SOURCE" \
        || ! grep -Fq 'using InitializeGl4es' "$QPA_GL4ES_SOURCE"; then
        apply_qpa_patch "$QPA_GL4ES_PATCH" "$QPA_GL4ES_SOURCE" \
            'using InitializeGl4es' "应用 Qt OHOS gl4es 外部上下文补丁"
    fi

    if ! grep -Fq 'QSurface::Offscreen' "$QPA_GL4ES_SOURCE" \
        || ! grep -Fq 'EGL_PBUFFER_BIT' "$QPA_OFFSCREEN_SOURCE" \
        || ! grep -Fq 'new QOhosPlatformOffscreenSurface' "$QPA_INTEGRATION_SOURCE"; then
        apply_qpa_patch "$QPA_WINDOW_SURFACE_PATCH" "$QPA_OFFSCREEN_SOURCE" \
            'EGL_PBUFFER_BIT' "应用 Qt OHOS EGL window/offscreen surface 补丁"
    fi

    if ! grep -Fq 'system file icon lookup unavailable for extension' "$QPA_THEME_SOURCE"; then
        apply_qpa_patch "$QPA_FILE_ICON_GUARD_PATCH" "$QPA_THEME_SOURCE" \
            'system file icon lookup unavailable for extension' \
            "保护缺失的 OHOS FileManagerServiceKit 文件图标查询"
    fi

    if ! grep -Fq 'ctxCreateInfo.optionalFlags = QEGLPlatformContext::NoSurfaceless' \
        "$QPA_INTEGRATION_SOURCE"; then
        apply_qpa_patch "$QPA_NO_SURFACELESS_PATCH" "$QPA_INTEGRATION_SOURCE" \
            'ctxCreateInfo.optionalFlags = QEGLPlatformContext::NoSurfaceless' \
            "禁用 OHOS OpenGLWrapper 不可用的 EGL surfaceless 初始化路径"
    fi

    if ! grep -Fq 'setGetProcAddress(resolveCurrentGlesProcAddress)' \
        "$QPA_GL4ES_SOURCE"; then
        apply_qpa_patch "$QPA_GL4ES_PROC_PATCH" "$QPA_GL4ES_SOURCE" \
            'setGetProcAddress(resolveCurrentGlesProcAddress)' \
            "让 GL4ES 从当前 EGL context 解析 GLES 驱动入口"
    fi

    if ! grep -Fq 'Defer the update without flooding notifications' \
        "$QPA_INPUT_CONTEXT_SOURCE"; then
        apply_qpa_patch "$QPA_DEFER_CURSOR_PATCH" "$QPA_INPUT_CONTEXT_SOURCE" \
            'Defer the update without flooding notifications' \
            "延后未连接输入法的光标更新并抑制通知洪泛"
    fi

    # qtbase corelib（非 QPA）：POSIX collation 不支持 numeric/case-insensitive，
    # 上游逐次 qWarning 会被 FreeCAD 转成用户可见通知洪泛；改为每进程只告警一次。
    COLLATOR_SOURCE="$SRC/src/corelib/text/qcollator_posix.cpp"
    if ! grep -Fq 'OHOS: without ICU these modes are silently unsupported' \
        "$COLLATOR_SOURCE"; then
        apply_qpa_patch "$COLLATOR_WARN_ONCE_PATCH" "$COLLATOR_SOURCE" \
            'OHOS: without ICU these modes are silently unsupported' \
            "让 POSIX collation 的能力缺失告警每进程只出现一次"
    fi

    # 弹窗/tooltip 的宿主窗口解析：逻辑父窗口是嵌入式对话框时，沿目标父视图
    # 的祖先链找宿主窗口，避免 "Failed to determine valid parent" 崩溃。
    if ! grep -Fq 'resolve the hosting window through the \*target parent\*' \
        "$QPA_VIEW_SOURCE"; then
        apply_qpa_patch "$QPA_POPUP_PARENT_PATCH" "$QPA_VIEW_SOURCE" \
            'resolve the hosting window through the *target parent*' \
            "修复嵌入式对话框里弹窗/下拉框的父窗口解析崩溃"
    fi

    # QWidget 样式初始化可能短暂实现一个无父级空 QLabel。若按主窗口处理，
    # OHOS 会为它启动第二个 Ability，并销毁真正主窗口的启动 surface。
    if ! grep -Fq 'OrphanQLabelEmbeddedRemap' "$QPA_VIEW_SOURCE"; then
        apply_qpa_patch "$QPA_ORPHAN_QLABEL_PATCH" "$QPA_VIEW_SOURCE" \
            'OrphanQLabelEmbeddedRemap' \
            "将启动阶段的孤立 QLabel 保留在现有主窗口"
    fi

    # FreeCAD loads the native-node page once as the transparent main-window
    # host behind its splash subwindow. QPA injects createInfo into that page
    # and defers native main-window geometry until GUI-ready, avoiding a
    # second page load and a moving splash.
    if ! grep -Fq 'FreeCADStartupContentReuse' "$QPA_JS_MAIN_SOURCE" \
        || ! grep -Fq 'FreeCADStartupGeometryDeferred' "$QPA_WINDOW_PROXY_SOURCE"; then
        apply_qpa_patch "$QPA_STARTUP_CONTENT_PATCH" "$QPA_JS_MAIN_SOURCE" \
            'FreeCADStartupContentReuse' \
            "复用启动页面并延后 FreeCAD 主窗口几何切换"
    fi

    # v11 is the last QPA binary that survived startup and painted the FreeCAD
    # main window on device.  Do not silently rebuild a source tree carrying
    # later experiments: 04/05/06 route RasterGL through a custom GL/RHI path,
    # 07 overrides proc lookup, 08 broadens GL backing store to RasterSurface,
    # and the v12 diagnostic also changed makeCurrent().  Those variants end
    # in QPlatformBackingStore::rhiFlush or invalid GLES calls on QtMainThread.
    qpa_bad_marker=
    for marker in \
        'QPlatformBackingStoreGL::rhiFlush' \
        'loadedGl4esHandle' \
        'QOhosEGLPlatformContext: unusable current context' \
        'QOpenGLWidget keeps the top-level QWidget as RasterSurface' \
        'QOpenGLWidget requires a real OpenGL compositor'; do
        if grep -Fq "$marker" "$QPA_GL4ES_SOURCE" \
            || grep -Fq "$marker" "$QPA_INTEGRATION_SOURCE" \
            || grep -Fq "$marker" "$QPA_BACKING_STORE_SOURCE"; then
            qpa_bad_marker=$marker
            break
        fi
    done
    if [ -n "$qpa_bad_marker" ] \
        || grep -Fq 'getProcAddress(const char *procName) override' "$QPA_GL4ES_HEADER" \
        || grep -Fq '<rhi/qrhi.h>' "$QPA_BACKING_STORE_SOURCE"; then
        echo "错误：Qt OHOS QPA 源码仍带有 v12-v14/patch 04..08 实验修改。" >&2
        echo "       命中 marker：${qpa_bad_marker:-post-v11 declaration/include}" >&2
        echo "       请恢复 v11 基线（02 + 03）及安全修复（09 + 10 + 11）后重试。" >&2
        exit 1
    fi
    if ! grep -Fq 'result = QtOhos::isGlBackingStoreDefaultEnabled()' \
        "$QPA_INTEGRATION_SOURCE"; then
        echo "错误：RasterGLSurface 未处于 v11 的可配置 backing-store 路径。" >&2
        exit 1
    fi
}

configure() {
    apply_gl4es_qpa_patch
    mkdir -p "$BUILD"

    # CMake records compiler-adjacent tools and implicit SDK paths in
    # CMakeFiles/<version>/CMake*Compiler.cmake.  Updating CMAKE_AR in the
    # cache is not enough when a build tree moves from the DevEco SDK under
    # /data/app to the HNP SDK under /data/service: generated Ninja rules will
    # still call the inaccessible old llvm-ar.  Refresh only when that
    # compiler state does not describe the active SDK, preserving normal
    # incremental builds otherwise.
    cmake_version=$(
        "$CMAKE_BIN" --version | sed -n '1s/^cmake version //p'
    )
    cmake_compiler_state="$BUILD/CMakeFiles/$cmake_version/CMakeCCompiler.cmake"
    cmake_fresh_arg=
    if [ -f "$cmake_compiler_state" ] \
        && ! grep -Fq "set(CMAKE_AR \"$NATIVE_SDK/llvm/bin/llvm-ar\")" \
            "$cmake_compiler_state"; then
        echo "==> 检测到 Qt CMake 编译器状态仍引用其它 SDK，执行一次 --fresh"
        cmake_fresh_arg=--fresh
    fi

    echo "==> configure Qt $QT_VERSION GUI in $BUILD"
    "$CMAKE_BIN" ${cmake_fresh_arg:+"$cmake_fresh_arg"} \
        -S "$SRC" -B "$BUILD" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$NINJA_BIN" \
        -U CMAKE_AR -U CMAKE_C_COMPILER_AR -U CMAKE_CXX_COMPILER_AR \
        -U CMAKE_LINKER -U CMAKE_NM -U CMAKE_OBJCOPY -U CMAKE_OBJDUMP \
        -U CMAKE_ASM_COMPILER_AR -U CMAKE_ASM_COMPILER_RANLIB \
        -U CMAKE_STRIP \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_C_COMPILER="$CPP_LIB_ROOT/scripts/ohos-bin/clang" \
        -DCMAKE_CXX_COMPILER="$CPP_LIB_ROOT/scripts/ohos-bin/clang++" \
        -DCMAKE_ASM_COMPILER="$CPP_LIB_ROOT/scripts/ohos-bin/clang" \
        -DCMAKE_AR:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-ar" \
        -DCMAKE_C_COMPILER_AR:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-ar" \
        -DCMAKE_CXX_COMPILER_AR:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-ar" \
        -DCMAKE_LINKER:FILEPATH="$NATIVE_SDK/llvm/bin/ld.lld" \
        -DCMAKE_NM:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-nm" \
        -DCMAKE_OBJCOPY:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-objcopy" \
        -DCMAKE_OBJDUMP:FILEPATH="$NATIVE_SDK/llvm/bin/llvm-objdump" \
        -DCMAKE_RANLIB="$PATCH_DIR/host-shim/llvm-ranlib" \
        -DCMAKE_ASM_COMPILER_AR="$NATIVE_SDK/llvm/bin/llvm-ar" \
        -DCMAKE_ASM_COMPILER_RANLIB="$PATCH_DIR/host-shim/llvm-ranlib" \
        -DCMAKE_STRIP="$NATIVE_SDK/llvm/bin/llvm-strip" \
        -DCMAKE_MODULE_PATH="$PATCH_DIR/cmake-platform" \
        -DFEATURE_gui=ON \
        -DFEATURE_widgets=ON \
        -DFEATURE_opengl=ON \
        -DFEATURE_opengles2=ON \
        -DFEATURE_egl=ON \
        -DFEATURE_gl=OFF \
        -DFEATURE_network=ON \
        -DFEATURE_concurrent=ON \
        -DFEATURE_sql=OFF \
        -DFEATURE_testlib=OFF \
        -DFEATURE_dbus=OFF \
        -DFEATURE_glib=OFF \
        -DFEATURE_icu=OFF \
        -DFEATURE_system_zlib=ON \
        -DFEATURE_zstd=OFF \
        -DFEATURE_brotli=OFF \
        -DFEATURE_xcb=OFF \
        -DFEATURE_eglfs=OFF \
        -DFEATURE_linuxfb=ON \
        -DFEATURE_vnc=OFF \
        -DFEATURE_vulkan=OFF \
        -DFEATURE_evdev=OFF \
        -DFEATURE_libinput=OFF \
        -DFEATURE_tslib=OFF \
        -DFEATURE_xkbcommon=OFF \
        -DFEATURE_fontconfig=OFF \
        -DFEATURE_system_freetype=OFF \
        -DFEATURE_system_harfbuzz=OFF \
        -DEGL_INCLUDE_DIR="$SYSROOT/usr/include" \
        -DEGL_LIBRARY="$SYSROOT/usr/lib/aarch64-linux-ohos/libEGL.so" \
        -DGLESv2_INCLUDE_DIR="$SYSROOT/usr/include" \
        -DGLESv2_LIBRARY="$SYSROOT/usr/lib/aarch64-linux-ohos/libGLESv2.so" \
        -DZLIB_INCLUDE_DIR="$SYSROOT/usr/include" \
        -DZLIB_LIBRARY="$SYSROOT/usr/lib/aarch64-linux-ohos/libz.so" \
        -DGIT_EXECUTABLE="$HOME/.harmonybrew/bin/git" \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF
}

build() {
    echo "==> build Qt $QT_VERSION GUI"
    "$CMAKE_BIN" --build "$BUILD" -- -j "$JOBS" 2>&1 | tee "$BUILD/build.log"
    echo "==> install to $PREFIX"
    "$CMAKE_BIN" --install "$BUILD"
    QT_PREFIX="$PREFIX" OHOS_SDK="$OHOS_SDK" NATIVE_SDK="$NATIVE_SDK" \
        sh "$PROJECT_DIR/scripts/sign-qt6-host-tools-ohos.sh"
}

case "${1:-all}" in
    configure) configure ;;
    build) build ;;
    all) configure && build ;;
    *) echo "usage: $0 [all|configure|build]" >&2; exit 2 ;;
esac
echo "==> done"
