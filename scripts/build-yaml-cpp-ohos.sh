#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

VERSION="${YAML_CPP_VERSION:-0.8.0}"
SHA256="${YAML_CPP_SHA256:-fbe74bbdcee21d656715688706da3c8becfd946d92cd44705cc6098bb23b3a16}"
ARCHIVE="$CPP_LIB_ROOT/downloads/yaml-cpp/yaml-cpp-$VERSION.tar.gz"
SRC="$CPP_LIB_ROOT/sources/yaml-cpp/$VERSION"
BUILD="$CPP_LIB_ROOT/build/yaml-cpp/$VERSION/ohos-$ABI"
PREFIX="$CPP_LIB_ROOT/install/yaml-cpp/$VERSION/ohos/$ABI"
URL="https://codeload.github.com/jbeder/yaml-cpp/tar.gz/refs/tags/$VERSION"

mkdir -p "$(dirname "$ARCHIVE")" "$(dirname "$SRC")"
if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading yaml-cpp $VERSION"
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

cmake_configure "$SRC" "$BUILD" "$PREFIX" \
    -DBUILD_TESTING=OFF \
    -DYAML_BUILD_SHARED_LIBS=OFF \
    -DYAML_CPP_BUILD_TESTS=OFF \
    -DYAML_CPP_BUILD_TOOLS=OFF \
    -DYAML_CPP_FORMAT_SOURCE=OFF \
    -DYAML_CPP_INSTALL=ON
cmake_build_install "$BUILD"

echo "Built yaml-cpp $VERSION: $PREFIX"
