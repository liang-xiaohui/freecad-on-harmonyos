#!/bin/sh
# Stage FreeCAD v1.1.2 GUI（Qt6 线）HAP runtime：
#   - entry/libs/arm64-v8a/：Qt6 + libqohos(QPA) + FreeCAD GUI + OCCT + Coin + gl4es + Python 等 native 依赖
#   - entry/src/main/resources/rawfile/：python311.zip + freecad-runtime.zip
# 前置：build-qt6-gui-ohos.sh / build-qt6-modules-ohos.sh / build-freecad-gui-qt6-ohos.sh + install
# 另需在 entry/libs 放入 libfreecadqtapp.so（见 CPPLib/build/freecad-qtapp）。
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
FREECAD_PREFIX="${FREECAD_PREFIX:-$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-gui-qt6}"
BUILD_ADDONMGR="${FREECAD_BUILD_ADDONMGR:-ON}"
BUILD_START="${FREECAD_BUILD_START:-ON}"
QT_PREFIX="$CPP_LIB_ROOT/install/qt/6.8.3/ohos/$ABI"
PYTHON_ROOT="$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI"
OCCT_PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/7.8.1/ohos/$ABI}"
XERCES_PREFIX="${XERCES_PREFIX:-$CPP_LIB_ROOT/install/xerces-c/3.2.4/ohos/$ABI}"
VTK_PREFIX="${VTK_PREFIX:-$CPP_LIB_ROOT/install/vtk/9.3.1/ohos/$ABI}"
LIBFFI_PREFIX="${LIBFFI_PREFIX:-$CPP_LIB_ROOT/install/libffi/3.4.2/ohos/$ABI}"
COIN_PREFIX="$CPP_LIB_ROOT/install/coin/4.0.0/ohos/$ABI"
GL4ES_DIR="$CPP_LIB_ROOT/install/gl4es/81547d9/ohos/$ABI/usr/lib/gl4es"
QTAPP_LIB="${QTAPP_LIB:-$CPP_LIB_ROOT/build/freecad-qtapp/libfreecadqtapp.so}"
LIBS_PARENT="$PROJECT_DIR/entry/libs"
LIBS_DIR="$LIBS_PARENT/$ABI"
RAWFILE_PARENT="$PROJECT_DIR/entry/src/main/resources"
RAWFILE_DIR="$RAWFILE_PARENT/rawfile"
FLEXIMIND_ROOT="${FLEXIMIND_ROOT:-/path/to/FlexiMind}"

for required in \
    "$FREECAD_PREFIX/lib/FreeCAD.so" \
    "$FREECAD_PREFIX/lib/FreeCADGui.so" \
    "$FREECAD_PREFIX/lib/PartGui.so" \
    "$FREECAD_PREFIX/lib/ImportGui.so" \
    "$FREECAD_PREFIX/lib/PartDesignGui.so" \
    "$FREECAD_PREFIX/lib/SketcherGui.so" \
    "$QT_PREFIX/lib/libQt6Gui.so.6.8.3" \
    "$QT_PREFIX/plugins/platforms/libqohos.so" \
    "$COIN_PREFIX/lib/libCoin.so.4.0.0" \
    "$GL4ES_DIR/libGL.so" \
    "$QTAPP_LIB" \
    "$PYTHON_ROOT/lib/libpython3.11.so.1.0"; do
    [ -e "$required" ] || {
        echo "错误：缺少 GUI HAP runtime 输入：$required" >&2
        exit 1
    }
done

for required in \
    "$FREECAD_PREFIX/Mod/Import/InitGui.py" \
    "$FREECAD_PREFIX/Mod/PartDesign/InitGui.py" \
    "$FREECAD_PREFIX/Mod/Sketcher/InitGui.py"; do
    [ -f "$required" ] || {
        echo "错误：GUI 工作台未安装完整，缺少：$required" >&2
        exit 1
    }
