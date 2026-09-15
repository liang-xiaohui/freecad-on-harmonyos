#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
FREECAD_PREFIX="${FREECAD_PREFIX:-$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-headless}"
PYTHON_ROOT="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI}"
OCCT_PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/7.8.1/ohos/$ABI}"
QT_PREFIX="${QT_PREFIX:-$CPP_LIB_ROOT/install/qt/5.12.12-src/ohos/$ABI}"
XERCES_PREFIX="${XERCES_PREFIX:-$CPP_LIB_ROOT/install/xerces-c/3.2.4/ohos/$ABI}"
LIBFFI_PREFIX="${LIBFFI_PREFIX:-$CPP_LIB_ROOT/install/libffi/3.4.2/ohos/$ABI}"
LIBS_PARENT="$PROJECT_DIR/entry/libs"
LIBS_DIR="$LIBS_PARENT/$ABI"
RAWFILE_PARENT="$PROJECT_DIR/entry/src/main/resources"
RAWFILE_DIR="$RAWFILE_PARENT/rawfile"
FLEXIMIND_ROOT="${FLEXIMIND_ROOT:-/path/to/FlexiMind}"
# 这个脚本产出的是内部包（无头验收 + FlexiMind 作业），按定义就是 ON：FlexiMind 载荷与
# 验收脚本都照进，audit-headless-hap.sh 也按 ON 校验 rawfile。对外包走 stage-gui-hap.sh
# （默认 OFF，不声明 EntryAbility、不带载荷与验收脚本）。两边共用 entry/module.json5，
# 能力清单的差异由 entry/hvigorfile.ts 在构建期按同一个开关裁掉。
PACKAGE_FLEXIMIND=ON
export PACKAGE_FLEXIMIND
PY_YAML_ROOT="$PROJECT_DIR/runtime/pyyaml"
PACKAGING_ROOT="$PROJECT_DIR/runtime/packaging"
NUMPY_SP="${NUMPY_SP:-$CPP_LIB_ROOT/install/numpy/2.2.6/ohos/$ABI/site-packages}"
NUMPY_LICENSE="$NUMPY_SP/numpy-2.2.6.dist-info/LICENSE.txt"

for required in \
    "$FREECAD_PREFIX/lib/FreeCAD.so" \
    "$FREECAD_PREFIX/lib/Part.so" \
    "$FREECAD_PREFIX/lib/Mesh.so" \
    "$FREECAD_PREFIX/lib/Import.so" \
    "$FREECAD_PREFIX/lib/Materials.so" \
    "$FREECAD_PREFIX/lib/Sketcher.so" \
    "$FREECAD_PREFIX/lib/_PartDesign.so" \
    "$PYTHON_ROOT/lib/libpython3.11.so.1.0" \
    "$PYTHON_ROOT/lib/python3.11/os.py" \
    "$OCCT_PREFIX/lib/libTKernel.so" \
    "$QT_PREFIX/lib/libQt5Core.so" \
    "$XERCES_PREFIX/lib/libxerces-c-3.2.so"; do
    [ -e "$required" ] || {
        echo "错误：缺少 HAP runtime 输入：$required" >&2
        exit 1
    }
done

[ -f "$PY_YAML_ROOT/yaml/__init__.py" ] || {
    echo "错误：缺少 vendored PyYAML runtime：$PY_YAML_ROOT/yaml/__init__.py" >&2
    exit 1
}
[ -f "$PACKAGING_ROOT/packaging/__init__.py" ] || {
    echo "错误：缺少 vendored packaging runtime：$PACKAGING_ROOT/packaging/__init__.py" >&2
    exit 1
}
[ -f "$NUMPY_SP/numpy/__init__.py" ] || {
    echo "错误：缺少 NumPy runtime：$NUMPY_SP/numpy/__init__.py" >&2
    exit 1
}
for required in \
    "$PY_YAML_ROOT/LICENSE" \
    "$PACKAGING_ROOT/LICENSE" \
    "$PACKAGING_ROOT/LICENSE.APACHE" \
    "$PACKAGING_ROOT/LICENSE.BSD" \
    "$NUMPY_LICENSE" \
    "$NUMPY_SP/numpy/_core/_multiarray_umath.cpython-311-aarch64-linux-ohos.so" \
    "$NUMPY_SP/numpy/fft/_pocketfft_umath.cpython-311-aarch64-linux-ohos.so" \
    "$NUMPY_SP/numpy/linalg/_umath_linalg.cpython-311-aarch64-linux-ohos.so"; do
    [ -f "$required" ] || {
        echo "错误：缺少 Python runtime 输入：$required" >&2
        exit 1
    }
done

for required in \
    "$FLEXIMIND_ROOT/workers/worker-a.py" \
    "$FLEXIMIND_ROOT/workers/worker-b.py" \
    "$FLEXIMIND_ROOT/workers/worker-c.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/registered_base.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/reference_geometry.py"; do
    [ -f "$required" ] || {
        echo "错误：缺少 FlexiMind FreeCAD runtime 输入：$required" >&2
        exit 1
    }
