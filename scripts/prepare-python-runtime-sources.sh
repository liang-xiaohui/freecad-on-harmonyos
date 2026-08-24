#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHON_SOURCE="$CPP_LIB_ROOT/sources/python/openharmony-master"
LIBFFI_SOURCE="$CPP_LIB_ROOT/sources/libffi/openharmony-master"
PYTHON_REVISION="${PYTHON_REVISION:-a9f6ab8811ad8a65f5cc1dbcaa422c2c9847e509}"
LIBFFI_REVISION="${LIBFFI_REVISION:-4cffe588bdb419ec35af3839a9822eec98699cac}"

clone_pinned_source() {
    repository=$1
    revision=$2
    destination=$3

    if [ ! -d "$destination/.git" ]; then
        mkdir -p "$(dirname "$destination")"
        git clone "$repository" "$destination"
        git -C "$destination" checkout --detach "$revision"
    fi

    actual_revision=$(git -C "$destination" rev-parse HEAD)
    [ "$actual_revision" = "$revision" ] || {
        echo "Unexpected revision in $destination" >&2
        echo "  expected: $revision" >&2
        echo "  actual:   $actual_revision" >&2
        exit 1
    }
}

clone_pinned_source \
    https://gitee.com/openharmony/third_party_python.git \
    "$PYTHON_REVISION" \
    "$PYTHON_SOURCE"
clone_pinned_source \
    https://gitee.com/openharmony/third_party_libffi.git \
    "$LIBFFI_REVISION" \
    "$LIBFFI_SOURCE"

PYTHON_PATCH="$PROJECT_DIR/patches/python-3.11.4/ohos-missing-extensions.patch"
if git -C "$PYTHON_SOURCE" apply --check "$PYTHON_PATCH" 2>/dev/null; then
    git -C "$PYTHON_SOURCE" apply "$PYTHON_PATCH"
elif ! git -C "$PYTHON_SOURCE" apply --reverse --check "$PYTHON_PATCH" 2>/dev/null; then
    echo "Python compatibility patch cannot be applied cleanly: $PYTHON_PATCH" >&2
    exit 1
fi

echo "OpenHarmony Python and libffi sources are ready"
