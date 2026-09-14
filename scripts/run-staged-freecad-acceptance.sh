#!/bin/sh
# Run the same six FreeCAD/OCCT checks used by the HAP acceptance ability,
# directly against the current entry/libs and rawfile staging trees.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

STAGED_DIR="${STAGED_DIR:-$PROJECT_DIR/entry/libs/$ABI}"
RAWFILE_DIR="${RAWFILE_DIR:-$PROJECT_DIR/entry/src/main/resources/rawfile}"
PYTHON_BIN="${PYTHON_BIN:-$NATIVE_SDK/llvm/python3/bin/python3}"
OCCT_BIN="${OCCT_BIN:-$CPP_LIB_ROOT/build/probes/occt-smoke/ohos-$ABI/occt-smoke}"
ACCEPTANCE_SCRIPT="${ACCEPTANCE_SCRIPT:-$RAWFILE_DIR/freecad_headless_acceptance.py}"

for required in \
    "$STAGED_DIR/FreeCAD.so" \
    "$RAWFILE_DIR/python311.zip" \
    "$RAWFILE_DIR/freecad-runtime.zip" \
    "$ACCEPTANCE_SCRIPT" \
    "$PYTHON_BIN" \
    "$OCCT_BIN"; do
    [ -f "$required" ] || {
        echo "错误：验收输入不存在：$required" >&2
        exit 2
    }
done

if [ -n "${FREECAD_PROBE_OUTPUT_DIR:-}" ]; then
    OUTPUT_DIR=$FREECAD_PROBE_OUTPUT_DIR
    mkdir -p "$OUTPUT_DIR"
else
    ARTIFACT_ROOT="${FREECAD_ARTIFACT_ROOT:-/storage/Users/currentUser/codex-freecad-artifacts}"
    mkdir -p "$ARTIFACT_ROOT"
    OUTPUT_DIR=$(mktemp -d "$ARTIFACT_ROOT/gui-acceptance.XXXXXX")
fi

mkdir -p \
    "$OUTPUT_DIR/runtime" \
    "$OUTPUT_DIR/user/home" \
    "$OUTPUT_DIR/user/data" \
    "$OUTPUT_DIR/user/cache" \
    "$OUTPUT_DIR/user/temp"
cp "$RAWFILE_DIR/freecad-runtime.zip" "$OUTPUT_DIR/runtime/freecad-runtime.zip"

PROBE_LD_LIBRARY_PATH="$STAGED_DIR:$STAGED_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
occt_output=$(LD_LIBRARY_PATH="$PROBE_LD_LIBRARY_PATH" \
    "$OCCT_BIN" "$OUTPUT_DIR/occt-smoke.step")
printf '%s\n' "$occt_output"
occt_volume=$(printf '%s\n' "$occt_output" |
    sed -n 's/.*volume=\([^ ]*\).*/\1/p' | tail -n 1)
[ -n "$occt_volume" ] || {
    echo "错误：无法从 OCCT probe 输出解析体积。" >&2
    exit 1
}

export HOME="$OUTPUT_DIR/user/home"
export TMPDIR="$OUTPUT_DIR/user/temp"
export XDG_CONFIG_HOME="$OUTPUT_DIR/user/home"
export XDG_DATA_HOME="$OUTPUT_DIR/user/data"
export XDG_CACHE_HOME="$OUTPUT_DIR/user/cache"
export FREECAD_USER_HOME="$OUTPUT_DIR/user/home"
export FREECAD_USER_DATA="$OUTPUT_DIR/user/data"
export FREECAD_USER_TEMP="$OUTPUT_DIR/user/temp"
export FREECAD_PROBE_ROOT="$STAGED_DIR"
export FREECAD_PROBE_OUTPUT_DIR="$OUTPUT_DIR"
export FREECAD_OCCT_SMOKE_VOLUME="$occt_volume"
export LD_LIBRARY_PATH="$PROBE_LD_LIBRARY_PATH"
export PYTHONPATH="$RAWFILE_DIR/python311.zip:$STAGED_DIR/lib/python3.11/lib-dynload"

"$PYTHON_BIN" -S "$ACCEPTANCE_SCRIPT"

RESULT="$OUTPUT_DIR/freecad-acceptance.json"
[ -s "$RESULT" ] || {
    echo "错误：验收结果未生成：$RESULT" >&2
    exit 1
}

"$PYTHON_BIN" -S -c \
    'import json,sys; result=json.load(open(sys.argv[1], encoding="utf-8")); print(json.dumps(result, ensure_ascii=False, indent=2)); raise SystemExit(0 if result.get("ok") else 1)' \
    "$RESULT"
echo "FreeCAD staged 验收通过（FREECAD_PROBE_FEM=${FREECAD_PROBE_FEM:-OFF}）：$RESULT"
