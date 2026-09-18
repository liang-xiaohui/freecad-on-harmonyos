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
# 打包任务：assembleHap 出模块包（.hap，设备安装/调试用）；
# assembleApp 出应用包（.app，AGC 提审上传用）。两者共用同一套 stage 产物与签名配置。
HVIGOR_TASK="${HVIGOR_TASK:-assembleHap}"

# 对外包 / 内部包的开关。归一化后 export 给 hvigor：entry/hvigorfile.ts 读它来决定
# 要不要在构建期把 EntryAbility 从 module.json5 里剥掉（对外包默认剥掉），
# scripts/stage-gui-hap.sh 读它来决定 runtime 与 rawfile 里放不放 FlexiMind 载荷与
# 验收脚本。三处必须同一次构建里取值一致，否则 verify-gui-hap.sh 会拦下来。
# 用 ON 构建的包只留在开发机和设备上调试，不要上架。
PACKAGE_FLEXIMIND="${PACKAGE_FLEXIMIND:-OFF}"
case "$PACKAGE_FLEXIMIND" in
    ON | on | 1 | true | yes) PACKAGE_FLEXIMIND=ON ;;
    *) PACKAGE_FLEXIMIND=OFF ;;
esac
export PACKAGE_FLEXIMIND

if [ -z "${HVIGOR_JS:-}" ]; then
    HVIGOR_JS=$(find "$CACHE_ROOT" -maxdepth 8 \
        -path '*/node_modules/@ohos/hvigor/bin/hvigor.js' -type f -print 2>/dev/null |
        sort | tail -n 1)
fi
NODE_BIN="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"

# 本机是 HarmonyOS host，没有 JRE，而 hvigor 的打包/签名任务硬编码
# `java -jar <sdk>/toolchains/lib/<tool>.jar`，缺 java 就以 `spawn java ENOENT` 收场。
# scripts/toolchain/java 是一个 sh 桥：把这类调用翻译给 SDK 自带的原生 arm64 工具
# （app_packing_tool / hap-sign-tool），并补上桥壳原本提供的两处行为
# （packing 工具需要显式的 `pack` 子命令；verify-profile 的 -outFile 要包成
# {"content": ...}，否则 hvigor 会报假的 bundleName 不匹配 00303074）。
# 只在 PATH 上找不到真正的 java 时才启用，装了 DevEco / JBR 的机器不受影响。
if ! command -v java >/dev/null 2>&1 && [ -x "$PROJECT_DIR/scripts/toolchain/java" ]; then
    PATH="$PROJECT_DIR/scripts/toolchain:$PATH"
    export PATH
    echo "提示：PATH 上没有 java，改用 scripts/toolchain/java（原生桥）。"
fi

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

# SDK 的 releaseType 会被原样写进 pack.info 的 apiVersion.releaseType，而 AGC 就是拿这**一个**
# 字段判「有没有用 beta 版 API」的 —— 工程配置里写什么都没用（取值来自 SDK 的
# oh-uni-package.json）。官方 Public SDK 的 Beta 快照会长期停留在旧构建号，很容易一路用下去，
# 所以 release 出包这条路直接拦下来。细节与换 SDK 的步骤见 docs/appgallery-release.md「Step 6」。
SDK_META="$DEVECO_SDK_HOME/toolchains/oh-uni-package.json"
if [ -f "$SDK_META" ]; then
    SDK_RELEASE_TYPE=$(sed -n 's/.*"releaseType"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SDK_META" | head -n 1)
    SDK_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SDK_META" | head -n 1)
    if [ "$BUILD_MODE" = "release" ] && [ -n "$SDK_RELEASE_TYPE" ] && [ "$SDK_RELEASE_TYPE" != "Release" ]; then
        if [ "${ALLOW_BETA_SDK:-0}" != "1" ]; then
            echo "错误：release 构建用的是 $SDK_RELEASE_TYPE 版 SDK（$SDK_VERSION）。" >&2
            echo "      pack.info 的 apiVersion.releaseType 会写成 \"$SDK_RELEASE_TYPE\"，" >&2
            echo "      AGC 提审会以「使用了 HarmonyOS beta 版本的 API」驳回。" >&2
            echo "      换 Release 版 SDK：sh scripts/switch-ohos-sdk.sh <SDK 根目录>" >&2
            echo "      （确要硬来：ALLOW_BETA_SDK=1，但出的包不要提审）" >&2
            exit 3
        fi
        echo "警告：ALLOW_BETA_SDK=1，用 $SDK_RELEASE_TYPE 版 SDK（$SDK_VERSION）出 release 包。" >&2
    elif [ -n "$SDK_RELEASE_TYPE" ]; then
        echo "SDK: $SDK_RELEASE_TYPE $SDK_VERSION（$DEVECO_SDK_HOME）"
    fi
fi

cd "$PROJECT_DIR"

# assembleApp 是工程级任务，不接受 -p module。
if [ "$HVIGOR_TASK" = "assembleApp" ]; then
    exec "$NODE_BIN" "$HVIGOR_JS" \
        -p "product=$PRODUCT" \
        -p "buildMode=$BUILD_MODE" \
        assembleApp --no-daemon --no-parallel --info
fi

exec "$NODE_BIN" "$HVIGOR_JS" \
    -p "module=$MODULE_TARGET" \
    -p "product=$PRODUCT" \
    -p "buildMode=$BUILD_MODE" \
    "$HVIGOR_TASK" --no-daemon --no-parallel --info
