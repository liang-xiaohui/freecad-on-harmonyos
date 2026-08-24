#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

READELF=$(command -v readelf 2>/dev/null || command -v llvm-readelf 2>/dev/null || true)
[ -n "$READELF" ] || { echo "错误：audit 需要 readelf 或 llvm-readelf" >&2; exit 2; }

STAGED_DIR="${STAGED_DIR:-$PROJECT_DIR/entry/libs/$ABI}"
RAWFILE_DIR="${RAWFILE_DIR:-$PROJECT_DIR/entry/src/main/resources/rawfile}"
SYSTEM_DIRS="
$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos
$NATIVE_SDK/sysroot/usr/lib
$NATIVE_SDK/llvm/lib/aarch64-linux-ohos
"

[ -d "$STAGED_DIR" ] || {
    echo "错误：staged runtime 不存在：$STAGED_DIR" >&2
    exit 2
}

for required in \
    FreeCAD.so Part.so Mesh.so Import.so Materials.so Sketcher.so _PartDesign.so \
    libFreeCADBase.so libFreeCADApp.so \
    libpython3.11.so.1.0 libffi.so.8 \
    lib/python3.11/lib-dynload/_socket.cpython-311-aarch64-linux-ohos.so \
    lib/python3.11/lib-dynload/_ctypes.cpython-311-aarch64-linux-ohos.so \
    lib/python3.11/lib-dynload/binascii.cpython-311-aarch64-linux-ohos.so \
    lib/python3.11/lib-dynload/zlib.cpython-311-aarch64-linux-ohos.so; do
    [ -f "$STAGED_DIR/$required" ] || {
        echo "MISSING $required" >&2
        exit 1
    }
done

for required in python311.zip freecad-runtime.zip freecad_headless_acceptance.py; do
    [ -f "$RAWFILE_DIR/$required" ] || {
        echo "MISSING rawfile/$required" >&2
        exit 1
    }
done
unzip -tq "$RAWFILE_DIR/python311.zip" >/dev/null
unzip -tq "$RAWFILE_DIR/freecad-runtime.zip" >/dev/null
unzip -Z1 "$RAWFILE_DIR/python311.zip" | grep -Fx 'encodings/__init__.py' >/dev/null
unzip -Z1 "$RAWFILE_DIR/python311.zip" | grep -Fx 'json/__init__.py' >/dev/null
unzip -Z1 "$RAWFILE_DIR/freecad-runtime.zip" | grep -Fx 'Mod/Part/Init.py' >/dev/null
unzip -Z1 "$RAWFILE_DIR/freecad-runtime.zip" | grep -Fx 'Mod/PartDesign/Init.py' >/dev/null
unzip -Z1 "$RAWFILE_DIR/freecad-runtime.zip" | grep -Fx 'Mod/Sketcher/Init.py' >/dev/null

is_resolved()
{
    elf=$1
    needed=$2
    elf_dir=$(dirname "$elf")
    for directory in "$elf_dir" "$STAGED_DIR" "$STAGED_DIR/lib" $SYSTEM_DIRS; do
        if [ -e "$directory/$needed" ]; then
            return 0
        fi
    done
    return 1
}

failed=0
elf_count=0
find "$STAGED_DIR" -type f -name '*.so*' | while IFS= read -r elf; do
    relative=${elf#"$STAGED_DIR"/}
    if ! "$READELF" -h "$elf" 2>/dev/null | grep -F 'Machine:' | grep -F 'AArch64' >/dev/null; then
        echo "FAIL    $relative is not AArch64"
        printf '%s\n' "$relative" >> "$STAGED_DIR/.audit-failed"
        continue
    fi

    runpath=$("$READELF" -d "$elf" 2>/dev/null | sed -n 's/.*Library runpath: \[\(.*\)\]/\1/p')
    case "$runpath" in
        *'/storage/'*|*'/data/'*|*'/srv/'*)
            echo "FAIL    $relative has absolute RUNPATH=$runpath"
            printf '%s\n' "$relative" >> "$STAGED_DIR/.audit-failed"
            ;;
    esac

    for needed in $("$READELF" -d "$elf" 2>/dev/null | awk '/\(NEEDED\)/ {gsub(/\[|\]/, "", $5); print $5}'); do
        if ! is_resolved "$elf" "$needed"; then
            echo "MISSING $relative -> $needed"
            printf '%s\n' "$relative -> $needed" >> "$STAGED_DIR/.audit-failed"
        fi
    done
    echo "$relative" >> "$STAGED_DIR/.audit-seen"
done

if [ -f "$STAGED_DIR/.audit-failed" ]; then
    failed=1
fi
if [ -f "$STAGED_DIR/.audit-seen" ]; then
    elf_count=$(wc -l < "$STAGED_DIR/.audit-seen" | tr -d ' ')
fi
rm -f "$STAGED_DIR/.audit-failed" "$STAGED_DIR/.audit-seen"

if [ "$failed" -ne 0 ]; then
    echo "Headless HAP runtime audit failed" >&2
    exit 1
fi

echo "Headless HAP runtime audit passed ($elf_count AArch64 ELF files plus rawfile runtime)"
