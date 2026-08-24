#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

PYTHON_VERSION="${PYTHON_VERSION:-3.11.4}"
PYTHON_SOURCE="$CPP_LIB_ROOT/sources/python/openharmony-master"
SDK_PYTHON="$NATIVE_SDK/llvm/python3"
SDK_PYTHON_BIN="$SDK_PYTHON/bin/python3"
LIBFFI_PREFIX="${LIBFFI_PREFIX:-$CPP_LIB_ROOT/install/libffi/3.4.2/ohos/$ABI}"
BUILD="$CPP_LIB_ROOT/build/python/$PYTHON_VERSION/ohos-$ABI-extensions"
PREFIX="$CPP_LIB_ROOT/install/python/$PYTHON_VERSION/ohos/$ABI"
DYNLOAD="$PREFIX/lib/python3.11/lib-dynload"
STAGED_DYNLOAD="$BUILD/lib-dynload"

"$PROJECT_DIR/scripts/prepare-python-runtime-sources.sh"
[ -f "$LIBFFI_PREFIX/lib/libffi.so.8" ] || \
    "$PROJECT_DIR/scripts/build-libffi-ohos.sh"
[ -x "$SDK_PYTHON_BIN" ] || {
    echo "SDK Python is not executable: $SDK_PYTHON_BIN" >&2
    exit 1
}

if [ ! -f "$PREFIX/lib/libpython3.11.so.1.0" ]; then
    mkdir -p "$PREFIX"
    cp -R "$SDK_PYTHON/." "$PREFIX/"
fi
cp "$LIBFFI_PREFIX/lib/libffi.so.8.1.0" "$PREFIX/lib/libffi.so.8.1.0.new"
mv -f "$PREFIX/lib/libffi.so.8.1.0.new" "$PREFIX/lib/libffi.so.8.1.0"
ln -sfn libffi.so.8.1.0 "$PREFIX/lib/libffi.so.8"
ln -sfn libffi.so.8 "$PREFIX/lib/libffi.so"

mkdir -p "$BUILD"
export CC="$CLANG_BIN --target=aarch64-linux-ohos --sysroot=$NATIVE_SDK/sysroot"
export LDSHARED="$CLANG_BIN --target=aarch64-linux-ohos --sysroot=$NATIVE_SDK/sysroot -shared -fuse-ld=lld -Wl,-z,relro,-z,now -Wl,-z,noexecstack -Wl,-rpath,\$ORIGIN/../.."
export CFLAGS="-O2 -fPIC -fstack-protector-strong"
export CPPFLAGS="--target=aarch64-linux-ohos --sysroot=$NATIVE_SDK/sysroot"
export LDFLAGS="-L$PREFIX/lib -L$LIBFFI_PREFIX/lib"

"$SDK_PYTHON_BIN" "$PROJECT_DIR/tools/build-python-extensions.py" \
    --source "$PYTHON_SOURCE" \
    --python-prefix "$PREFIX" \
    --libffi-prefix "$LIBFFI_PREFIX" \
    --build-temp "$BUILD/objects" \
    --output-dir "$STAGED_DYNLOAD"

for module in _socket binascii zlib _ctypes; do
    staged_file=$(find "$STAGED_DYNLOAD" -maxdepth 1 \
        -name "$module.cpython-311-*.so" -print | head -n 1)
    [ -n "$staged_file" ] || {
        echo "Built extension is missing: $module" >&2
        exit 1
    }
    destination="$DYNLOAD/$(basename "$staged_file")"
    cp "$staged_file" "$destination.new"
    mv -f "$destination.new" "$destination"
done

PYTHON_ROOT="$PREFIX" "$PROJECT_DIR/scripts/audit-python-runtime-ohos.sh"
PYTHON_ROOT="$PREFIX" PYTHON_BIN="$SDK_PYTHON_BIN" \
    "$PROJECT_DIR/scripts/run-python-runtime-probe.sh"

echo "Built extended Python $PYTHON_VERSION runtime: $PREFIX"
