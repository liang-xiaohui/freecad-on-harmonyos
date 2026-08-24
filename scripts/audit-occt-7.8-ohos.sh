#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

VERSION="${OCCT_VERSION:-7.8.1}"
PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/$VERSION/ohos/$ABI}"
SYSTEM_DIRS="
$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos
$NATIVE_SDK/sysroot/usr/lib
$NATIVE_SDK/llvm/lib/aarch64-linux-ohos
"

[ -d "$PREFIX/lib" ] || {
    echo "OCCT install is missing: $PREFIX" >&2
    exit 2
}
command -v readelf >/dev/null 2>&1 || {
    echo "readelf is required for the OCCT ELF audit" >&2
    exit 2
}

for library in \
    TKernel TKMath TKG2d TKG3d TKGeomBase TKBRep TKGeomAlgo TKTopAlgo \
    TKPrim TKBO TKBool TKShHealing TKMesh TKService TKV3d TKCDF TKLCAF \
    TKCAF TKBinL TKBin TKDE TKXSBase TKDESTEP TKDEIGES TKDESTL TKRWMesh; do
    [ -f "$PREFIX/lib/lib$library.so" ] || {
        echo "MISSING lib$library.so" >&2
        exit 1
    }
done

is_resolved()
{
    needed=$1
    if [ -e "$PREFIX/lib/$needed" ]; then
        return 0
    fi
    for directory in $SYSTEM_DIRS; do
        if [ -e "$directory/$needed" ]; then
            return 0
        fi
    done
    return 1
}

failed=0
elf_count=0
for elf in "$PREFIX"/lib/lib*.so; do
    [ -e "$elf" ] || continue
    relative=${elf#"$PREFIX"/}
    elf_count=$((elf_count + 1))

    if ! readelf -h "$elf" 2>/dev/null | grep -F 'Machine:' | grep -F 'AArch64' >/dev/null; then
        echo "FAIL    $relative is not AArch64"
        failed=1
        continue
    fi

    runpath=$(readelf -d "$elf" 2>/dev/null | sed -n 's/.*Library runpath: \[\(.*\)\]/\1/p')
    if [ "$runpath" != '$ORIGIN' ]; then
        echo "FAIL    $relative RUNPATH=$runpath expected=\$ORIGIN"
        failed=1
    fi

    for needed in $(readelf -d "$elf" 2>/dev/null | awk '/\(NEEDED\)/ {gsub(/\[|\]/, "", $5); print $5}'); do
        if ! is_resolved "$needed"; then
            echo "MISSING $relative -> $needed"
            failed=1
        fi
    done
done

if [ "$failed" -ne 0 ]; then
    echo "OCCT $VERSION ELF audit failed" >&2
    exit 1
fi

echo "OCCT $VERSION ELF audit passed ($elf_count AArch64 shared libraries)"
