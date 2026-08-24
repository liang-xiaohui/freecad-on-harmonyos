#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/gui-hap-$(date '+%Y%m%d-%H%M%S').log"

if hilog -r >/dev/null 2>&1; then
    echo "==> 日志已清空"
else
    echo "==> 无权清空系统日志，继续监听"
fi
echo "==> 原始日志：$LOG_FILE"
echo "==> 启动 FreeCAD GUI HAP（QAbility）；Ctrl+C 停止"
echo "==> 重点看：FreeCADGui / QtForOhos / FreeCADProbe 最后一条日志 + Fault thread / pc backtrace"

hilog | tee "$LOG_FILE" | grep --line-buffered -i -E \
    'com\.freecad\.headless\.acceptance|FreeCADGui|QtForOhos|FreeCADProbe|FreeCAD|QAbility|XComponent|EGL|GLES|gl4es|libGL|Python|PySide|shiboken|dlopen|setupFreecadEnv|materialize|DfxSignalHandler|FaultLogger|ProcessDump|Cpp Crash|Fault thread|#[0-9][0-9].*pc |SIGSEGV|SIGABRT|abort|terminate'