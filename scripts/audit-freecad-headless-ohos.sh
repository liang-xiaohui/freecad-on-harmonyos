#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
PREFIX="$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-headless"
QT_PREFIX="${QT_PREFIX:-$CPP_LIB_ROOT/install/qt/5.12.12-src/ohos/$ABI}"
XERCES_PREFIX="${XERCES_PREFIX:-$CPP_LIB_ROOT/install/xerces-c/3.2.4/ohos/$ABI}"
OCCT_PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/7.8.1/ohos/$ABI}"
PYTHON_ROOT="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI}"
SYSROOT_LIB="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos"
TOOLCHAIN_LIB="$NATIVE_SDK/llvm/lib/aarch64-linux-ohos"

command -v readelf >/dev/null 2>&1 || {
    echo "readelf is required for the FreeCAD ELF audit" >&2
    exit 2
}

SEARCH_DIRS="
$PREFIX/lib
$QT_PREFIX/lib
$XERCES_PREFIX/lib
$OCCT_PREFIX/lib
$PYTHON_ROOT/lib
$TOOLCHAIN_LIB
$SYSROOT_LIB
$NATIVE_SDK/sysroot/usr/lib
"

resolve_library()
{
    library_name=$1
    for search_dir in $SEARCH_DIRS; do
        if [ -e "$search_dir/$library_name" ]; then
            return 0
        fi
    done
    return 1
}

failed=0

audit_elf()
{
    relative_path=$1
    expected_runpath=$2
    elf="$PREFIX/$relative_path"

    if [ ! -f "$elf" ]; then
        echo "MISSING $relative_path"
        failed=1
        return
    fi

    if ! readelf -h "$elf" | grep -F "Machine:" | grep -F "AArch64" >/dev/null; then
        echo "FAIL    $relative_path is not AArch64"
        failed=1
        return
    fi

    runpath=$(readelf -d "$elf" | sed -n 's/.*Library runpath: \[\(.*\)\]/\1/p')
    if [ "$runpath" != "$expected_runpath" ]; then
        echo "FAIL    $relative_path RUNPATH=$runpath expected=$expected_runpath"
        failed=1
    fi

    for needed in $(readelf -d "$elf" | awk '/\(NEEDED\)/ {gsub(/\[|\]/, "", $5); print $5}'); do
        if ! resolve_library "$needed"; then
            echo "MISSING $relative_path -> $needed"
            failed=1
        fi
    done

    echo "OK      $relative_path"
}

audit_elf bin/FreeCADCmd '$ORIGIN/../lib'
for library in \
    lib/FreeCAD.so \
    lib/Import.so \
    lib/Materials.so \
    lib/Mesh.so \
    lib/Part.so \
    lib/Sketcher.so \
    lib/_PartDesign.so \
    lib/libFreeCADApp.so \
    lib/libFreeCADBase.so; do
    audit_elf "$library" '$ORIGIN'
done

if [ "$failed" -ne 0 ]; then
    echo "FreeCAD ELF audit failed" >&2
    exit 1
fi

echo "FreeCAD headless ELF audit passed"