done
if [ "$BUILD_ADDONMGR" = ON ]; then
    for required in \
        "$FREECAD_PREFIX/Mod/AddonManager/Init.py" \
        "$FREECAD_PREFIX/Mod/AddonManager/InitGui.py"; do
        [ -f "$required" ] || {
            echo "错误：Addon Manager 已启用但未安装：$required" >&2
            exit 1
        }
    done
fi
if [ "$BUILD_START" = ON ]; then
    for required in \
        "$FREECAD_PREFIX/Mod/Start/Init.py" \
        "$FREECAD_PREFIX/Mod/Start/InitGui.py"; do
        [ -f "$required" ] || {
            echo "错误：Start 工作台已启用但未安装：$required" >&2
            exit 1
        }
    done
fi

for required in \
    "$FLEXIMIND_ROOT/workers/worker-a.py" \
    "$FLEXIMIND_ROOT/workers/worker-b.py" \
    "$FLEXIMIND_ROOT/workers/worker-c.py" \
    "$FLEXIMIND_ROOT/tools/freecad/design_bridge.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/InitGui.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/registered_base.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/reference_geometry.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/scene_state.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/commands.py"; do
    [ -f "$required" ] || {
        echo "错误：缺少 FlexiMind FreeCAD runtime 输入：$required" >&2
        exit 1
    }
done

READELF=$(command -v readelf 2>/dev/null || command -v llvm-readelf 2>/dev/null || true)
[ -n "$READELF" ] || { echo "错误：staging 需要 readelf 或 llvm-readelf" >&2; exit 2; }
export READELF
for command_name in zip unzip; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "错误：staging 需要 $command_name" >&2
        exit 2
    }
done

mkdir -p "$LIBS_PARENT"
STAGE=$(mktemp -d "$LIBS_PARENT/.arm64-v8a.gui.XXXXXX")
RAW_STAGE=$(mktemp -d "$RAWFILE_PARENT/.rawfile.gui.XXXXXX")
SCAN_FILE="$STAGE/.elf-scan"
trap 'rm -rf -- "$STAGE" "$RAW_STAGE"' EXIT HUP INT TERM

copy_named_library()
{
    cp -L "$1" "$STAGE/$2"
}

HEADLESS_PREFIX="$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-headless"

HEADLESS_QT6_PREFIX="$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-headless-qt6"

