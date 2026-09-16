#!/bin/sh
# 把一个**已经解压好的** OpenHarmony / HarmonyOS SDK 装成工程的 API 26 SDK，并检查
# 它的 releaseType 是不是 Release —— 这一步的存在理由见 docs/appgallery-release.md
# 的「Step 6」：AGC 会因为 `pack.info` 的 `apiVersion.releaseType` 是 `Beta` 而驳回提审，
# 而那个字段只来自 SDK 自身的元数据，工程配置改不了。
#
# 用法：
#   sh scripts/switch-ohos-sdk.sh <SDK 根目录>              # 装好并把工程切过去
#   sh scripts/switch-ohos-sdk.sh <SDK 根目录> --check       # 只看，不写任何东西
#   ALLOW_BETA=1 sh scripts/switch-ohos-sdk.sh <SDK 根目录>  # 明知是 Beta 也要切（自测用）
#   NO_SWITCH=1 sh scripts/switch-ohos-sdk.sh <SDK 根目录>   # 只补装桥接/转码库，不动 .ohos-sdk
#
# <SDK 根目录> 指的是含 ets/ js/ native/ previewer/ toolchains/ 那一层，例如
#   ~/CPPLib/toolchains/harmonyos/26.0.0.38
# 官方 Release 包（ohos-sdk-windows_linux-public_20260829.tar.gz）解出来的层级是
#   ohos-sdk/ohos/{ets,js,native,previewer,toolchains}
# 注意要指到 `ohos` 那一层，不是压缩包解压出来的最外层。
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LINK_NAME="${LINK_NAME:-26}"
OHOS_SDK_DIR="$PROJECT_DIR/.ohos-sdk"
COMPONENTS="ets js native previewer toolchains"

# 本机 PATH 首位被注入了 safe-bin（其 rm 在特定环境下以 126 退出），能用 /bin/rm 就用它。
RM=/bin/rm
[ -x "$RM" ] || RM=rm

CHECK_ONLY=0
ALLOW_BETA="${ALLOW_BETA:-0}"
NO_SWITCH="${NO_SWITCH:-0}"
SDK_ROOT=""
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --allow-beta) ALLOW_BETA=1 ;;
        --no-switch) NO_SWITCH=1 ;;
        -*) echo "错误：未知参数 $arg" >&2; exit 2 ;;
        *) SDK_ROOT="$arg" ;;
    esac
done

[ -n "$SDK_ROOT" ] || {
    echo "用法：sh scripts/switch-ohos-sdk.sh <SDK 根目录> [--check|--allow-beta|--no-switch]" >&2
    exit 2
}
# pwd -P：把软链解开，否则传进来的若是 `.ohos-sdk/26` 这种软链，会把软链套软链地存下去。
SDK_ROOT=$(CDPATH= cd -- "$SDK_ROOT" 2>/dev/null && pwd -P) || {
    echo "错误：SDK 根目录不存在：$SDK_ROOT" >&2
    exit 2
}

