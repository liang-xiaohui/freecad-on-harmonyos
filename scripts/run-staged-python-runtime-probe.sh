#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

STAGED_DIR="${STAGED_DIR:-$PROJECT_DIR/entry/libs/$ABI}"
RAWFILE_DIR="${RAWFILE_DIR:-$PROJECT_DIR/entry/src/main/resources/rawfile}"
PYTHON_BIN="${PYTHON_BIN:-$NATIVE_SDK/llvm/python3/bin/python3}"

[ -f "$RAWFILE_DIR/python311.zip" ] || {
    echo "错误：请先运行 scripts/stage-headless-hap.sh" >&2
    exit 2
}
[ -f "$STAGED_DIR/lib/python3.11/lib-dynload/_socket.cpython-311-aarch64-linux-ohos.so" ] || {
    echo "错误：staged lib-dynload 不完整" >&2
    exit 2
}

export LD_LIBRARY_PATH="$STAGED_DIR:$STAGED_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$RAWFILE_DIR/python311.zip:$STAGED_DIR/lib/python3.11/lib-dynload"
exec "$PYTHON_BIN" -S "$PROJECT_DIR/probes/python-runtime/probe.py"
