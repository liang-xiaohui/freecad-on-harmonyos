#!/bin/sh
# Fetch the header-only pybind11 dependency used by FreeCAD CAM/flat-mesh.
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
PYBIND11_VERSION="${PYBIND11_VERSION:-2.13.6}"
PYBIND11_ROOT="${PYBIND11_ROOT:-$CPP_LIB_ROOT/sources/pybind11/pybind11-$PYBIND11_VERSION}"
SOURCE_PARENT="$CPP_LIB_ROOT/sources/pybind11"
ARCHIVE="$SOURCE_PARENT/pybind11-$PYBIND11_VERSION.tar.gz"
URL="https://github.com/pybind/pybind11/archive/refs/tags/v$PYBIND11_VERSION.tar.gz"

if [ -f "$PYBIND11_ROOT/include/pybind11/pybind11.h" ]; then
    echo "pybind11 $PYBIND11_VERSION is ready: $PYBIND11_ROOT"
    exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "错误：准备 pybind11 需要 curl" >&2; exit 2; }
command -v tar >/dev/null 2>&1 || { echo "错误：准备 pybind11 需要 tar" >&2; exit 2; }
mkdir -p "$SOURCE_PARENT"
[ -f "$ARCHIVE" ] || curl -L --fail --retry 3 -o "$ARCHIVE" "$URL"
tar -xzf "$ARCHIVE" -C "$SOURCE_PARENT"
[ -f "$PYBIND11_ROOT/include/pybind11/pybind11.h" ] || {
    echo "错误：pybind11 解压后缺少头文件：$PYBIND11_ROOT/include/pybind11/pybind11.h" >&2
    exit 1
}
echo "pybind11 $PYBIND11_VERSION is ready: $PYBIND11_ROOT"
