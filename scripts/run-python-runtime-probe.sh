#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

PYTHON_ROOT="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI}"
# Binaries copied to /storage cannot execute unsigned. Use the trusted SDK
# interpreter with the staged runtime until the latter is inside a signed HAP.
PYTHON_BIN="${PYTHON_BIN:-$NATIVE_SDK/llvm/python3/bin/python3}"

[ -x "$PYTHON_BIN" ] || {
    echo "Python is not executable: $PYTHON_BIN" >&2
    exit 1
}
[ -f "$PYTHON_ROOT/lib/python3.11/os.py" ] || {
    echo "Python runtime is missing: $PYTHON_ROOT" >&2
    exit 1
}

export PYTHONHOME="$PYTHON_ROOT"
exec "$PYTHON_BIN" "$PROJECT_DIR/probes/python-runtime/probe.py"
