#!/bin/sh
# Prepare Microsoft.GSL for FreeCAD 1.1.2 Start/StartGui.
# The release source archive omits git submodules, so pin the exact gitlink
# recorded by the FreeCAD 1.1.2 tag instead of using repository HEAD.
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
SOURCE_DIR="${FREECAD_GSL_SOURCE:-$CPP_LIB_ROOT/sources/freecad/$FREECAD_VERSION/src/3rdParty/GSL}"
REPOSITORY="${FREECAD_GSL_REPOSITORY:-https://github.com/microsoft/GSL.git}"
EXPECTED_COMMIT="543d0dd3fe966ddf20e884b44e5fdbf12cb43784"

if [ -f "$SOURCE_DIR/include/gsl/pointers" ]; then
    [ -e "$SOURCE_DIR/.git" ] || {
        echo "Microsoft.GSL exists without Git metadata; cannot verify the required commit: $SOURCE_DIR" >&2
        exit 1
    }
    actual=$(git -C "$SOURCE_DIR" rev-parse HEAD)
    [ "$actual" = "$EXPECTED_COMMIT" ] || {
        echo "Microsoft.GSL commit mismatch: expected $EXPECTED_COMMIT, got $actual" >&2
        exit 1
    }
    echo "Microsoft.GSL $EXPECTED_COMMIT is ready: $SOURCE_DIR"
    exit 0
fi

if [ -d "$SOURCE_DIR" ] && find "$SOURCE_DIR" -mindepth 1 -print -quit | grep -q .; then
    echo "Microsoft.GSL directory is non-empty but incomplete: $SOURCE_DIR" >&2
    echo "Remove only that incomplete directory, then rerun this script." >&2
    exit 1
fi

command -v git >/dev/null 2>&1 || {
    echo "git is required to prepare Microsoft.GSL" >&2
    exit 1
}

parent=$(dirname "$SOURCE_DIR")
mkdir -p "$parent"
tmp="$SOURCE_DIR.tmp.$$"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

echo "==> Downloading Microsoft.GSL at FreeCAD 1.1.2 commit $EXPECTED_COMMIT"
git clone --no-checkout "$REPOSITORY" "$tmp"
git -C "$tmp" fetch --depth 1 origin "$EXPECTED_COMMIT"
git -C "$tmp" checkout --detach "$EXPECTED_COMMIT"
[ -f "$tmp/include/gsl/pointers" ] || {
    echo "Downloaded Microsoft.GSL does not contain include/gsl/pointers" >&2
    exit 1
}

[ -d "$SOURCE_DIR" ] || mkdir -p "$SOURCE_DIR"
if find "$SOURCE_DIR" -mindepth 1 -print -quit | grep -q .; then
    echo "Microsoft.GSL destination changed during download: $SOURCE_DIR" >&2
    exit 1
fi
rmdir "$SOURCE_DIR"
mv "$tmp" "$SOURCE_DIR"
trap - EXIT HUP INT TERM
echo "Microsoft.GSL $EXPECTED_COMMIT is ready: $SOURCE_DIR"
