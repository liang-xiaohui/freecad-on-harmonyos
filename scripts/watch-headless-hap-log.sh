#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/headless-hap-$(date '+%Y%m%d-%H%M%S').log"

if hilog -r >/dev/null 2>&1; then
    echo "==> 日志已清空"
else
    echo "==> 无权清空系统日志，继续监听"
fi
echo "==> 原始日志：$LOG_FILE"
echo "==> 启动 FreeCAD 验收 HAP；Ctrl+C 停止"

hilog | tee "$LOG_FILE" | grep --line-buffered -i -E \
    'com\.freecad\.headless\.acceptance|FreeCADProbe|FreeCAD|OCCT|Python|DfxSignalHandler|FaultLogger|ProcessDump|Cpp Crash|Fault thread|#[0-9][0-9].*pc '
