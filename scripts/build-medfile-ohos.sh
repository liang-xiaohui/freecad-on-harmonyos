#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

VERSION=6.0.1
SHA256=62f163812e4df09c23e93d42342856a6da438cbf98d9dfe0360ce7b14a92b035
ARCHIVE="$CPP_LIB_ROOT/downloads/medfile/med-$VERSION.tar.gz"
SRC="$CPP_LIB_ROOT/sources/medfile/$VERSION"
BUILD="$CPP_LIB_ROOT/build/medfile/$VERSION/ohos-$ABI"
PREFIX="${MEDFILE_PREFIX:-$CPP_LIB_ROOT/install/medfile/$VERSION/ohos/$ABI}"
HDF5_PREFIX="${HDF5_PREFIX:-$CPP_LIB_ROOT/install/hdf5/1.14.6/ohos/$ABI}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/storage/Users/currentUser/codex-freecad-artifacts}"
URL="https://codeload.github.com/chennes/med/tar.gz/refs/tags/v$VERSION"

[ -f "$HDF5_PREFIX/include/hdf5.h" ] && [ -f "$HDF5_PREFIX/lib/libhdf5.so" ] || {
    echo "Build HDF5 first: sh scripts/build-hdf5-ohos.sh" >&2
    exit 1
}
mkdir -p "$(dirname "$ARCHIVE")" "$(dirname "$SRC")" "$ARTIFACT_DIR"
if [ ! -f "$ARCHIVE" ]; then
    DOWNLOAD_DIR=$(mktemp -d "$ARTIFACT_DIR/medfile-download.XXXXXX")
    curl -fL --retry 2 --connect-timeout 15 -o "$DOWNLOAD_DIR/archive.tar.gz" "$URL"
    mv "$DOWNLOAD_DIR/archive.tar.gz" "$ARCHIVE"
fi
ACTUAL_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
[ "$ACTUAL_SHA256" = "$SHA256" ] || {
    echo "MEDFile archive checksum mismatch: $ARCHIVE ($ACTUAL_SHA256)" >&2
    exit 1
}
if [ ! -f "$SRC/CMakeLists.txt" ]; then
    [ ! -e "$SRC" ] || {
        echo "Refusing to extract into incomplete source directory: $SRC" >&2
        exit 1
    }
    mkdir -p "$SRC"
    tar --no-same-owner --strip-components=1 -xzf "$ARCHIVE" -C "$SRC"
fi

cmake_configure "$SRC" "$BUILD" "$PREFIX" \
    -DCMAKE_PREFIX_PATH="$HDF5_PREFIX" \
    -DCMAKE_FIND_ROOT_PATH="$NATIVE_SDK;$HDF5_PREFIX" \
    -DCMAKE_Fortran_COMPILER:FILEPATH=NOTFOUND \
    -DCMAKE_INSTALL_RPATH='$ORIGIN' \
    -DHDF5_ROOT_DIR="$HDF5_PREFIX" \
    -DMED_MEDINT_TYPE=int \
    -DMEDFILE_BUILD_SHARED_LIBS=ON \
    -DMEDFILE_BUILD_STATIC_LIBS=OFF \
    -DMEDFILE_BUILD_TESTS=OFF \
    -DMEDFILE_BUILD_PYTHON=OFF \
    -DMEDFILE_BUILD_DOC=OFF \
    -DMEDFILE_INSTALL_DOC=OFF
cmake_build_install "$BUILD"
mkdir -p "$PREFIX/share/licenses/medfile"
cp "$SRC/COPYING" "$SRC/COPYING.LESSER" "$PREFIX/share/licenses/medfile/"

[ -f "$PREFIX/lib/libmedC.so" ] && [ -f "$PREFIX/include/med.h" ]
echo "Built MEDFile $VERSION: $PREFIX"
