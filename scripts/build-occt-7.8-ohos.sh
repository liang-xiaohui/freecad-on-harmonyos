#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

VERSION="${OCCT_VERSION:-7.8.1}"
SHA256="${OCCT_SHA256:-7321af48c34dc253bf8aae3f0430e8cb10976961d534d8509e72516978aa82f5}"
TAG="V$(printf '%s' "$VERSION" | tr . _)"
ARCHIVE="$CPP_LIB_ROOT/downloads/occt/OCCT-$VERSION.tar.gz"
SRC="$CPP_LIB_ROOT/sources/occt/$VERSION"
BUILD="$CPP_LIB_ROOT/build/occt/$VERSION/ohos-$ABI-ninja"
PREFIX="$CPP_LIB_ROOT/install/occt/$VERSION/ohos/$ABI"
URL="https://codeload.github.com/Open-Cascade-SAS/OCCT/tar.gz/refs/tags/$TAG"
PATCH_FILE="$PROJECT_DIR/patches/occt-$VERSION/ohos.patch"

if [ "$VERSION" != "7.8.1" ] && [ -z "${OCCT_SHA256:-}" ]; then
    echo "OCCT_SHA256 is required for version $VERSION" >&2
    exit 1
fi
[ -f "$PATCH_FILE" ] || {
    echo "Missing HarmonyOS patch: $PATCH_FILE" >&2
    exit 1
}

mkdir -p "$(dirname "$ARCHIVE")" "$(dirname "$SRC")"
if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading OCCT $VERSION"
    curl -fL --retry 2 --connect-timeout 15 -o "$ARCHIVE.part" "$URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi

actual_sha256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
if [ "$actual_sha256" != "$SHA256" ]; then
    echo "Checksum mismatch for $ARCHIVE" >&2
    echo "expected: $SHA256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
fi

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    [ ! -e "$SRC" ] || {
        echo "Refusing to extract into incomplete directory: $SRC" >&2
        exit 1
    }
    mkdir -p "$SRC"
    tar --no-same-owner --strip-components=1 -xzf "$ARCHIVE" -C "$SRC"
fi

if git -C "$SRC" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "OCCT patch already applied: $(basename "$PATCH_FILE")"
elif git -C "$SRC" apply --check "$PATCH_FILE"; then
    git -C "$SRC" apply "$PATCH_FILE"
    echo "Applied OCCT patch: $(basename "$PATCH_FILE")"
else
    echo "OCCT patch does not apply cleanly: $PATCH_FILE" >&2
    exit 1
fi

cmake_configure "$SRC" "$BUILD" "$PREFIX" \
    -DBUILD_LIBRARY_TYPE=Shared \
    -DBUILD_MODULE_FoundationClasses=ON \
    -DBUILD_MODULE_ModelingData=ON \
    -DBUILD_MODULE_ModelingAlgorithms=ON \
    -DBUILD_MODULE_Visualization=ON \
    -DBUILD_MODULE_ApplicationFramework=ON \
    -DBUILD_MODULE_DataExchange=ON \
    -DBUILD_MODULE_DETools=OFF \
    -DBUILD_MODULE_Draw=OFF \
    -DBUILD_SAMPLES_QT=OFF \
    -DBUILD_Inspector=OFF \
    -DINSTALL_TEST_CASES=OFF \
    -DINSTALL_SAMPLES=OFF \
    -DBUILD_DOC_Overview=OFF \
    -DBUILD_RESOURCES=OFF \
    -DBUILD_YACCLEX=OFF \
    -DBUILD_RELEASE_DISABLE_EXCEPTIONS=OFF \
    -DUSE_TK=OFF \
    -DUSE_FREETYPE=OFF \
    -DUSE_FREEIMAGE=OFF \
    -DUSE_FFMPEG=OFF \
    -DUSE_OPENVR=OFF \
    -DUSE_DRACO=OFF \
    -DUSE_TBB=OFF \
    -DUSE_EIGEN=OFF \
    -DUSE_VTK=OFF \
    -DUSE_XLIB=OFF \
    -DUSE_OPENGL=OFF \
    -DUSE_GLES2=OFF \
    -DINSTALL_DIR_LIB=lib \
    -DINSTALL_DIR_BIN=bin \
    -DINSTALL_DIR_INCLUDE=include/opencascade \
    -DINSTALL_DIR_CMAKE=lib/cmake/opencascade \
    -DCMAKE_INSTALL_RPATH='$ORIGIN'

cmake_build_install "$BUILD"
OCCT_VERSION="$VERSION" OCCT_PREFIX="$PREFIX" "$PROJECT_DIR/scripts/audit-occt-7.8-ohos.sh"
echo "Built OCCT $VERSION: $PREFIX"
