#!/bin/sh
# Build and sign the GUI HAP with the project-local API 26 SDK overlay. The
# overlay supplies host-executable bridges for the native packing/sign tools.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE_ROOT="${CACHE_ROOT:-/storage/Users/currentUser/.cache}"
DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$PROJECT_DIR/.ohos-sdk/26}"
BUILD_MODE="${BUILD_MODE:-debug}"
PRODUCT="${PRODUCT:-default}"
MODULE_TARGET="${MODULE_TARGET:-entry@default}"

if [ -z "${HVIGOR_JS:-}" ]; then
    HVIGOR_JS=$(find "$CACHE_ROOT" -maxdepth 8 \
        -path '*/node_modules/@ohos/hvigor/bin/hvigor.js' -type f -print 2>/dev/null |
        sort | tail -n 1)
fi
NODE_BIN="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"

[ -n "$HVIGOR_JS" ] && [ -f "$HVIGOR_JS" ] || {
    echo "错误：找不到 Hvigor；请用 HVIGOR_JS 指定 @ohos/hvigor/bin/hvigor.js。" >&2
    exit 2
}
[ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ] || {
    echo "错误：找不到可执行的 Node.js；请用 NODE_BIN 指定。" >&2
    exit 2
}

HVIGOR_PACKAGE=$(CDPATH= cd -- "$(dirname -- "$HVIGOR_JS")/.." && pwd)
NODE_MODULES=$(CDPATH= cd -- "$HVIGOR_PACKAGE/../.." && pwd)
[ -f "$NODE_MODULES/@ohos/hvigor-ohos-plugin/package.json" ] || {
    echo "错误：Hvigor 缓存缺少 @ohos/hvigor-ohos-plugin：$NODE_MODULES" >&2
    exit 2
}

OHOS_PACKING_TOOL="${OHOS_PACKING_TOOL:-$DEVECO_SDK_HOME/toolchains/lib/ohos_packing_tool}"
OHOS_HAP_SIGN_TOOL="${OHOS_HAP_SIGN_TOOL:-$DEVECO_SDK_HOME/toolchains/lib/hap-sign-tool}"
for required in \
    "$DEVECO_SDK_HOME/ets/oh-uni-package.json" \
    "$DEVECO_SDK_HOME/native/oh-uni-package.json" \
    "$DEVECO_SDK_HOME/toolchains/oh-uni-package.json" \
    "$OHOS_PACKING_TOOL" \
    "$OHOS_HAP_SIGN_TOOL"; do
    [ -e "$required" ] || {
        echo "错误：HAP 构建 SDK 输入不存在：$required" >&2
        exit 2
    }
done

export DEVECO_SDK_HOME OHOS_PACKING_TOOL OHOS_HAP_SIGN_TOOL
export NODE_PATH="$NODE_MODULES${NODE_PATH:+:$NODE_PATH}"

cd "$PROJECT_DIR"
exec "$NODE_BIN" "$HVIGOR_JS" \
    -p "module=$MODULE_TARGET" \
    -p "product=$PRODUCT" \
    -p "buildMode=$BUILD_MODE" \
    assembleHap --no-daemon --no-parallel --info