# 从 oh-uni-package.json 里取一个字符串字段；文件可能是单行也可能是多行。
json_field() {
    sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

echo "SDK 根目录：$SDK_ROOT"
echo ""
printf '%-12s %-10s %-10s %s\n' "component" "apiVersion" "releaseType" "version"
printf '%-12s %-10s %-10s %s\n' "------------" "----------" "-----------" "-------"

BETA_FOUND=0
for component in $COMPONENTS; do
    meta="$SDK_ROOT/$component/oh-uni-package.json"
    if [ ! -f "$meta" ]; then
        echo "" >&2
        echo "错误：组件元数据缺失：$meta" >&2
        echo "      （说明 <SDK 根目录> 指错了层，或这个 SDK 不是完整包）" >&2
        exit 2
    fi
    api=$(json_field "$meta" apiVersion)
    release_type=$(json_field "$meta" releaseType)
    version=$(json_field "$meta" version)
    printf '%-12s %-10s %-10s %s\n' "$component" "$api" "$release_type" "$version"
    [ "$release_type" = "Release" ] || BETA_FOUND=1
done

echo ""

if [ "$BETA_FOUND" != "0" ]; then
    if [ "$ALLOW_BETA" != "1" ]; then
        cat >&2 <<'EOF'
错误：这个 SDK 不是 Release 版（上面 releaseType 不是 Release 的组件就是证据）。

用它的构建产物会在 pack.info 里写下 "releaseType": "<非 Release>"，
AGC 提审会被驳回：「经检测发现，您的应用使用了 HarmonyOS beta 版本的 API」。

去 OpenHarmony 官方发布页取对应的 Release 包（例如 7.0-Release 的
ohos-sdk-windows_linux-public_20260829.tar.gz，即 Ohos_sdk_public 26.0.0.38），
解压后指到 ohos 那一层。详见 docs/appgallery-release.md 的「Step 6」。

确实只想自测、明知是 Beta 也要切：加 ALLOW_BETA=1（或 --allow-beta）。
EOF
        exit 3
    fi
    echo "警告：SDK 不是 Release 版，但你显式要求继续（ALLOW_BETA=1）。" >&2
    echo "      用这个 SDK 出的包不要拿去提审。" >&2
    echo ""
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "--check：只做了检查，没有改动任何文件。"
    exit 0
fi

TOOLCHAINS_LIB="$SDK_ROOT/toolchains/lib"

# ① 桥接壳：hvigor 按 jar 名找打包/签名工具，而官方 Public SDK 里只有同名可执行文件。
#    （语义与来历见 scripts/toolchain-bridges/README.md）
BRIDGES="$PROJECT_DIR/scripts/toolchain-bridges"
BRIDGE_OUT="$TOOLCHAINS_LIB/.bridges-$$"
echo "→ 编译桥接壳"
OUT="$BRIDGE_OUT" sh "$BRIDGES/build.sh" >/dev/null
for pair in "app_packing_tool.jar" "hap-sign-tool.jar"; do
    cp "$BRIDGE_OUT/$pair" "$TOOLCHAINS_LIB/$pair"
    echo "  装入 $TOOLCHAINS_LIB/$pair"
done
"$RM" -rf "$BRIDGE_OUT"

# ② 打包/签名/资源编译工具本体必须存在且可执行，否则 hvigor 会在很晚的阶段才炸。
#    注意 restool 在 toolchains/ 下，另两个在 toolchains/lib/ 下（hvigor 就是这么找的）。
for tool in "$SDK_ROOT/toolchains/restool" \
            "$TOOLCHAINS_LIB/ohos_packing_tool" \
            "$TOOLCHAINS_LIB/hap-sign-tool"; do
    [ -e "$tool" ] || {
        echo "错误：缺少工具 $tool" >&2
        exit 2
    }
    [ -x "$tool" ] || chmod +x "$tool"
done

# ③ libimage_transcoder_shared.so：OpenHarmony Public SDK 不发这个文件（它是 HarmonyOS SDK
#    的件），hvigor 的 process-resource 会去 toolchains/lib 里取它的路径。本工程未开启
#    resOptions.compression，restool 不会真的加载它，但路径存在与否会影响那道检查。
#    这里放一个指向 libc++_shared.so 的替身（与本工程一直在用的做法一致）。
#    真要开资源压缩，请从 HarmonyOS(DevEco) SDK 取正品放进 toolchains/lib。
transcoder="$TOOLCHAINS_LIB/libimage_transcoder_shared.so"
if [ -e "$transcoder" ]; then
    echo "→ 已有 libimage_transcoder_shared.so，保持不动"
else
    shared="$SDK_ROOT/native/llvm/lib/aarch64-linux-ohos/libc++_shared.so"
    [ -f "$shared" ] || {
        echo "错误：找不到 $shared，无法为 libimage_transcoder_shared.so 建替身。" >&2
        exit 2
    }
    ln -s "$shared" "$transcoder"
    echo "→ 补上 libimage_transcoder_shared.so（指向 libc++_shared.so 的替身）"
fi

if [ "$NO_SWITCH" = "1" ]; then
    echo ""
    echo "NO_SWITCH=1：SDK 已补装完，但没有改 $OHOS_SDK_DIR/$LINK_NAME。"
    exit 0
fi

# ④ 把工程的 .ohos-sdk/<LINK_NAME> 指向这个 SDK。旧的是实体目录就先改名留档，别删。
link="$OHOS_SDK_DIR/$LINK_NAME"
mkdir -p "$OHOS_SDK_DIR"
if [ -L "$link" ]; then
    current=$(readlink "$link")
    if [ "$current" = "$SDK_ROOT" ]; then
        echo "→ .ohos-sdk/$LINK_NAME 已经指向该 SDK，无需改动"
        exit 0
    fi
    echo "→ 旧软链 -> $current"
    "$RM" -f "$link"
elif [ -d "$link" ]; then
    old_meta="$link/toolchains/oh-uni-package.json"
    old_type=$(json_field "$old_meta" releaseType 2>/dev/null || true)
    old_version=$(json_field "$old_meta" version 2>/dev/null || true)
    [ -n "$old_type" ] || old_type="unknown"
    [ -n "$old_version" ] || old_version="unknown"
    backup="$OHOS_SDK_DIR/$LINK_NAME.$(printf '%s' "$old_type" | tr 'A-Z' 'a-z')-$old_version.bak"
    [ -e "$backup" ] && {
        echo "错误：留档路径已存在，不覆盖：$backup" >&2
        echo "      先自己处理它（确认没用再删），或改 LINK_NAME 后再跑。" >&2
        exit 2
    }
    mv "$link" "$backup"
    echo "→ 旧 SDK 目录留档为 .ohos-sdk/$(basename "$backup")（$old_type $old_version）"
fi

ln -s "$SDK_ROOT" "$link"
echo "→ .ohos-sdk/$LINK_NAME -> $SDK_ROOT"

echo ""
echo "完成。下一步："
echo "  sh scripts/build-release-hap.sh    # 出 .hap，并验签"
echo "  sh scripts/build-release-app.sh    # 出 .app（AGC 上传这个）"
echo ""
echo "出包后核对 releaseType（必须是 Release，两处都要看）："
echo "  # .app 那份 pack.info 是缩进过的 JSON，用 \"[[:space:]]*\" 容忍空格再 grep"
echo "  grep -oE '\"releaseType\"[[:space:]]*:[[:space:]]*\"[A-Za-z]*\"' \\"
echo "      entry/build/release/outputs/default/pack.info build/outputs/release/pack.info"
