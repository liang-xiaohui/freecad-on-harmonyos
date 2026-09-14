#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

VERSION=1.14.6
SHA256=e4defbac30f50d64e1556374aa49e574417c9e72c6b1de7a4ff88c4b1bea6e9b
ARCHIVE="$CPP_LIB_ROOT/downloads/hdf5/hdf5-$VERSION.tar.gz"
SRC="$CPP_LIB_ROOT/sources/hdf5/$VERSION"
BUILD="$CPP_LIB_ROOT/build/hdf5/$VERSION/ohos-$ABI"
PREFIX="${HDF5_PREFIX:-$CPP_LIB_ROOT/install/hdf5/$VERSION/ohos/$ABI}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/storage/Users/currentUser/codex-freecad-artifacts}"
URL="https://github.com/HDFGroup/hdf5/releases/download/hdf5_$VERSION/hdf5-$VERSION.tar.gz"

mkdir -p "$(dirname "$ARCHIVE")" "$(dirname "$SRC")" "$ARTIFACT_DIR"
if [ ! -f "$ARCHIVE" ]; then
    DOWNLOAD_DIR=$(mktemp -d "$ARTIFACT_DIR/hdf5-download.XXXXXX")
    curl -fL --retry 2 --connect-timeout 15 -o "$DOWNLOAD_DIR/archive.tar.gz" "$URL"
    mv "$DOWNLOAD_DIR/archive.tar.gz" "$ARCHIVE"
fi
ACTUAL_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
[ "$ACTUAL_SHA256" = "$SHA256" ] || {
    echo "HDF5 archive checksum mismatch: $ARCHIVE ($ACTUAL_SHA256)" >&2
    exit 1
}
if [ ! -f "$SRC/CMakeLists.txt" ]; then
    [ ! -e "$SRC" ] || {
        echo "Refusing to extract into incomplete source directory: $SRC" >&2
        exit 1
    }
    mkdir -p "$SRC"
    tar --no-same-owner --strip-components=2 -xzf "$ARCHIVE" -C "$SRC"
fi

cmake_configure "$SRC" "$BUILD" "$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DHDF5_BUILD_CPP_LIB=OFF \
    -DHDF5_BUILD_FORTRAN=OFF \
    -DHDF5_BUILD_HL_LIB=OFF \
    -DHDF5_BUILD_TOOLS=OFF \
    -DHDF5_BUILD_UTILS=OFF \
    -DHDF5_BUILD_EXAMPLES=OFF \
    -DHDF5_ENABLE_PARALLEL=OFF \
    -DHDF5_ENABLE_THREADSAFE=OFF \
    -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
    -DHDF5_ENABLE_SZIP_SUPPORT=OFF \
    -DZLIB_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include" \
    -DZLIB_LIBRARY="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos/libz.so"
cmake_build_install "$BUILD"

[ -f "$PREFIX/lib/libhdf5.a" ] && [ -f "$PREFIX/lib/libhdf5.so" ] && \
    [ -f "$PREFIX/include/hdf5.h" ]
echo "Built HDF5 $VERSION: $PREFIX"
