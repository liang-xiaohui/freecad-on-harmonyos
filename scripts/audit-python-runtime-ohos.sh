#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

PYTHON_VERSION="${PYTHON_VERSION:-3.11.4}"
PREFIX="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/$PYTHON_VERSION/ohos/$ABI}"
DYNLOAD="$PREFIX/lib/python3.11/lib-dynload"
READELF_BIN="${READELF_BIN:-$(command -v readelf)}"
EXPECTED_RUNPATH='$ORIGIN/../..'
MODULES="_socket binascii zlib _ctypes _ssl"

for module in $MODULES; do
    file=$(find "$DYNLOAD" -maxdepth 1 -name "$module.cpython-311-*.so" -print | head -n 1)
    [ -n "$file" ] || {
        echo "Missing Python extension: $module" >&2
        exit 1
    }
    "$READELF_BIN" -h "$file" | grep -q 'Machine:.*AArch64' || {
        echo "Not an AArch64 ELF: $file" >&2
        exit 1
    }
    "$READELF_BIN" -d "$file" | grep -Fq "Library runpath: [$EXPECTED_RUNPATH]" || {
        echo "Unexpected RUNPATH: $file" >&2
        "$READELF_BIN" -d "$file" | grep -E 'RPATH|RUNPATH' >&2 || true
        exit 1
    }
    if "$READELF_BIN" -d "$file" | grep -E '/storage|/data/service|/data/app' >/dev/null; then
        echo "Absolute build path leaked into $file" >&2
        exit 1
    fi
    echo "OK $(basename "$file")"
done

"$READELF_BIN" -h "$PREFIX/lib/libffi.so.8.1.0" | grep -q 'Machine:.*AArch64'
"$READELF_BIN" -d "$PREFIX/lib/libffi.so.8.1.0" | grep -Fq 'Library soname: [libffi.so.8]'
for symbol in ffi_call ffi_closure_alloc ffi_prep_cif ffi_prep_cif_var; do
    "$READELF_BIN" -Ws "$PREFIX/lib/libffi.so.8.1.0" | \
        grep -Eq "GLOBAL +DEFAULT +[0-9]+ +$symbol$" || {
            echo "libffi does not export $symbol" >&2
            exit 1
        }
done
echo "Python runtime ELF audit passed"