done

for command_name in readelf zip unzip; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "错误：staging 需要 $command_name" >&2
        exit 2
    }
done

mkdir -p "$LIBS_PARENT"
STAGE=$(mktemp -d "$LIBS_PARENT/.arm64-v8a.stage.XXXXXX")
RAW_STAGE=$(mktemp -d "$RAWFILE_PARENT/.rawfile.stage.XXXXXX")
SCAN_FILE="$STAGE/.elf-scan"
trap 'rm -rf -- "$STAGE" "$RAW_STAGE"' EXIT HUP INT TERM

copy_named_library()
{
    source_file=$1
    target_name=$2
    cp -L "$source_file" "$STAGE/$target_name"
}

echo "==> Stage FreeCAD headless modules"
for library in \
    FreeCAD.so Part.so Mesh.so Import.so Materials.so Sketcher.so _PartDesign.so \
    libFreeCADBase.so libFreeCADApp.so; do
    copy_named_library "$FREECAD_PREFIX/lib/$library" "$library"
done

echo "==> Stage CPython 3.11 runtime"
mkdir -p "$STAGE/lib/python3.11/lib-dynload"
for extension in "$PYTHON_ROOT"/lib/python3.11/lib-dynload/*.so; do
    [ -f "$extension" ] || continue
    cp -L "$extension" "$STAGE/lib/python3.11/lib-dynload/"
done
copy_named_library "$PYTHON_ROOT/lib/libpython3.11.so.1.0" libpython3.11.so.1.0
cp -L "$PYTHON_ROOT/lib/libpython3.11.so.1.0" "$STAGE/lib/libpython3.11.so.1.0"

# _ssl is loaded from lib/python3.11/lib-dynload and resolves its OpenSSL
# dependencies through the $ORIGIN/../.. RUNPATH, so keep them in <libs>/lib
# as well as at the top level.
for openssl_library in libssl.so.3 libcrypto.so.3; do
    if [ -e "$PYTHON_ROOT/lib/$openssl_library" ]; then
        copy_named_library "$PYTHON_ROOT/lib/$openssl_library" "$openssl_library"
        cp -L "$PYTHON_ROOT/lib/$openssl_library" "$STAGE/lib/$openssl_library"
    fi
done

if [ -e "$PYTHON_ROOT/lib/libffi.so.8" ]; then
    copy_named_library "$PYTHON_ROOT/lib/libffi.so.8" libffi.so.8
    cp -L "$PYTHON_ROOT/lib/libffi.so.8" "$STAGE/lib/libffi.so.8"
elif [ -e "$LIBFFI_PREFIX/lib/libffi.so.8" ]; then
    copy_named_library "$LIBFFI_PREFIX/lib/libffi.so.8" libffi.so.8
    cp -L "$LIBFFI_PREFIX/lib/libffi.so.8" "$STAGE/lib/libffi.so.8"
else
    echo "错误：缺少 libffi.so.8" >&2
    exit 1
fi

echo "==> Package Python and FreeCAD non-native runtime as rawfiles"
(cd "$PYTHON_ROOT/lib/python3.11" && \
    zip -q -r "$RAW_STAGE/python311.zip" . \
        -x 'lib-dynload/*' 'config-3.11-*/*' '__pycache__/*' '*/__pycache__/*' '*.pyc')
(cd "$FREECAD_PREFIX" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" Mod Ext share \
        -x '*/__pycache__/*' '*.pyc')
# Material imports the Python ``yaml`` package.  Include its pure-Python
# implementation in the runtime archive's Ext/ directory; no
# platform-specific _yaml ELF is copied into rawfile.
PY_YAML_STAGE=$(mktemp -d "$RAW_STAGE/.pyyaml.XXXXXX")
mkdir -p "$PY_YAML_STAGE/Ext"
cp -R "$PY_YAML_ROOT/yaml" "$PY_YAML_STAGE/Ext/"
cp "$PY_YAML_ROOT/LICENSE" "$PY_YAML_STAGE/Ext/yaml/LICENSE"
(cd "$PY_YAML_STAGE" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" Ext/yaml \
        -x '*/__pycache__/*' '*.pyc' '*.so' '*.so.*')
rm -rf "$PY_YAML_STAGE"
PACKAGING_STAGE=$(mktemp -d "$RAW_STAGE/.packaging.XXXXXX")
mkdir -p "$PACKAGING_STAGE/Ext"
cp -R "$PACKAGING_ROOT/packaging" "$PACKAGING_STAGE/Ext/"
cp "$PACKAGING_ROOT"/LICENSE* "$PACKAGING_STAGE/Ext/packaging/"
(cd "$PACKAGING_STAGE" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" Ext/packaging \
        -x '*/__pycache__/*' '*.pyc' '*.so' '*.so.*')
rm -rf "$PACKAGING_STAGE"
echo "==> Stage NumPy Python package and signed native extensions"
NUMPY_STAGE=$(mktemp -d "$RAW_STAGE/.numpy.XXXXXX")
mkdir -p "$NUMPY_STAGE/Ext"
cp -r "$NUMPY_SP/numpy" "$NUMPY_STAGE/Ext/"
cp "$NUMPY_LICENSE" "$NUMPY_STAGE/Ext/numpy/LICENSE.txt"
PATCHELF_BIN="${PATCHELF:-$(command -v patchelf 2>/dev/null || true)}"
find "$NUMPY_STAGE/Ext/numpy" -type f -name '*.so*' -print |
    while IFS= read -r extension; do
        extension_name=$(basename "$extension")
        cp -L "$extension" "$STAGE/$extension_name"
        extension_runpath=$(readelf -d "$STAGE/$extension_name" 2>/dev/null |
            awk '/\(RPATH\)|\(RUNPATH\)/ {sub(/^.*\[/, ""); sub(/\].*$/, ""); print; exit}')
        if printf '%s\n' "$extension_runpath" | tr ':' '\n' | grep -q '^/' && [ -x "$PATCHELF_BIN" ]; then
            "$PATCHELF_BIN" --set-rpath '$ORIGIN' "$STAGE/$extension_name"
        fi
    done
for package_init in \
    "$NUMPY_STAGE/Ext/numpy/_core/__init__.py" \
    "$NUMPY_STAGE/Ext/numpy/fft/__init__.py" \
    "$NUMPY_STAGE/Ext/numpy/linalg/__init__.py" \
    "$NUMPY_STAGE/Ext/numpy/random/__init__.py"; do
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
done
(cd "$NUMPY_STAGE" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" Ext/numpy \
        -x '*.pyc' '*/__pycache__/*' '*.so' '*.so.*' '*.a')
rm -rf "$NUMPY_STAGE"
echo "==> Package FlexiMind headless jobs (GUI Workbench excluded)"
FLEXIMIND_STAGE="$RAW_STAGE/fleximind"
FLEXIMIND_HELPERS="$FLEXIMIND_STAGE/FlexiMind/tools/freecad/FlexiMindGripDesign"
mkdir -p "$FLEXIMIND_STAGE/FlexiMind/workers" "$FLEXIMIND_HELPERS"
cp "$PROJECT_DIR/runtime/fleximind_job_runner.py" "$FLEXIMIND_STAGE/FlexiMind/"
printf '%s\n' '"""FlexiMind runtime package."""' > "$FLEXIMIND_STAGE/FlexiMind/__init__.py"
printf '%s\n' '"""Headless modeling helpers shared with FlexiMind."""' > "$FLEXIMIND_HELPERS/__init__.py"
for worker in \
    worker-a.py \
    worker-b.py \
    worker-c.py; do
    cp "$FLEXIMIND_ROOT/workers/$worker" "$FLEXIMIND_STAGE/FlexiMind/workers/$worker"
done
for helper in registered_base.py reference_geometry.py; do
    cp "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/$helper" "$FLEXIMIND_HELPERS/$helper"
done
(cd "$FLEXIMIND_STAGE" && \
    zip -q -r "$RAW_STAGE/freecad-runtime.zip" FlexiMind \
        -x '*/__pycache__/*' '*.pyc')
rm -rf "$FLEXIMIND_STAGE"
if unzip -Z1 "$RAW_STAGE/freecad-runtime.zip" |
   grep -Eq '^(Mod/FlexiMindGripDesign/|FlexiMind/tools/freecad/FlexiMindGripDesign/(Init.py|InitGui.py|commands.py|scene_state.py|Resources/))'; then
    echo "错误：FlexiMindGripDesign GUI 工作台当前禁用，不得进入 runtime" >&2
    exit 1
fi
cp "$PROJECT_DIR/probes/freecad-headless/acceptance.py" \
    "$RAW_STAGE/freecad_headless_acceptance.py"
unzip -tq "$RAW_STAGE/python311.zip" >/dev/null
unzip -tq "$RAW_STAGE/freecad-runtime.zip" >/dev/null

SEARCH_DIRS="
$FREECAD_PREFIX/lib
$PYTHON_ROOT/lib
$LIBFFI_PREFIX/lib
$OCCT_PREFIX/lib
$QT_PREFIX/lib
$XERCES_PREFIX/lib
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
        for needed in $(readelf -d "$elf" 2>/dev/null | awk '/\(NEEDED\)/ {gsub(/\[|\]/, "", $5); print $5}'); do
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

OLD_DIR="$LIBS_PARENT/.arm64-v8a.previous.$$"
RAW_OLD_DIR="$RAWFILE_PARENT/.rawfile.previous.$$"
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

echo "==> Audit staged runtime"
STAGED_DIR="$LIBS_DIR" RAWFILE_DIR="$RAWFILE_DIR" \
    "$PROJECT_DIR/scripts/audit-headless-hap.sh"

file_count=$(find "$LIBS_DIR" -type f | wc -l | tr -d ' ')
size_kb=$(du -sk "$LIBS_DIR" | awk '{print $1}')
echo "Staged $file_count files ($size_kb KiB): $LIBS_DIR"
echo "Packaged raw runtime: $RAWFILE_DIR"
