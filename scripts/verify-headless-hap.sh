#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# 这个脚本校验的是内部包（无头验收 + FlexiMind 作业）：私有输入清单与条目断言
# 全部来自外部钩子 —— 本仓库是公开的，不含这些信息。见 scripts/fleximind-hook.sh。
. "$PROJECT_DIR/scripts/fleximind-hook.sh"
fleximind_load_hook
PY_YAML_ROOT="$PROJECT_DIR/runtime/pyyaml"
PACKAGING_ROOT="$PROJECT_DIR/runtime/packaging"
ABI="${ABI:-arm64-v8a}"
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
NUMPY_SP="${NUMPY_SP:-$CPP_LIB_ROOT/install/numpy/2.2.6/ohos/$ABI/site-packages}"
NUMPY_LICENSE="$NUMPY_SP/numpy-2.2.6.dist-info/LICENSE.txt"
STAGED_DIR="$PROJECT_DIR/entry/libs/$ABI"
RAWFILE_DIR="$PROJECT_DIR/entry/src/main/resources/rawfile"
DEFAULT_OUTPUT="$PROJECT_DIR/entry/build/default/outputs/default"

if [ -z "${HAP:-}" ]; then
    for candidate in \
        "$DEFAULT_OUTPUT/entry-default-signed.hap" \
        "$DEFAULT_OUTPUT/entry-default-unsigned.hap" \
        "$DEFAULT_OUTPUT/entry-default.hap"; do
        if [ -f "$candidate" ]; then
            HAP=$candidate
            break
        fi
    done
fi

[ -n "${HAP:-}" ] && [ -f "$HAP" ] || {
    echo "错误：未找到 HAP；可通过 HAP=/path/to/file.hap 指定" >&2
    exit 2
}
[ -d "$STAGED_DIR" ] || {
    echo "错误：请先运行 scripts/stage-headless-hap.sh" >&2
    exit 2
}

HAP_LIST=$(mktemp)
STAGED_LIST=$(mktemp)
RUNTIME_ZIP=$(mktemp)
trap 'rm -f "$HAP_LIST" "$STAGED_LIST" "$RUNTIME_ZIP"' EXIT HUP INT TERM

unzip -Z1 "$HAP" | sort > "$HAP_LIST"
find "$STAGED_DIR" -type f -printf '%P\n' | while IFS= read -r relative; do
    printf 'libs/%s/%s\n' "$ABI" "$relative"
done | sort > "$STAGED_LIST"

failed=0
while IFS= read -r entry; do
    if ! grep -Fx "$entry" "$HAP_LIST" >/dev/null; then
        echo "MISSING $entry"
        failed=1
    fi
done < "$STAGED_LIST"

for required in \
    "libs/$ABI/libfreecadacceptance.so" \
    "libs/$ABI/libc++_shared.so" \
    "libs/$ABI/FreeCAD.so" \
    "libs/$ABI/Part.so" \
    "libs/$ABI/Mesh.so" \
    "libs/$ABI/Import.so" \
    "libs/$ABI/Materials.so" \
    "libs/$ABI/Sketcher.so" \
    "libs/$ABI/_PartDesign.so" \
    "libs/$ABI/_multiarray_umath.cpython-311-aarch64-linux-ohos.so" \
    "libs/$ABI/_pocketfft_umath.cpython-311-aarch64-linux-ohos.so" \
    "libs/$ABI/_umath_linalg.cpython-311-aarch64-linux-ohos.so" \
    "resources/rawfile/python311.zip" \
    "resources/rawfile/freecad-runtime.zip" \
    "resources/rawfile/freecad_headless_acceptance.py"; do
    if ! grep -Fx "$required" "$HAP_LIST" >/dev/null; then
        echo "MISSING $required"
        failed=1
    fi
done

if grep -Fx "libs/$ABI/libentry.so" "$HAP_LIST" >/dev/null; then
    echo "STALE   libs/$ABI/libentry.so (old native module name)"
    failed=1
fi


for rawfile in python311.zip freecad-runtime.zip freecad_headless_acceptance.py; do
    if [ ! -f "$RAWFILE_DIR/$rawfile" ]; then
        echo "MISSING $RAWFILE_DIR/$rawfile"
        failed=1
    fi
done

for source in \
    "$PROJECT_DIR/entry/oh-package.json5" \
    "$PROJECT_DIR/entry/src/main/cpp/types/libfreecadacceptance/oh-package.json5" \
    "$PROJECT_DIR/entry/src/main/cpp/acceptance.cpp" \
    "$PROJECT_DIR/entry/src/main/ets/pages/Index.ets" \
    "$PROJECT_DIR/entry/src/main/ets/entryability/EntryAbility.ets" \
    "$PROJECT_DIR/entry/src/main/module.json5" \
    "$PROJECT_DIR/probes/freecad-headless/acceptance.py" \
    $(fleximind_input_files) \
    "$PY_YAML_ROOT/LICENSE" \
    "$PY_YAML_ROOT/yaml/__init__.py" \
    "$PACKAGING_ROOT/LICENSE" \
    "$PACKAGING_ROOT/LICENSE.APACHE" \
    "$PACKAGING_ROOT/LICENSE.BSD" \
    "$PACKAGING_ROOT/packaging/__init__.py" \
    "$NUMPY_LICENSE" \
    "$NUMPY_SP/numpy/__init__.py"; do
    if [ "$source" -nt "$HAP" ]; then
        echo "STALE   $source"
        failed=1
    fi
