#!/bin/sh
# Install and launch the current GUI HAP from a DevEco connector shell or a
# privileged device shell. A normal project/app shell cannot invoke bm/aa.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HAP=${HAP:-$PROJECT_DIR/entry/build/default/outputs/default/entry-default-signed.hap}
BUNDLE=${BUNDLE:-com.liangxiaohui.freecad}
ABILITY=${ABILITY:-QAbility}
HDC_BIN=${HDC_BIN:-hdc}
HDC_SERVER=${HDC_SERVER:-127.0.0.1:8711}
HDC_TIMEOUT=${HDC_TIMEOUT:-15}

[ -f "$HAP" ] || {
    echo "错误：找不到 HAP：$HAP" >&2
    exit 1
}

# A privileged HiShell/device shell exposes bm and aa directly. In that
# environment hdc's host-only -s option is invalid, so use native tools.
if command -v bm >/dev/null 2>&1 && command -v aa >/dev/null 2>&1; then
    echo "==> 设备 shell：安装 $HAP"
    bm install -p "$HAP"
    aa force-stop "$BUNDLE" >/dev/null 2>&1 || true
    aa start -b "$BUNDLE" -a "$ABILITY"
    exit 0
fi

command -v "$HDC_BIN" >/dev/null 2>&1 || {
    echo "错误：找不到 hdc；请在 DevEco connector shell 或特权 HiShell 中运行" >&2
    exit 2
}

hdc_host()
{
    if command -v timeout >/dev/null 2>&1; then
        timeout "$HDC_TIMEOUT" "$HDC_BIN" -s "$HDC_SERVER" "$@"
    else
        "$HDC_BIN" -s "$HDC_SERVER" "$@"
    fi
}

TARGET=$(hdc_host list targets 2>/dev/null | awk 'NF && $1 !~ /^\[/ {print $1; exit}')
[ -n "$TARGET" ] || {
    cat >&2 <<EOF
错误：主机 HDC 没有可用 target（服务器：$HDC_SERVER）。
请在 DevEco 中启动/连接设备并确认无线调试授权，然后重试。
当前 HAP：$HAP
EOF
    exit 3
}

echo "==> 主机 HDC target：$TARGET"
hdc_host -t "$TARGET" install -r "$HAP"
hdc_host -t "$TARGET" shell aa force-stop "$BUNDLE" >/dev/null 2>&1 || true
hdc_host -t "$TARGET" shell aa start -b "$BUNDLE" -a "$ABILITY"
