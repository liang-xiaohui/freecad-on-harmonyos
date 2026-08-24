#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FLEXIMIND_ROOT="${FLEXIMIND_ROOT:-/path/to/FlexiMind}"
ABI="${ABI:-arm64-v8a}"
STAGED_DIR="$PROJECT_DIR/entry/libs/$ABI"
RAWFILE_DIR="$PROJECT_DIR/entry/src/main/resources/rawfile"
DEFAULT_OUTPUT="$PROJECT_DIR/entry/build/default/outputs/default"

if [ -z "${HAP:-}" ]; then
    for candidate in \
        "$DEFAULT_OUTPUT/entry-default-signed.hap" \
        "$DEFAULT_OUTPUT/entry-default-unsigned.hap" \
        "$DEFAULT_OUTPUT/entry-default.hap"; do
        if [ -f "$candidate" ]; then
            HAP=$candidate
            break
        fi
    done
fi

[ -n "${HAP:-}" ] && [ -f "$HAP" ] || {
    echo "错误：未找到 HAP；可通过 HAP=/path/to/file.hap 指定" >&2
    exit 2
}
[ -d "$STAGED_DIR" ] || {
    echo "错误：请先运行 scripts/stage-headless-hap.sh" >&2
    exit 2
}

HAP_LIST=$(mktemp)
STAGED_LIST=$(mktemp)
RUNTIME_ZIP=$(mktemp)
trap 'rm -f "$HAP_LIST" "$STAGED_LIST" "$RUNTIME_ZIP"' EXIT HUP INT TERM

unzip -Z1 "$HAP" | sort > "$HAP_LIST"
find "$STAGED_DIR" -type f -printf '%P\n' | while IFS= read -r relative; do
    printf 'libs/%s/%s\n' "$ABI" "$relative"
done | sort > "$STAGED_LIST"

failed=0
while IFS= read -r entry; do
    if ! grep -Fx "$entry" "$HAP_LIST" >/dev/null; then
        echo "MISSING $entry"
        failed=1
    fi
done < "$STAGED_LIST"

for required in \
    "libs/$ABI/libfreecadacceptance.so" \
    "libs/$ABI/libc++_shared.so" \
    "libs/$ABI/FreeCAD.so" \
    "libs/$ABI/Part.so" \
    "libs/$ABI/Mesh.so" \
    "libs/$ABI/Import.so" \
    "libs/$ABI/Materials.so" \
    "libs/$ABI/Sketcher.so" \
    "libs/$ABI/_PartDesign.so" \
    "resources/rawfile/python311.zip" \
    "resources/rawfile/freecad-runtime.zip" \
    "resources/rawfile/freecad_headless_acceptance.py"; do
    if ! grep -Fx "$required" "$HAP_LIST" >/dev/null; then
        echo "MISSING $required"
        failed=1
    fi
done

if grep -Fx "libs/$ABI/libentry.so" "$HAP_LIST" >/dev/null; then
    echo "STALE   libs/$ABI/libentry.so (old native module name)"
    failed=1
fi


for rawfile in python311.zip freecad-runtime.zip freecad_headless_acceptance.py; do
    if [ ! -f "$RAWFILE_DIR/$rawfile" ]; then
        echo "MISSING $RAWFILE_DIR/$rawfile"
        failed=1
    fi
done

for source in \
    "$PROJECT_DIR/entry/oh-package.json5" \
    "$PROJECT_DIR/entry/src/main/cpp/types/libfreecadacceptance/oh-package.json5" \
    "$PROJECT_DIR/entry/src/main/cpp/acceptance.cpp" \
    "$PROJECT_DIR/entry/src/main/ets/pages/Index.ets" \
    "$PROJECT_DIR/entry/src/main/ets/entryability/EntryAbility.ets" \
    "$PROJECT_DIR/entry/src/main/module.json5" \
    "$PROJECT_DIR/probes/freecad-headless/acceptance.py" \
    "$PROJECT_DIR/runtime/fleximind_job_runner.py" \
    "$FLEXIMIND_ROOT/workers/worker-a.py" \
    "$FLEXIMIND_ROOT/workers/worker-b.py" \
    "$FLEXIMIND_ROOT/workers/worker-c.py" \
    "$FLEXIMIND_ROOT/tools/freecad/design_bridge.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/Init.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/registered_base.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/reference_geometry.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/scene_state.py" \
    "$FLEXIMIND_ROOT/tools/freecad/FlexiMindGripDesign/commands.py"; do
    if [ "$source" -nt "$HAP" ]; then
        echo "STALE   $source"
        failed=1
    fi
done

for entry in \
    FlexiMind/fleximind_job_runner.py \
    FlexiMind/workers/worker-a.py \
    FlexiMind/workers/worker-b.py \
    FlexiMind/workers/worker-c.py \
    FlexiMind/workers/manual_gripping_workbench_smoke.py \
    FlexiMind/tools/freecad/design_bridge.py \
    FlexiMind/tools/freecad/FlexiMindGripDesign/registered_base.py \
    FlexiMind/tools/freecad/FlexiMindGripDesign/reference_geometry.py \
    FlexiMind/tools/freecad/FlexiMindGripDesign/scene_state.py \
    FlexiMind/tools/freecad/FlexiMindGripDesign/commands.py \
    Mod/FlexiMindGripDesign/Init.py; do
    if ! unzip -p "$HAP" resources/rawfile/freecad-runtime.zip > "$RUNTIME_ZIP" || \
       ! unzip -Z1 "$RUNTIME_ZIP" | grep -q "^${entry}$"; then
        echo "MISSING resources/rawfile/freecad-runtime.zip:$entry"
        failed=1
    fi
done

newer_runtime=$(find "$STAGED_DIR" "$RAWFILE_DIR" -type f -newer "$HAP" -print | sed -n '1p')
if [ -n "$newer_runtime" ]; then
    echo "STALE   $newer_runtime"
    failed=1
fi

for rawfile in python311.zip freecad-runtime.zip freecad_headless_acceptance.py; do
    staged_hash=$(sha256sum "$RAWFILE_DIR/$rawfile" | awk '{print $1}')
    hap_hash=$(unzip -p "$HAP" "resources/rawfile/$rawfile" | sha256sum | awk '{print $1}')
    if [ "$staged_hash" != "$hap_hash" ]; then
        echo "STALE   resources/rawfile/$rawfile"
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    echo "HAP does not contain the current headless acceptance runtime" >&2
    exit 1
fi

entry_count=$(wc -l < "$STAGED_LIST" | tr -d ' ')
echo "Verified $entry_count staged runtime files in: $HAP"
