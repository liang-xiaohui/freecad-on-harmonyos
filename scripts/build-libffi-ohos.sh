#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

VERSION="${LIBFFI_VERSION:-3.4.2}"
SOURCE_REPOSITORY="$CPP_LIB_ROOT/sources/libffi/openharmony-master"
GENERATED_ROOT="$CPP_LIB_ROOT/build/libffi/$VERSION/openharmony-source"
SOURCE="$GENERATED_ROOT/libffi-$VERSION"
PREFIX="$CPP_LIB_ROOT/install/libffi/$VERSION/ohos/$ABI"

[ -f "$SOURCE_REPOSITORY/libffi-$VERSION.tar.gz" ] || \
    "$PROJECT_DIR/scripts/prepare-python-runtime-sources.sh"

"$CMAKE_BIN" -E remove_directory "$GENERATED_ROOT"
mkdir -p "$GENERATED_ROOT"
tar -xzf "$SOURCE_REPOSITORY/libffi-$VERSION.tar.gz" -C "$GENERATED_ROOT"

# install.py uses GNU patch options that Toybox patch does not implement.
# Keep the official patch order but use git apply, which also handles CRLF patches.
for patch_name in \
    backport-x86-64-Always-double-jump-table-slot-size-for-CET-71.patch \
    backport-Fix-check-for-invalid-varargs-arguments-707.patch \
    libffi-Add-sw64-architecture.patch \
    backport-Fix-signed-vs-unsigned-comparison.patch \
    riscv-extend-return-types-smaller-than-ffi_arg-680.patch \
    fix-AARCH64EB-support.patch \
    backport-openharmony-adapt.patch \
    backport-openharmony-dummy.patch
do
    patch_file="$SOURCE_REPOSITORY/patch/$patch_name"
    [ -s "$patch_file" ] || continue
    git -C "$SOURCE" apply --ignore-space-change --ignore-whitespace "$patch_file"
done
git -C "$SOURCE" apply \
    "$PROJECT_DIR/patches/libffi-3.4.2/ohos-trampoline-path.patch"

[ -f "$SOURCE/fficonfig.h" ] || {
    echo "Patched libffi source is incomplete: $SOURCE" >&2
    exit 1
}

mkdir -p "$PREFIX/include" "$PREFIX/lib"

"$CLANG_BIN" \
    --target=aarch64-linux-ohos \
    --sysroot="$NATIVE_SDK/sysroot" \
    -O2 -fPIC \
    -DTARGET=AARCH64 -DFFI_BUILDING \
    -Wno-sign-compare -Wno-implicit-function-declaration \
    -I"$SOURCE" -I"$SOURCE/include" -I"$SOURCE/src/aarch64" \
    -shared -fuse-ld=lld \
    -Wl,-soname,libffi.so.8 \
    -Wl,-z,relro,-z,now -Wl,-z,noexecstack \
    "$SOURCE/src/aarch64/ffi.c" \
    "$SOURCE/src/aarch64/sysv.S" \
    "$SOURCE/src/closures.c" \
    "$SOURCE/src/java_raw_api.c" \
    "$SOURCE/src/prep_cif.c" \
    "$SOURCE/src/raw_api.c" \
    "$SOURCE/src/tramp.c" \
    "$SOURCE/src/types.c" \
    -o "$PREFIX/lib/libffi.so.8.1.0"

cp "$SOURCE/include/ffi.h" "$PREFIX/include/ffi.h"
cp "$SOURCE/src/aarch64/ffitarget.h" "$PREFIX/include/ffitarget.h"
ln -sfn libffi.so.8.1.0 "$PREFIX/lib/libffi.so.8"
ln -sfn libffi.so.8 "$PREFIX/lib/libffi.so"

echo "Built libffi $VERSION for OpenHarmony: $PREFIX"