done
for source in "$PY_YAML_ROOT"/yaml/*.py; do
    [ -f "$source" ] || continue
    if [ "$source" -nt "$HAP" ]; then
        echo "STALE   $source"
        failed=1
    fi
done
newer_packaging=$(find "$PACKAGING_ROOT" -type f -newer "$HAP" -print -quit)
if [ -n "$newer_packaging" ]; then
    echo "STALE   $newer_packaging"
    failed=1
fi
newer_numpy=$(find "$NUMPY_SP/numpy" -type f -newer "$HAP" -print -quit)
if [ -n "$newer_numpy" ]; then
    echo "STALE   $newer_numpy"
    failed=1
fi

if ! unzip -p "$HAP" resources/rawfile/freecad-runtime.zip > "$RUNTIME_ZIP"; then
    echo "MISSING resources/rawfile/freecad-runtime.zip"
    failed=1
fi
for entry in $(fleximind_payload_entries); do
    if ! unzip -Z1 "$RUNTIME_ZIP" | grep -Fqx "$entry"; then
        echo "MISSING resources/rawfile/freecad-runtime.zip:$entry"
        failed=1
    fi
done
if unzip -Z1 "$RUNTIME_ZIP" | grep -Eq "$(fleximind_forbidden_pattern)"; then
    echo "UNEXPECTED resources/rawfile/freecad-runtime.zip:FlexiMindGripDesign GUI Workbench"
    failed=1
fi

for entry in Ext/yaml/__init__.py Ext/yaml/loader.py Ext/yaml/dumper.py Ext/yaml/LICENSE; do
    if ! unzip -p "$HAP" resources/rawfile/freecad-runtime.zip > "$RUNTIME_ZIP" || \
       ! unzip -Z1 "$RUNTIME_ZIP" | grep -q "^${entry}$"; then
        echo "MISSING resources/rawfile/freecad-runtime.zip:$entry"
        failed=1
    fi
done
for entry in Ext/packaging/__init__.py Ext/packaging/version.py Ext/packaging/utils.py \
             Ext/packaging/LICENSE Ext/packaging/LICENSE.APACHE Ext/packaging/LICENSE.BSD; do
    if ! unzip -p "$HAP" resources/rawfile/freecad-runtime.zip > "$RUNTIME_ZIP" || \
       ! unzip -Z1 "$RUNTIME_ZIP" | grep -q "^${entry}$"; then
        echo "MISSING resources/rawfile/freecad-runtime.zip:$entry"
        failed=1
    fi
done
for entry in Ext/numpy/__init__.py Ext/numpy/_core/__init__.py Ext/numpy/fft/__init__.py \
             Ext/numpy/linalg/__init__.py Ext/numpy/random/__init__.py Ext/numpy/LICENSE.txt; do
    if ! unzip -p "$HAP" resources/rawfile/freecad-runtime.zip > "$RUNTIME_ZIP" || \
       ! unzip -Z1 "$RUNTIME_ZIP" | grep -q "^${entry}$"; then
        echo "MISSING resources/rawfile/freecad-runtime.zip:$entry"
        failed=1
    fi
done

for package in numpy/_core numpy/fft numpy/linalg numpy/random; do
    if ! unzip -p "$RUNTIME_ZIP" "Ext/$package/__init__.py" |
         grep -q 'FREECAD_APP_LIBRARY_DIR'; then
        echo "MISSING native path setup in resources/rawfile/freecad-runtime.zip:Ext/$package/__init__.py"
        failed=1
    fi
done

newer_runtime=$(find "$STAGED_DIR" "$RAWFILE_DIR" -type f -newer "$HAP" -print | sed -n '1p')
if [ -n "$newer_runtime" ]; then
    echo "STALE   $newer_runtime"
    failed=1
fi

for rawfile in python311.zip freecad-runtime.zip freecad_headless_acceptance.py; do
    staged_hash=$(sha256sum "$RAWFILE_DIR/$rawfile" | awk '{print $1}')
    hap_hash=$(unzip -p "$HAP" "resources/rawfile/$rawfile" | sha256sum | awk '{print $1}')
    if [ "$staged_hash" != "$hap_hash" ]; then
        echo "STALE   resources/rawfile/$rawfile"
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    echo "HAP does not contain the current headless acceptance runtime" >&2
    exit 1
fi

entry_count=$(wc -l < "$STAGED_LIST" | tr -d ' ')
echo "Verified $entry_count staged runtime files in: $HAP"