echo "==> Stage FreeCAD GUI modules（全部 .so 从 gui-qt6 构建产物）"
for library in "$FREECAD_PREFIX"/lib/*.so; do
    [ -f "$library" ] && copy_named_library "$library" "$(basename "$library")"
done
# 补充 headless-qt6 中有但 gui-qt6 中可能缺失的应用模块；GUI 模块必须来自 GUI 构建
for library in Sketcher.so _PartDesign.so Import.so; do
    if [ ! -f "$FREECAD_PREFIX/lib/$library" ] && [ -f "$HEADLESS_QT6_PREFIX/lib/$library" ]; then
        copy_named_library "$HEADLESS_QT6_PREFIX/lib/$library" "$library"
    fi
done

echo "==> Stage Qt6 runtime"
for qtlib in "$QT_PREFIX"/lib/libQt6*.so.6.8.3; do
    base=$(basename "$qtlib")
    soname=${base%.8.3}   # libQt6Core.so.6
    copy_named_library "$qtlib" "$soname"
done
mkdir -p "$STAGE/plugins/platforms" "$STAGE/plugins/imageformats"
for plugin in libqohos.so libqoffscreen.so libqminimal.so; do
    [ -f "$QT_PREFIX/plugins/platforms/$plugin" ] && copy_named_library "$QT_PREFIX/plugins/platforms/$plugin" "plugins/platforms/$plugin"
done
# libqohos.so 同时是 NAPI 模块（ArkTS `import qpa from 'libqohos.so'`），
# NAPI 框架只从 libs 顶层加载，必须额外复制一份到顶层（仅 plugins/platforms/ 会被 Qt 插件系统找到，
# 但 ArkTS 侧找不到会导致 QAbilityStage onCreate 抛 "Cannot read property handleAbilityStageOnCreate of undefined"）。
[ -f "$QT_PREFIX/plugins/platforms/libqohos.so" ] && copy_named_library "$QT_PREFIX/plugins/platforms/libqohos.so" "libqohos.so"
for plugin in "$QT_PREFIX"/plugins/imageformats/*.so; do
    [ -f "$plugin" ] && copy_named_library "$plugin" "plugins/imageformats/$(basename "$plugin")"
done

echo "==> Stage FreeCAD Qt app library + Coin + gl4es"
copy_named_library "$QTAPP_LIB" libfreecadqtapp.so
# The standalone Qt app helper is also loaded directly from the HAP root.  A
# build made outside the final staging prefix can retain host-specific absolute
# paths, which are invalid on-device and make the runtime non-relocatable.
if "$READELF" -d "$STAGE/libfreecadqtapp.so" | grep -Eq 'Library (rpath|runpath): \[[^$]'; then
    PATCHELF_BIN="${PATCHELF:-$(command -v patchelf 2>/dev/null || true)}"
    [ -x "$PATCHELF_BIN" ] || [ -x /data/service/hnp/bin/patchelf ] || {
        echo "错误：libfreecadqtapp.so 含绝对 RUNPATH，但找不到 patchelf" >&2
        exit 1
    }
    [ -x "$PATCHELF_BIN" ] || PATCHELF_BIN=/data/service/hnp/bin/patchelf
    "$PATCHELF_BIN" --set-rpath '$ORIGIN' "$STAGE/libfreecadqtapp.so"
fi
copy_named_library "$COIN_PREFIX/lib/libCoin.so.4.0.0" libCoin.so.80
cp -L "$COIN_PREFIX/lib/libCoin.so.4.0.0" "$STAGE/libCoin.so.4.0.0"
copy_named_library "$GL4ES_DIR/libGL.so" libGL.so

echo "==> Stage CPython 3.11 runtime"
mkdir -p "$STAGE/lib/python3.11/lib-dynload"
for extension in "$PYTHON_ROOT"/lib/python3.11/lib-dynload/*.so; do
    [ -f "$extension" ] || continue
    cp -L "$extension" "$STAGE/lib/python3.11/lib-dynload/"
done
copy_named_library "$PYTHON_ROOT/lib/libpython3.11.so.1.0" libpython3.11.so.1.0
cp -L "$PYTHON_ROOT/lib/libpython3.11.so.1.0" "$STAGE/lib/libpython3.11.so.1.0"

if [ -e "$PYTHON_ROOT/lib/libffi.so.8" ]; then
    copy_named_library "$PYTHON_ROOT/lib/libffi.so.8" libffi.so.8
    cp -L "$PYTHON_ROOT/lib/libffi.so.8" "$STAGE/lib/libffi.so.8"
elif [ -e "$LIBFFI_PREFIX/lib/libffi.so.8" ]; then
    copy_named_library "$LIBFFI_PREFIX/lib/libffi.so.8" libffi.so.8
    cp -L "$LIBFFI_PREFIX/lib/libffi.so.8" "$STAGE/lib/libffi.so.8"
fi

echo "==> Package Python and FreeCAD GUI runtime as rawfiles"
(cd "$PYTHON_ROOT/lib/python3.11" && \
    zip -q -r "$RAW_STAGE/python311.zip" . \
        -x 'lib-dynload/*' 'config-3.11-*/*' '__pycache__/*' '*/__pycache__/*' '*.pyc')
(cd "$FREECAD_PREFIX" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" Mod Ext share \
        -x '*/__pycache__/*' '*.pyc')
# Sketcher/PartDesign/Import 的 Python 目录并入（来自 headless-qt6 构建）
if [ -d "$HEADLESS_QT6_PREFIX/Mod" ]; then
(cd "$HEADLESS_QT6_PREFIX" && \
        zip -q -r "$RAW_STAGE/freecad-runtime.zip" Mod \
            -i 'Mod/Sketcher/*' 'Mod/PartDesign/*' 'Mod/Import/*' \
            -x '*/__pycache__/*' '*.pyc')
fi

for entry in Mod/Import/InitGui.py Mod/PartDesign/InitGui.py Mod/Sketcher/InitGui.py; do
    unzip -Z1 "$RAW_STAGE/freecad-runtime.zip" | grep -q "^${entry}$" || {
        echo "错误：打包后的 runtime 缺少 GUI 工作台注册脚本：$entry" >&2
        exit 1
    }
done
if [ "$BUILD_ADDONMGR" = ON ]; then
    for entry in Mod/AddonManager/Init.py Mod/AddonManager/InitGui.py; do
        unzip -Z1 "$RAW_STAGE/freecad-runtime.zip" | grep -q "^${entry}$" || {
            echo "错误：打包后的 runtime 缺少 Addon Manager 注册脚本：$entry"
            exit 1
        }
    done
fi
if [ "$BUILD_START" = ON ]; then
    for entry in Mod/Start/Init.py Mod/Start/InitGui.py; do
        unzip -Z1 "$RAW_STAGE/freecad-runtime.zip" | grep -q "^${entry}$" || {
            echo "错误：打包后的 runtime 缺少 Start 注册脚本：$entry"
            exit 1
        }
    done
fi
# PySide6 / shiboken6 / pivy：Python 包解压到 freecad-home/Ext/；native 扩展保留在 HAP libs/ 下
PYSIDE6_SP="$CPP_LIB_ROOT/install/pyside6/ohos/$ABI/site-packages"
SHIBOKEN_SP="$CPP_LIB_ROOT/build/shiboken6/inst/lib/python3.11/site-packages"
PIVY_SP="$CPP_LIB_ROOT/install/pivy/ohos/$ABI/site-packages"
# 用临时 staging 目录把 PySide6/shiboken6/pivy 放到 zip 的 Ext/ 前缀下（freecad-home/Ext 在 sys.path）
BINDINGS_STAGE=$(mktemp -d "$RAW_STAGE/.bindings.XXXXXX")
mkdir -p "$BINDINGS_STAGE/Ext"
if [ -d "$PYSIDE6_SP/PySide6" ]; then
    cp -r "$PYSIDE6_SP/PySide6" "$BINDINGS_STAGE/Ext/"
    # libpyside6 运行库先随包收集，随后移入 HAP native libs/ 并由 Hvigor 签名
    for lib in "$CPP_LIB_ROOT"/install/pyside6/ohos/$ABI/lib/libpyside6*.so*; do
        [ -f "$lib" ] && cp -L "$lib" "$BINDINGS_STAGE/Ext/PySide6/"
    done
fi
if [ -d "$SHIBOKEN_SP/shiboken6" ]; then
    cp -r "$SHIBOKEN_SP/shiboken6" "$BINDINGS_STAGE/Ext/"
    for lib in "$CPP_LIB_ROOT"/build/shiboken6/inst/lib/libshiboken6*.so*; do
        [ -f "$lib" ] && cp -L "$lib" "$BINDINGS_STAGE/Ext/shiboken6/"
    done
fi
if [ -d "$PIVY_SP/pivy" ]; then
    cp -r "$PIVY_SP/pivy" "$BINDINGS_STAGE/Ext/"
fi
# Native extension modules cannot be loaded from the writable freecad-home
# tree on a non-debuggable OHOS device: extracting them from a rawfile loses
# the HAP code signature.  Put every binding ELF in entry/libs so Hvigor signs
# it, leave only Python files in freecad-runtime.zip, and extend each package's
# __path__ to the signed native library directory at runtime.
PATCHELF_BIN="${PATCHELF:-$(command -v patchelf 2>/dev/null || true)}"
[ -x "$PATCHELF_BIN" ] || [ -x /data/service/hnp/bin/patchelf ] || {
    echo "错误：绑定模块需要 patchelf 以设置可移植 RUNPATH" >&2
    exit 1
}
[ -x "$PATCHELF_BIN" ] || PATCHELF_BIN=/data/service/hnp/bin/patchelf

find "$BINDINGS_STAGE/Ext" -type f -name '*.so*' -print |
    while IFS= read -r binding; do
        binding_name=$(basename "$binding")
        cp -L "$binding" "$STAGE/$binding_name"
        binding_runpath=$("$READELF" -d "$STAGE/$binding_name" 2>/dev/null |
            awk '/\(RPATH\)|\(RUNPATH\)/ {sub(/^.*\[/, ""); sub(/\].*$/, ""); print; exit}')
        # patchelf has to add new dynamic tables when an OHOS ELF has no
        # RUNPATH.  That rewrite makes musl crash in find_sym2() while loading
        # Shiboken.abi3.so.  Files without a RUNPATH already resolve sibling
        # dependencies through the HAP native namespace, so leave them intact.
        if printf '%s\n' "$binding_runpath" | tr ':' '\n' | grep -q '^/'; then
            "$PATCHELF_BIN" --set-rpath '$ORIGIN' "$STAGE/$binding_name"
        fi
    done

prepend_native_package_path()
{
    package_init=$1
    package_tmp="${package_init}.ohos"
    {
        printf '%s\n' \
            '# OHOS native extensions live in the HAP-signed library directory.' \
            'import os as _ohos_os' \
            '_ohos_native_dir = _ohos_os.environ.get("FREECAD_APP_LIBRARY_DIR")' \
            'if _ohos_native_dir and _ohos_native_dir not in __path__:' \
            '    __path__.append(_ohos_native_dir)' \
            'del _ohos_native_dir, _ohos_os' \
            ''
        sed -n 'p' "$package_init"
    } > "$package_tmp"
    mv "$package_tmp" "$package_init"
}
for package_init in \
    "$BINDINGS_STAGE/Ext/shiboken6/__init__.py" \
    "$BINDINGS_STAGE/Ext/PySide6/__init__.py" \
    "$BINDINGS_STAGE/Ext/pivy/__init__.py"; do
    [ -f "$package_init" ] && prepend_native_package_path "$package_init"
done

(cd "$BINDINGS_STAGE" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" Ext \
        -i 'Ext/PySide6/*' 'Ext/shiboken6/*' 'Ext/pivy/*' \
        -x '*.pyc' '*/__pycache__/*' '*.so' '*.so.*')
if unzip -Z1 "$RAW_STAGE/freecad-runtime.zip" |
   grep -Eq '^Ext/(PySide6|shiboken6|pivy)/.*\.so([.]|$)'; then
    echo "错误：Python 绑定 ELF 不得进入 rawfile（会丢失 HAP 代码签名）" >&2
    exit 1
fi
rm -rf "$BINDINGS_STAGE"
echo "==> Package FlexiMind workers and Grip Design Workbench"
FLEXIMIND_STAGE="$RAW_STAGE/fleximind"
mkdir -p "$FLEXIMIND_STAGE/FlexiMind/workers" "$FLEXIMIND_STAGE/FlexiMind/tools/freecad" "$FLEXIMIND_STAGE/Mod"
cp "$PROJECT_DIR/runtime/fleximind_job_runner.py" "$FLEXIMIND_STAGE/FlexiMind/"
printf '%s\n' '"""FlexiMind runtime package."""' > "$FLEXIMIND_STAGE/FlexiMind/__init__.py"
for worker in \
    worker-a.py \
    worker-b.py \
    worker-c.py \
    manual_gripping_workbench_smoke.py; do
    cp "$FLEXIMIND_ROOT/workers/$worker" "$FLEXIMIND_STAGE/FlexiMind/workers/$worker"
done
cp "$FLEXIMIND_ROOT/tools/freecad/design_bridge.py" "$FLEXIMIND_STAGE/FlexiMind/tools/freecad/"
cp -R "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign" \
    "$FLEXIMIND_STAGE/FlexiMind/tools/freecad/"
cp -R "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign" \
    "$FLEXIMIND_STAGE/Mod/"
(cd "$FLEXIMIND_STAGE" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" FlexiMind Mod \
        -x '*/__pycache__/*' '*.pyc')
rm -rf "$FLEXIMIND_STAGE"
cp "$PROJECT_DIR/probes/freecad-headless/acceptance.py" \
    "$RAW_STAGE/freecad_headless_acceptance.py"
unzip -tq "$RAW_STAGE/python311.zip" >/dev/null
unzip -tq "$RAW_STAGE/freecad-runtime.zip" >/dev/null

SEARCH_DIRS="
$FREECAD_PREFIX/lib
$HEADLESS_QT6_PREFIX/lib
$QT_PREFIX/lib
$PYTHON_ROOT/lib
$LIBFFI_PREFIX/lib
$OCCT_PREFIX/lib
$XERCES_PREFIX/lib
$VTK_PREFIX/lib
$COIN_PREFIX/lib
$GL4ES_DIR
"
SYSTEM_DIRS="
$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos
$NATIVE_SDK/sysroot/usr/lib
"

find_staged_library()
{
    needed=$1
    [ -e "$STAGE/$needed" ] || [ -e "$STAGE/lib/$needed" ]
}

is_system_library()
{
    needed=$1
    if [ "$needed" = "libc++_shared.so" ]; then
        return 0
    fi
    for directory in $SYSTEM_DIRS; do
        if [ -e "$directory/$needed" ]; then
            return 0
        fi
    done
    return 1
}

find_dependency_source()
{
    needed=$1
    for directory in $SEARCH_DIRS; do
        if [ -e "$directory/$needed" ]; then
            printf '%s\n' "$directory/$needed"
            return 0
        fi
    done
    return 1
}

echo "==> Resolve non-system DT_NEEDED closure"
pass=0
while [ "$pass" -lt 32 ]; do
    pass=$((pass + 1))
    before=$(find "$STAGE" -maxdepth 1 -type f -name '*.so*' | wc -l | tr -d ' ')
    find "$STAGE" -type f -name '*.so*' > "$SCAN_FILE"
    while IFS= read -r elf; do
        for needed in $("$READELF" -d "$elf" 2>/dev/null | awk '/\(NEEDED\)/ {gsub(/\[|\]/, "", $5); print $5}'); do
            if find_staged_library "$needed" || is_system_library "$needed"; then
                continue
            fi
            source_file=$(find_dependency_source "$needed" || true)
            if [ -n "$source_file" ]; then
                copy_named_library "$source_file" "$needed"
                echo "  + $needed"
            fi
        done
    done < "$SCAN_FILE"
    after=$(find "$STAGE" -maxdepth 1 -type f -name '*.so*' | wc -l | tr -d ' ')
    [ "$before" = "$after" ] && break
done
rm -f "$SCAN_FILE"

OLD_DIR="$LIBS_PARENT/.arm64-v8a.gui.previous.$$"
RAW_OLD_DIR="$RAWFILE_PARENT/.rawfile.gui.previous.$$"
if [ -d "$LIBS_DIR" ]; then
    mv "$LIBS_DIR" "$OLD_DIR"
fi
mv "$STAGE" "$LIBS_DIR"
STAGE="$LIBS_PARENT/.stage-complete.$$"
if [ -d "$RAWFILE_DIR" ]; then
    mv "$RAWFILE_DIR" "$RAW_OLD_DIR"
fi
mv "$RAW_STAGE" "$RAWFILE_DIR"
RAW_STAGE="$RAWFILE_PARENT/.rawfile-complete.$$"
rm -rf -- "$OLD_DIR"
rm -rf -- "$RAW_OLD_DIR"
trap - EXIT HUP INT TERM

echo "==> Audit staged runtime (架构/RUNPATH/递归依赖)"
STAGED_DIR="$LIBS_DIR" RAWFILE_DIR="$RAWFILE_DIR" \
    "$PROJECT_DIR/scripts/audit-headless-hap.sh" || true

file_count=$(find "$LIBS_DIR" -type f | wc -l | tr -d ' ')
size_kb=$(du -sk "$LIBS_DIR" | awk '{print $1}')
echo "Staged $file_count files ($size_kb KiB): $LIBS_DIR"
echo "Packaged raw runtime: $RAWFILE_DIR"
echo "提示：Libentry 仍需 DevEco 构建；libqohos.so 由 XComponent 以 libraryname=qohos 加载。"
