#!/bin/sh
# Prepare the AddonManager submodule required by FreeCAD 1.1.2 GUI.
# The release source archive omits git submodules, so pin the exact gitlink
# recorded by the FreeCAD 1.1.2 tag instead of using the repository HEAD.
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
SOLVER="${ADDON_MANAGER_SOURCE:-$CPP_LIB_ROOT/sources/freecad/$FREECAD_VERSION/src/Mod/AddonManager}"
REPOSITORY="${ADDON_MANAGER_REPOSITORY:-https://github.com/FreeCAD/AddonManager.git}"
EXPECTED_COMMIT="937b6877239dc78ef59eeefe8099e5f14243eda1"

if [ -f "$SOLVER/CMakeLists.txt" ]; then
    [ -e "$SOLVER/.git" ] || {
        echo "AddonManager exists without Git metadata; cannot verify the required commit: $SOLVER" >&2
        exit 1
    }
    actual=$(git -C "$SOLVER" rev-parse HEAD)
    [ "$actual" = "$EXPECTED_COMMIT" ] || {
        echo "AddonManager commit mismatch: expected $EXPECTED_COMMIT, got $actual" >&2
        exit 1
    }
    echo "AddonManager $EXPECTED_COMMIT is ready: $SOLVER"
    exit 0
fi

if [ -d "$SOLVER" ] && find "$SOLVER" -mindepth 1 -print -quit | grep -q .; then
    echo "AddonManager directory is non-empty but incomplete: $SOLVER" >&2
    echo "Remove only that incomplete directory, then rerun this script." >&2
    exit 1
fi

command -v git >/dev/null 2>&1 || {
    echo "git is required to prepare AddonManager" >&2
    exit 1
}

parent=$(dirname "$SOLVER")
mkdir -p "$parent"
tmp="$SOLVER.tmp.$$"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

echo "==> Downloading AddonManager at FreeCAD 1.1.2 commit $EXPECTED_COMMIT"
git clone --no-checkout "$REPOSITORY" "$tmp"
git -C "$tmp" fetch --depth 1 origin "$EXPECTED_COMMIT"
git -C "$tmp" checkout --detach "$EXPECTED_COMMIT"
[ -f "$tmp/CMakeLists.txt" ] || {
    echo "Downloaded AddonManager does not contain CMakeLists.txt" >&2
    exit 1
}

[ -d "$SOLVER" ] || mkdir -p "$SOLVER"
if find "$SOLVER" -mindepth 1 -print -quit | grep -q .; then
    echo "AddonManager destination changed during download: $SOLVER" >&2
    exit 1
fi
rmdir "$SOLVER"
mv "$tmp" "$SOLVER"
trap - EXIT HUP INT TERM
echo "AddonManager $EXPECTED_COMMIT is ready: $SOLVER"
